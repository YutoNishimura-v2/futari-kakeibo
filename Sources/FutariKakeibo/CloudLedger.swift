import CloudKit
import Combine
import CoreData
import Foundation
import FutariDomain

enum InviteIssue: Error, Equatable {
    case signedOut, expired, accountMismatch, otherPartner, retry

    var message: String {
        switch self {
        case .signedOut: return "iCloudにサインインしていないため、招待を使えません。"
        case .expired: return "この招待リンクは期限切れか、無効になっています。"
        case .accountMismatch: return "招待先のApple Accountを確認できず、国や地域の設定が関係している可能性があります。"
        case .otherPartner: return "この家計簿に招待できるパートナーは1人です。"
        case .retry: return "招待を処理できませんでした。"
        }
    }

    var nextAction: String {
        switch self {
        case .signedOut: return "「設定」でiCloudにサインイン"
        case .expired: return "招待した人に新しいリンクを依頼"
        case .accountMismatch: return "招待先と相手のiCloudのメールアドレス・国や地域を確認"
        case .otherPartner: return "招待先のメールアドレスを確認"
        case .retry: return "通信を確認して再試行"
        }
    }

    static func classify(_ error: Error, accepting: Bool) -> Self {
        if let bookError = error as? BookError {
            switch bookError {
            case .unresolvedPartner: return .accountMismatch
            case .otherPartner: return .otherPartner
            default: return .retry
            }
        }
        guard let error = error as? CKError else { return .retry }
        switch error.code {
        case .notAuthenticated: return .signedOut
        case .unknownItem: return accepting ? .expired : .accountMismatch
        case .zoneNotFound, .userDeletedZone: return accepting ? .expired : .retry
        case .permissionFailure, .serverRejectedRequest: return .accountMismatch
        case .partialFailure:
            let issues = (error.partialErrorsByItemID ?? [:]).values.map { classify($0, accepting: accepting) }
            if issues.contains(.signedOut) { return .signedOut }
            if issues.contains(.accountMismatch) { return .accountMismatch }
            return !issues.isEmpty && issues.allSatisfy { $0 == .expired } ? .expired : .retry
        default: return .retry
        }
    }
}

@MainActor
final class CloudLedger: ObservableObject, BookRepository {
    private static let model = ledgerModel()
    @Published private(set) var snapshot: LedgerSnapshot?
    @Published private(set) var books: [Book] = []
    @Published private(set) var lockedBooks: [Book] = []
    @Published private(set) var bookTitles: [Book: String] = [:]
    @Published private(set) var notice: String?
    @Published private(set) var canRetry = false
    @Published private(set) var canShare = false
    @Published private(set) var shareBusy = false
    @Published private(set) var partnerNotice: String?
    @Published private(set) var inviteIssue: InviteIssue?
    @Published private(set) var isBookShared = false
    @Published private(set) var pendingQuickRecord = false

    private let cloud: CKContainer?
    private let configuredPlan: Plan
    private var accessByBook: [Book: ProAccess] = [:]
    private var verifiedPurchases: [String: ProGrant] = [:]
    private var purchaseDestinationReady = false
    private var purchaseSaveFailed = false
    private var purchaseVerificationFailed = false
    lazy var purchases = ProPurchases(ledger: self)
    private var purchaseTimer: Task<Void, Never>?
    private var purchaseBoundary: Date?
    var access: ProAccess { snapshot.map { access(for: $0.book) } ?? .free }
    var plan: Plan { access.plan }
    var personalPlan: Plan {
        access(from: verifiedPurchases.values, at: .now).plan
    }
    var canPurchasePro: Bool {
        !shareBusy && !storageError && !storeLoadFailed && (snapshot?.member != nil || !lockedBooks.isEmpty)
    }

    private func access(for book: Book) -> ProAccess {
        if configuredPlan.allowsProFeatures { return .lifetime }
        guard let grant = accessByBook[book], grant.expiresAt.map({ $0 > .now }) ?? true else { return .free }
        return grant
    }

    private func access<S: Sequence>(from grants: S, at date: Date) -> ProAccess where S.Element == ProGrant {
        configuredPlan.allowsProFeatures ? .lifetime : ProGrant.access(from: grants, at: date)
    }
    private var container: NSPersistentCloudKitContainer?
    private var privateStore: NSPersistentStore?
    private var sharedStore: NSPersistentStore?
    private var observations: [NSObjectProtocol] = []
    private var account: CKAccountStatus?
    private var currentUserID: CKRecord.ID?
    private var accountCheck = 0
    private var accountError = false
    private var syncFailures: Set<String> = []
    private var storeLoadFailed = false
    private var importedStores: Set<String> = []
    private var storageError = false
    private var recurringError = false
    private var migrationPending = true
    private var message: String?
    private var failedInvite: CKShare.Metadata?
    private var joinMergeFailed = false
    private var awaitingZone: CKRecordZone.ID? {
        didSet {
            let zone = awaitingZone.map { ["name": $0.zoneName, "owner": $0.ownerName] }
            UserDefaults.standard.set(zone, forKey: "ledger.awaitingZone")
        }
    }
    private var pendingLeave: CKRecordZone.ID?
    private var selectedID = ScreenshotDemo.isEnabled ? nil : UserDefaults.standard.string(forKey: "ledger.selectedBook")
    private var context: NSManagedObjectContext? { container?.viewContext }
    private var noAccount: Bool { account == .noAccount || account == .restricted }
    var sharingAccountIssue: InviteIssue? { account == .noAccount ? .signedOut : nil }
    var canRetryInvite: Bool { failedInvite != nil }
    private var initialPrivateImportFinished: Bool {
        privateStore.map { importedStores.contains($0.identifier) } ?? false
    }
    private var privateLedgerReady: Bool {
        cloud == nil || noAccount || (account == .available && initialPrivateImportFinished)
    }
    private var mayCreatePrimary: Bool {
        privateLedgerReady && (cloud == nil || noAccount || sharedStore.map { importedStores.contains($0.identifier) } == true)
    }

    private func readyForRecurring(in store: NSPersistentStore) -> Bool {
        cloud == nil || noAccount
            || (account == .available && !accountError && importedStores.contains(store.identifier))
    }

    init(plan: Plan = .configured) {
        if ScreenshotDemo.isEnabled {
            configuredPlan = ScreenshotDemo.isFree ? .free : .pro
            cloud = nil
            openScreenshotBook()
            return
        }
        configuredPlan = plan
        if let zone = UserDefaults.standard.dictionary(forKey: "ledger.awaitingZone"),
           let name = zone["name"] as? String, let owner = zone["owner"] as? String {
            awaitingZone = CKRecordZone.ID(zoneName: name, ownerName: owner)
        }
        if let id = Bundle.main.object(forInfoDictionaryKey: "LedgerCloudContainer") as? String,
           id.hasPrefix("iCloud."), id != "iCloud.example.futarikakeibo" {
            cloud = CKContainer(identifier: id)
        } else {
            cloud = nil
        }
        open()
    }

    private func openScreenshotBook() {
        do {
            let stack = NSPersistentCloudKitContainer(name: "FutariScreenshot", managedObjectModel: Self.model)
            let store = try stack.persistentStoreCoordinator.addPersistentStore(
                ofType: NSInMemoryStoreType, configurationName: nil, at: nil
            )
            container = stack
            privateStore = store
            migrationPending = false
            refresh()
            guard let snapshot else { throw BookError.unavailable }
            let book = snapshot.book
            try rename(Names(first: "はる", second: "あおい"), replacing: snapshot.names, in: book)
            for expense in try ScreenshotDemo.expenses() {
                try add(expense, to: book)
            }
            if plan.allowsProFeatures, let month = ScreenshotDemo.day.map(Month.init(containing:)) {
                try setBudget(18_000, category: .groceries, month: month, in: book)
                try setBudget(4_000, category: .dining, month: month, in: book)
            }
        } catch {
            NSLog("Screenshot book: %@", String(describing: error))
            storeLoadFailed = true
            snapshot = nil
            updateNotice()
        }
    }

    private func open() {
        do {
            let stack = NSPersistentCloudKitContainer(name: "FutariLedger", managedObjectModel: Self.model)
            let directory = NSPersistentContainer.defaultDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            func description(_ scope: CKDatabase.Scope, file: String) -> NSPersistentStoreDescription {
                let store = NSPersistentStoreDescription(url: directory.appendingPathComponent(file))
                store.shouldAddStoreAsynchronously = false
                store.shouldMigrateStoreAutomatically = true
                store.shouldInferMappingModelAutomatically = true
                store.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                store.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                if let id = cloud?.containerIdentifier {
                    let options = NSPersistentCloudKitContainerOptions(containerIdentifier: id)
                    options.databaseScope = scope
                    store.cloudKitContainerOptions = options
                }
                return store
            }

            let owned = description(.private, file: "FutariPrivate.sqlite")
            let invited = description(.shared, file: "FutariShared.sqlite")
            stack.persistentStoreDescriptions = [owned, invited]
            watch(stack)
            // With synchronous store descriptions the stores are attached before this call returns.
            stack.loadPersistentStores { _, error in
                if let error { NSLog("Ledger store: %@", String(describing: error)) }
            }
            let coordinator = stack.persistentStoreCoordinator
            container = stack
            privateStore = owned.url.flatMap { coordinator.persistentStore(for: $0) }
            sharedStore = invited.url.flatMap { coordinator.persistentStore(for: $0) }
            storeLoadFailed = privateStore == nil || sharedStore == nil
            refresh()
        } catch {
            NSLog("Ledger open: %@", String(describing: error))
            storeLoadFailed = true
            updateNotice()
        }
    }

    private func watch(_ stack: NSPersistentCloudKitContainer) {
        let center = NotificationCenter.default
        observations = [
            center.addObserver(forName: .NSPersistentStoreRemoteChange,
                               object: stack.persistentStoreCoordinator, queue: nil) { [weak self, weak stack] _ in
                Task { @MainActor in
                    guard let self, let stack, self.container === stack else { return }
                    self.context?.reset()
                    self.refresh()
                }
            },
            center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                               object: stack, queue: nil) { [weak self, weak stack] note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
                Task { @MainActor in
                    guard let self, let stack, self.container === stack else { return }
                    let eventID = "\(event.storeIdentifier)/\(event.type.rawValue)"
                    if event.succeeded { self.syncFailures.remove(eventID) }
                    else { self.syncFailures.insert(eventID) }
                    if event.succeeded && event.type == .import {
                        self.importedStores.insert(event.storeIdentifier)
                        self.context?.reset()
                        self.refresh()
                    } else {
                        self.updateNotice()
                    }
                }
            },
            center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.currentUserID = nil
                    await self.checkAccount()
                }
            }
        ]
    }

    private func migrate(in context: NSManagedObjectContext, store: NSPersistentStore,
                         preferred: LedgerBookRow?) throws {
        let defaults = UserDefaults.standard
        let key = "ledger.legacyDestination"
        let completion = "ledger.legacyImported"
        if defaults.bool(forKey: completion) { return }
        let legacy = try readLegacyLedger()
        guard !legacy.expenses.isEmpty || !legacy.settled.isEmpty || legacy.names != Names() else {
            defaults.set(true, forKey: completion)
            return
        }
        let savedDestination = defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
        let previousTarget = try savedDestination.flatMap { id in
            try rows(in: context, store: store).first { $0.id == id }
        }
        let book = previousTarget ?? preferred
        let destination = book?.id ?? savedDestination ?? UUID()
        defaults.set(destination.uuidString, forKey: key)
        let target = book ?? LedgerBookRow(context: context)
        if book == nil {
            context.assign(target, to: store)
            target.id = destination
        }

        do {
            let existing: Set<UUID> = book == nil ? [] : Set(try expenses(in: target, context: context).map(\.id))
            for expense in legacy.expenses where !existing.contains(expense.id) {
                try insert(expense, in: target, store: store, context: context)
            }
            let edits = book == nil ? [:] : try latestEdits(in: target, context: context)
            if edits["first"] == nil {
                insertEdit("first", value: legacy.names.first, in: target, store: store, context: context)
            }
            if edits["second"] == nil {
                insertEdit("second", value: legacy.names.second, in: target, store: store, context: context)
            }
            for month in legacy.settled where edits[monthKey(month)] == nil {
                insertEdit(monthKey(month), value: "1", in: target, store: store, context: context)
            }
            if !target.migrated { target.migrated = true }
            if context.hasChanges { try context.save() }
            defaults.set(true, forKey: completion)
        } catch {
            context.rollback()
            throw error
        }
    }

    func activate() async {
        await checkAccount()
        guard !shareBusy, account == .available, let cloud, let container,
              let book = snapshot?.book, !book.isGuest,
              let (row, _, _) = try? activeRow(in: book),
              let share = try? container.fetchShares(matching: [row.objectID])[row.objectID],
              let live = try? await cloud.privateCloudDatabase.record(for: share.recordID) as? CKShare
        else { return }
        guard snapshot?.book == book, account == .available, !shareBusy else { return }
        observePartner(in: live, book: book)
        updateNotice()
    }

    private func checkAccount() async {
        guard let cloud else { refresh(); return }
        accountCheck += 1
        let check = accountCheck
        do {
            let status = try await cloud.accountStatus()
            guard check == accountCheck else { return }
            if account == .available && status != .available {
                importedStores.removeAll()
            }
            account = status
            accountError = status == .couldNotDetermine || status == .temporarilyUnavailable
            if status == .available {
                do {
                    let id = try await cloud.userRecordID()
                    guard check == accountCheck else { return }
                    currentUserID = id.recordName == CKCurrentUserDefaultName ? nil : id
                } catch {
                    guard check == accountCheck else { return }
                    NSLog("Ledger purchase member: %@", String(describing: error))
                }
            } else {
                currentUserID = nil
            }
        } catch {
            guard check == accountCheck else { return }
            accountError = true
        }
        refresh()
    }

    func retry() async {
        guard !shareBusy else { return }
        if storeLoadFailed { reopen() }
        if let pendingLeave {
            await purgeSharedZone(pendingLeave)
            return
        }
        await checkAccount()
        await purchases.activate()
    }

    private func reopen() {
        // Reattach the same SQLite files, preserving queued local writes and history.
        context?.reset()
        if let coordinator = container?.persistentStoreCoordinator {
            do {
                for store in coordinator.persistentStores {
                    try coordinator.remove(store)
                }
            } catch {
                NSLog("Ledger store detach: %@", String(describing: error))
                let attached = coordinator.persistentStores
                if let privateStore, !attached.contains(privateStore) { self.privateStore = nil }
                if let sharedStore, !attached.contains(sharedStore) { self.sharedStore = nil }
                refresh()
                return
            }
        }
        observations.forEach { NotificationCenter.default.removeObserver($0) }
        observations.removeAll()
        privateStore = nil
        sharedStore = nil
        container = nil
        storageError = false
        storeLoadFailed = false
        importedStores.removeAll()
        syncFailures.removeAll()
        open()
    }

    private func updateNotice() {
        canShare = account == .available && cloud != nil && snapshot?.member != nil
            && !storageError && !storeLoadFailed
        canRetry = storageError || storeLoadFailed || recurringError || purchaseSaveFailed || purchaseVerificationFailed
            || joinMergeFailed
            || pendingLeave != nil
            || (!noAccount && (accountError || !syncFailures.isEmpty))
        if joinMergeFailed {
            notice = "記録を共有先に追加できませんでした。再試行してください"
        } else if storageError || storeLoadFailed {
            notice = "家計簿を読み込めませんでした。再試行してください"
        } else if purchaseSaveFailed {
            notice = "購入情報を家計簿に保存できませんでした"
        } else if purchaseVerificationFailed {
            notice = "購入情報を確認できませんでした"
        } else if recurringError {
            notice = "定期入力を記録できませんでした"
        } else if account == .restricted {
            notice = "共有するには設定でiCloudの利用制限を確認してください"
        } else if cloud == nil && !ScreenshotDemo.isEnabled {
            notice = "この端末に記録します"
        } else if awaitingZone != nil && syncFailures.isEmpty && !accountError {
            notice = "共有の家計簿を読み込んでいます"
        } else if canRetry {
            notice = "同期できていません。通信を確認して再試行してください"
        } else if snapshot == nil && !mayCreatePrimary {
            notice = "iCloudの家計簿を読み込んでいます"
        } else {
            notice = message
        }
    }

    func select(_ book: Book) {
        guard books.contains(book), !shareBusy else { return }
        remember(book)
        message = nil
        refresh()
    }

    private func remember(_ book: Book) {
        selectedID = book.id.uuidString
        if !ScreenshotDemo.isEnabled {
            UserDefaults.standard.set(selectedID, forKey: "ledger.selectedBook")
        }
    }

    func refresh() {
        // The live accessor already returns free when the timer fires at expiry.
        let previousAccess = snapshot.flatMap { accessByBook[$0.book] } ?? .free
        defer {
            updateNotice()
            if !ScreenshotDemo.isEnabled {
                let current = storageError ? nil : snapshot
                WidgetPublishing.publish(access: access, snapshot: current, bookTitle: current.map { title(for: $0.book) })
                if previousAccess != access {
                    Task { await SettlementReminder.shared.refresh(access: access) }
                }
            }
        }
        purchaseDestinationReady = false
        guard let context, let container else { return }
        do {
            // Titled rows are the additional Pro books. The primary book never carries a title.
            let ownedRows = try privateStore.map { try rows(in: context, store: $0) } ?? []
            var owned = ownedRows.filter { $0.title == nil }
            let titledOwned = ownedRows.filter { $0.title != nil }
            let shared = noAccount ? [] : try sharedStore.map { try rows(in: context, store: $0) } ?? []
            let objectIDs = (ownedRows + shared).map(\.objectID)
            let shares = cloud == nil || noAccount || objectIDs.isEmpty ? [:] :
                try container.fetchShares(matching: objectIDs)
            if privateLedgerReady, !shareBusy, let privateStore {
                if migrationPending {
                    let preferred = try preferredOwned(owned, shares: shares, context: context)
                    try migrate(in: context, store: privateStore, preferred: preferred)
                    migrationPending = false
                    owned = try rows(in: context, store: privateStore).filter { $0.title == nil }
                }
                if mayCreatePrimary, !storeLoadFailed, owned.isEmpty, (awaitingZone == nil || noAccount) {
                    let book = LedgerBookRow(context: context)
                    context.assign(book, to: privateStore)
                    book.id = UUID()
                    do { try context.save() } catch { context.rollback(); throw error }
                    owned = [book]
                }
            }
            let candidates: [(Book, LedgerBookRow)] = (owned + titledOwned + shared).compactMap { row in
                guard let id = row.id else { return nil }
                let isGuest = row.objectID.persistentStore == sharedStore
                if isGuest, let pendingLeave, shares[row.objectID]?.recordID.zoneID == pendingLeave { return nil }
                return (Book(id: id, isGuest: isGuest), row)
            }.sorted { $0.0.id.uuidString < $1.0.id.uuidString }
            let hasSharedOwned = owned.contains { shares[$0.objectID] != nil }
            var available: [(Book, LedgerBookRow)] = []
            var locked: [Book] = []
            var titles: [Book: String] = [:]
            var bookEdits: [Book: [String: LedgerEditRow]] = [:]
            var nextAccess: [Book: ProAccess] = [:]
            let now = Date.now
            var boundary: Date?
            purchaseSaveFailed = false
            for (book, row) in candidates {
                var edits = try latestEdits(in: row, context: context)
                let share = shares[row.objectID]
                let bookMember = member(for: book, share: share)
                let partner = share.flatMap(activePartners)?.first { $0.acceptanceStatus == .accepted }
                let participantID = share?.currentUserParticipant?.userIdentity.userRecordID
                let currentUserID = self.currentUserID ?? participantID.flatMap {
                    $0.recordName == CKCurrentUserDefaultName ? nil : $0
                }
                let partnerID = book.isGuest ? currentUserID : partner?.userIdentity.userRecordID
                let partnerPrefix = partnerID.map { "pro/second/\($0.recordName)/" }
                let memberPrefix: String?
                switch bookMember {
                case .first?: memberPrefix = "pro/first/"
                case .second?: memberPrefix = partnerPrefix
                case nil: memberPrefix = nil
                }
                if !shareBusy, bookMember != nil, !verifiedPurchases.isEmpty {
                    let canWriteGrant = !book.isGuest || container.canUpdateRecord(forManagedObjectWith: row.objectID)
                    if memberPrefix == nil || !canWriteGrant {
                        purchaseSaveFailed = true
                    } else if let memberPrefix, let store = row.objectID.persistentStore {
                        do {
                            edits.merge(try savePurchases(prefix: memberPrefix, in: row, store: store,
                                                          context: context, edits: edits)) { _, saved in saved }
                            purchaseDestinationReady = true
                        } catch {
                            purchaseSaveFailed = true
                            NSLog("Ledger purchases: %@", String(describing: error))
                        }
                    }
                }
                let grants = edits.compactMap { key, row -> ProGrant? in
                    guard key.hasPrefix("pro/first/") || partnerPrefix.map({ key.hasPrefix($0) }) == true else {
                        return nil
                    }
                    return purchaseGrant(in: row)
                }
                let bookAccess = bookMember == nil ? access(from: [], at: now) : access(from: grants, at: now)
                nextAccess[book] = bookAccess
                if let expiry = bookAccess.expiresAt { boundary = min(boundary ?? expiry, expiry) }
                for grant in grants where !grant.revoked && grant.purchasedAt > now {
                    boundary = min(boundary ?? grant.purchasedAt, grant.purchasedAt)
                }
                if let title = row.title {
                    titles[book] = title
                    if !bookAccess.plan.allowsProFeatures {
                        if bookMember != nil {
                            locked.append(book)
                        }
                        continue
                    }
                } else if !book.isGuest, share == nil, !mayCreatePrimary || hasSharedOwned,
                          try isEmpty(row, context: context) {
                    continue
                }
                available.append((book, row))
                bookEdits[book] = edits
            }
            accessByBook = nextAccess
            schedulePurchaseRefresh(at: boundary)
            books = available.map(\.0)
            lockedBooks = locked
            bookTitles = titles
            if !shareBusy, privateLedgerReady, account == .available,
               let zone = awaitingZone, let joined = candidates.first(where: {
                $0.0.isGuest && shares[$0.1.objectID]?.recordID.zoneID == zone
            }) {
                if member(for: joined.0, share: shares[joined.1.objectID]) != .second {
                    joinMergeFailed = true
                } else if let edits = bookEdits[joined.0] {
                    do {
                        let solo = try preferredOwned(owned.filter {
                            shares[$0.objectID] == nil && $0.id.map(hadPartner) == false
                        }, shares: shares, context: context)
                        if let solo, try mergeSoloEntries(from: solo, into: joined.1, edits: edits, context: context) {
                            message = "精算済みの月にも記録を追加しました。支払い済みの金額を確認してください"
                        }
                        remember(joined.0)
                        awaitingZone = nil
                        joinMergeFailed = false
                    } catch {
                        context.rollback()
                        joinMergeFailed = true
                        NSLog("Ledger join: %@", String(describing: error))
                    }
                } else {
                    awaitingZone = nil
                    joinMergeFailed = false
                }
            }

            let guests = candidates.filter { $0.0.isGuest }
            if let previous = snapshot?.book, previous.isGuest, !noAccount,
               !guests.contains(where: { $0.0 == previous }) {
                message = "共有が終了しました。共有するには招待を受け直してください"
            }
            if !shareBusy {
                do {
                    try generateRecurring(in: available.filter { access(for: $0.0).plan.allowsProFeatures },
                                          edits: bookEdits, shares: shares,
                                          container: container, context: context)
                    recurringError = false
                } catch {
                    NSLog("Ledger recurring: %@", String(describing: error))
                    recurringError = true
                }
                for (book, row) in available {
                    guard let edits = bookEdits[book] else { continue }
                    try purgeDeletedExpenseRows(in: row, book: book, edits: edits,
                                                container: container, context: context)
                }
            }
            let preferred = try preferredOwned(owned, shares: shares, context: context)
            let primary = available.first { $0.1 === preferred }
            let selected = available.first {
                $0.0.id.uuidString == selectedID && ($0.0.isGuest || titles[$0.0] != nil || $0.1 === preferred)
            }
            let establishedPrimary: (Book, LedgerBookRow)? = try primary.flatMap { candidate in
                if shares[candidate.1.objectID] != nil { return candidate }
                return try isEmpty(candidate.1, context: context) ? nil : candidate
            }
            let guest = available.first { $0.0.isGuest && member(for: $0.0, share: shares[$0.1.objectID]) == .second }
            let additional = available.first { titles[$0.0] != nil }
            partnerNotice = nil
            isBookShared = false
            guard let (book, row) = selected ?? establishedPrimary ?? guest ?? primary ?? additional
                    ?? available.first(where: { $0.0.isGuest }) else {
                snapshot = nil
                storageError = false
                return
            }

            let share = shares[row.objectID]
            if !book.isGuest && account == .available { observePartner(in: share, book: book) }
            isBookShared = book.isGuest || (share.map(activePartners)?.contains { $0.acceptanceStatus == .accepted } ?? false)
            let member = self.member(for: book, share: share)
            let plan = access(for: book).plan
            let edits = bookEdits[book] ?? [:]
            var names = Names(first: edits["first"]?.value ?? Names.firstDefault,
                              second: edits["second"]?.value ?? Names.secondDefault)
            if share != nil && names.first == Names.firstDefault { names.first = "持ち主" }
            var settlementDates: [Month: Date] = [:]
            for (key, edit) in edits where key.hasPrefix("month/") && edit.value == "1" {
                guard let seconds = Int(key.dropFirst(6)), let date = edit.time else { continue }
                let month = Month(containing: Date(timeIntervalSince1970: TimeInterval(seconds)))
                settlementDates[month] = max(date, settlementDates[month] ?? .distantPast)
            }
            let custom = plan.allowsProFeatures ? customCategories(from: edits) : [:]
            let expenses = try self.expenses(in: row, context: context, edits: edits,
                                             registeredCategories: Set(custom.keys))
            snapshot = LedgerSnapshot(book: book, member: member, names: names,
                                      expenses: expenses, settlementDates: settlementDates,
                                      budgets: plan.allowsProFeatures ? budgets(from: edits) : [:],
                                      recurring: plan.allowsProFeatures ? try templates(from: edits) : [],
                                      customCategories: custom,
                                      shopping: plan.allowsProFeatures ? shoppingItems(from: edits) : [])
            storageError = false
        } catch {
            NSLog("Ledger refresh: %@", String(describing: error))
            storageError = true
        }
    }

    func updatePurchases(_ purchases: [String: ProGrant], verificationFailed: Bool) throws -> Bool {
        verifiedPurchases = purchases
        purchaseVerificationFailed = verificationFailed
        refresh()
        if storageError || storeLoadFailed || purchaseSaveFailed { throw PurchaseError.save }
        return purchases.isEmpty || purchaseDestinationReady
    }

    func purchaseUpdateFailed() {
        purchaseVerificationFailed = true
        updateNotice()
    }

    private func purchaseGrant(in row: LedgerEditRow?) -> ProGrant? {
        guard let data = row?.value?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProGrant.self, from: data)
    }

    private func savePurchases(prefix: String, in book: LedgerBookRow, store: NSPersistentStore,
                               context: NSManagedObjectContext, edits: [String: LedgerEditRow]) throws
        -> [String: LedgerEditRow] {
        var saved: [String: LedgerEditRow] = [:]
        do {
            for (id, grant) in verifiedPurchases {
                let key = prefix + id
                let previous = edits[key]
                if previous == nil && !grant.revoked && grant.expiresAt.map({ $0 <= .now }) == true { continue }
                if let old = purchaseGrant(in: previous), !grant.supersedes(old) { continue }
                let value = String(decoding: try JSONEncoder().encode(grant), as: UTF8.self)
                saved[key] = insertEdit(key, value: value, in: book, store: store, context: context,
                                        after: previous?.time)
            }
            if !saved.isEmpty { try context.save() }
            return saved
        } catch {
            context.rollback()
            throw error
        }
    }

    private func schedulePurchaseRefresh(at date: Date?) {
        guard purchaseBoundary != date else { return }
        purchaseBoundary = date
        purchaseTimer?.cancel()
        purchaseTimer = nil
        guard let date else { return }
        purchaseTimer = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(min(86_400, max(0, date.timeIntervalSinceNow))))
                self?.purchaseBoundary = nil
                self?.refresh()
            } catch { return }
        }
    }

    func title(for book: Book) -> String {
        bookTitles[book] ?? (book.isGuest ? "共有の家計簿" : "ふたりの家計簿")
    }

    private func member(for book: Book, share: CKShare?) -> Member? {
        if ScreenshotDemo.isEnabled { return ScreenshotDemo.member }
        return Member.forParticipant(
            isOwner: !book.isGuest,
            isPrivatePartner: share?.publicPermission == CKShare.ParticipantPermission.none
                && share?.currentUserParticipant?.role == .privateUser
                && share?.currentUserParticipant?.acceptanceStatus == .accepted
        )
    }

    /// Records this month's entry for each active template. The entry ID is derived from
    /// book, template and month, so every device writes the same ID and reads dedupe it.
    private func generateRecurring(
        in books: [(Book, LedgerBookRow)], edits: [Book: [String: LedgerEditRow]],
        shares: [NSManagedObjectID: CKShare], container: NSPersistentCloudKitContainer,
        context: NSManagedObjectContext
    ) throws {
        let month = Month(containing: Month.localDay(.now))
        do {
            for (book, row) in books {
                guard let store = row.objectID.persistentStore, readyForRecurring(in: store),
                      let values = edits[book] else { continue }
                if book.isGuest {
                    guard member(for: book, share: shares[row.objectID]) != nil,
                          container.canUpdateRecord(forManagedObjectWith: row.objectID) else { continue }
                }
                let candidates = try RecurringEntry.missing(
                    bookID: book.id, templates: templates(from: values), month: month,
                    existingIDs: [], isSettled: values[monthKey(month)]?.value == "1"
                )
                guard !candidates.isEmpty else { continue }
                let ids = candidates.map(\.id)
                let existing = Set(try context.fetch(expenseRequest(in: row, recurringIDs: ids)).compactMap(\.recurringID))
                for expense in candidates where !existing.contains(expense.id) {
                    guard values[deletedExpenseKey(expense.id)] == nil else { continue }
                    try insert(expense, in: row, store: store, context: context, recurring: true)
                }
                if context.hasChanges { try context.save() }
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    private func templates(from edits: [String: LedgerEditRow]) throws -> [Expense] {
        let decoder = JSONDecoder()
        return try edits.compactMap { key, row -> Expense? in
            guard key.hasPrefix("recurring/"), let value = row.value, !value.isEmpty else { return nil }
            return try decoder.decode(ExpenseFields.self, from: Data(value.utf8)).expense()
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func budgets(from edits: [String: LedgerEditRow]) -> [Month: [Category: Int]] {
        var budgets: [Month: [Category: Int]] = [:]
        for (key, row) in edits where key.hasPrefix("budget/") {
            let parts = key.split(separator: "/")
            guard parts.count == 3, let seconds = Int(parts[1]),
                  let category = Category(rawValue: String(parts[2])),
                  let value = row.value, let limit = Int(value), (1...Ledger.maximumYen).contains(limit)
            else { continue }
            let month = Month(containing: Date(timeIntervalSince1970: TimeInterval(seconds)))
            budgets[month, default: [:]][category] = limit
        }
        return budgets
    }

    var canCreateBook: Bool {
        personalPlan.allowsProFeatures && privateLedgerReady && privateStore != nil && !shareBusy && !storageError
    }

    func createBook(title: String) throws {
        guard personalPlan.allowsProFeatures else { throw BookError.proRequired }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 30, canCreateBook, let context, let privateStore
        else { throw BookError.unavailable }
        let row = LedgerBookRow(context: context)
        context.assign(row, to: privateStore)
        let book = Book(id: UUID(), isGuest: false)
        row.id = book.id
        row.title = title
        do {
            try savePurchases(prefix: "pro/first/", in: row, store: privateStore, context: context, edits: [:])
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
        remember(book)
        refresh()
    }

    func setBudget(_ limit: Int?, category: Category, month: Month, in book: Book) throws {
        if let limit, !(1...Ledger.maximumYen).contains(limit) { throw LedgerError.invalidAmount }
        try writeProEdit(budgetKey(category, month: month), value: limit.map { String($0) } ?? "", in: book)
    }

    private func budgetKey(_ category: Category, month: Month) -> String {
        "budget/\(Int(month.start.timeIntervalSince1970))/\(category.rawValue)"
    }

    func copyPreviousBudget(to month: Month, in book: Book) throws {
        guard plan.allowsProFeatures else { throw BookError.proRequired }
        try write(to: book) { row, store, context in
            let edits = try latestEdits(in: row, context: context)
            let limitsByMonth = budgets(from: edits)
            let categories = Set(Category.allCases + Array(customCategories(from: edits).keys))
            let previous = (limitsByMonth[month.advanced(by: -1)] ?? [:]).filter { categories.contains($0.key) }
            guard !previous.isEmpty,
                  (limitsByMonth[month] ?? [:]).keys.allSatisfy({ !categories.contains($0) })
            else { throw BookError.unavailable }
            for (category, limit) in previous {
                let key = budgetKey(category, month: month)
                insertEdit(key, value: String(limit), in: row, store: store,
                           context: context, after: edits[key]?.time)
            }
        }
    }

    func addTemplate(_ template: Expense, to book: Book) throws {
        guard plan.allowsProFeatures else { throw BookError.proRequired }
        let data = try JSONEncoder().encode(ExpenseFields(template))
        let recurringField = "recurring/\(template.id.uuidString)"
        try write(to: book) { row, store, context in
            guard try latestEdits(in: row, context: context)[recurringField] == nil else { return }
            insertEdit(recurringField, value: String(decoding: data, as: UTF8.self), in: row, store: store, context: context)
        }
    }

    func stopTemplate(_ template: Expense, in book: Book) throws {
        try writeProEdit("recurring/\(template.id.uuidString)", value: "", in: book)
    }

    private func customCategories(from edits: [String: LedgerEditRow]) -> [Category: String] {
        var categories: [Category: String] = [:]
        for (key, row) in edits where key.hasPrefix("category/") {
            guard let category = Category(rawValue: String(key.dropFirst("category/".count))), category.isCustom,
                  let name = row.value, !name.isEmpty else { continue }
            categories[category] = name
        }
        return categories
    }

    func saveCategory(_ category: Category, name: String, in book: Book) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard category.isCustom, (1...30).contains(name.count) else { throw BookError.unavailable }
        try writeProEdit("category/\(category.rawValue)", value: name, in: book)
    }

    private func shoppingItems(from edits: [String: LedgerEditRow]) -> [ShoppingItem] {
        let prefix = "shopping/name/"
        return edits.compactMap { key, row -> ShoppingItem? in
            guard key.hasPrefix(prefix), let id = UUID(uuidString: String(key.dropFirst(prefix.count))),
                  let name = row.value, !name.isEmpty else { return nil }
            return ShoppingItem(id: id, name: name, checked: edits["shopping/checked/\(id.uuidString)"]?.value == "1")
        }.sorted { ($0.checked ? 1 : 0, $0.name, $0.id.uuidString) < ($1.checked ? 1 : 0, $1.name, $1.id.uuidString) }
    }

    func addShoppingItem(_ name: String, in book: Book) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(name.count) else { throw BookError.unavailable }
        try writeProEdit("shopping/name/\(UUID().uuidString)", value: name, in: book)
    }

    func setShoppingItem(_ item: ShoppingItem, checked: Bool, in book: Book) throws {
        try writeProEdit("shopping/checked/\(item.id.uuidString)", value: checked ? "1" : "0", in: book)
    }

    func removeShoppingItem(_ item: ShoppingItem, in book: Book) throws {
        try writeProEdit("shopping/name/\(item.id.uuidString)", value: "", in: book)
    }

    private func writeProEdit(_ key: String, value: String, in book: Book) throws {
        guard plan.allowsProFeatures else { throw BookError.proRequired }
        try write(to: book) { row, store, context in
            let previous = try latestEdits(in: row, context: context)[key]
            if previous?.value != value {
                insertEdit(key, value: value, in: row, store: store, context: context, after: previous?.time)
            }
        }
    }

    func requestQuickRecord() {
        pendingQuickRecord = true
    }

    func consumeQuickRecord() {
        pendingQuickRecord = false
    }

    private func purgeDeletedExpenseRows(
        in bookRow: LedgerBookRow, book: Book, edits: [String: LedgerEditRow],
        container: NSPersistentCloudKitContainer, context: NSManagedObjectContext
    ) throws {
        guard edits.keys.contains(where: { $0.hasPrefix("deletedExpense/") }) else { return }
        let decoder = JSONDecoder()
        for row in try context.fetch(expenseRequest(in: bookRow)) {
            let id = (try? expenseFields(for: row, decoder: decoder).id) ?? row.recurringID
            guard let id, edits[deletedExpenseKey(id)] != nil else { continue }
            guard !book.isGuest || container.canDeleteRecord(forManagedObjectWith: row.objectID) else { continue }
            context.delete(row)
        }
        if context.hasChanges {
            do { try context.save() }
            catch { context.rollback(); throw error }
        }
    }

    var canStartRecording: Bool {
        snapshot?.member != nil && !storeLoadFailed && !storageError && !shareBusy
    }

    func startRecording() throws -> LedgerSnapshot {
        guard canStartRecording, let snapshot else { throw BookError.unavailable }
        return snapshot
    }

    private func mergeSoloEntries(from source: LedgerBookRow, into destination: LedgerBookRow,
                                  edits: [String: LedgerEditRow], context: NSManagedObjectContext) throws -> Bool {
        let decoder = JSONDecoder()
        let existing = try context.fetch(expenseRequest(in: destination))
        let ids = try Set(existing.map { try expenseFields(for: $0, decoder: decoder).id })
        guard let store = destination.objectID.persistentStore else { throw BookError.unavailable }

        // Keep the solo ledger intact. The guest's first slot is the shared book's second slot.
        let destinationCategories = customCategories(from: edits)
        let sourceEdits = try latestEdits(in: source, context: context)
        let sourceCategories = customCategories(from: sourceEdits)
        let knownCategories = Set(sourceCategories.compactMap { category, name in
            destinationCategories[category] == name ? category : nil
        })
        var addedToSettledMonth = false
        let sourceEntries = try Dictionary(grouping: context.fetch(expenseRequest(in: source))) {
            try expenseFields(for: $0, decoder: decoder).id
        }
        for (id, copies) in sourceEntries where !ids.contains(id) {
            guard edits[deletedExpenseKey(id)] == nil, sourceEdits[deletedExpenseKey(id)] == nil,
                  let row = copies.first else { continue }
            let fields = try currentExpenseFields(expenseFields(for: row, decoder: decoder),
                                                  edits: sourceEdits, decoder: decoder)
            let expense = try fields.expense(registeredCategories: knownCategories)
            guard container?.canUpdateRecord(forManagedObjectWith: destination.objectID) == true
            else { throw BookError.unavailable }
            let split: SplitRule
            switch expense.split {
            case .equal: split = .equal
            case let .ratio(first, second): split = .ratio(first: second, second: first)
            case let .fixed(firstYen): split = .fixed(firstYen: abs(expense.amount) - firstYen)
            }
            let copy = try Expense(id: expense.id, amount: expense.amount, date: expense.date,
                                   category: expense.category, payer: expense.payer.other,
                                   split: split, label: expense.label)
            try insert(copy, in: destination, store: store, context: context)
            for photo in receiptPhotos(from: copies) {
                try insert(copy, in: destination, store: store, context: context, receiptJPEG: photo)
            }
            let month = Month(containing: expense.date)
            if edits[monthKey(month)]?.value == "1" { addedToSettledMonth = true }
        }
        if context.hasChanges { try context.save() }
        return addedToSettledMonth
    }

    private func preferredOwned(_ rows: [LedgerBookRow], shares: [NSManagedObjectID: CKShare],
                                context: NSManagedObjectContext) throws -> LedgerBookRow? {
        let ordered = rows.filter { $0.id != nil }.sorted {
            ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
        }
        let current = ordered.first { $0.id?.uuidString == selectedID }
        let shared = ordered.first { shares[$0.objectID] != nil }
        if let current {
            if shares[current.objectID] != nil { return current }
            if try !isEmpty(current, context: context) { return current }
        }
        if let shared { return shared }
        let populated = try ordered.first { try !isEmpty($0, context: context) }
        return populated ?? (privateLedgerReady ? (current ?? ordered.first) : nil)
    }

    private func isEmpty(_ book: LedgerBookRow, context: NSManagedObjectContext) throws -> Bool {
        let request = expenseRequest(in: book)
        request.fetchLimit = 1
        guard try context.fetch(request).isEmpty else { return false }
        return try latestEdits(in: book, context: context).allSatisfy { key, edit in
            if key.hasPrefix("pro/") { return true }
            switch key {
            case "first": return edit.value == Names.firstDefault
            case "second": return edit.value == Names.secondDefault
            default: return edit.value == "0"
            }
        }
    }

    private func rows(in context: NSManagedObjectContext, store: NSPersistentStore) throws -> [LedgerBookRow] {
        let request = NSFetchRequest<LedgerBookRow>(entityName: "LedgerBookRow")
        request.affectedStores = [store]
        return try context.fetch(request)
    }

    private func expenses(in book: LedgerBookRow, context: NSManagedObjectContext,
                          edits: [String: LedgerEditRow] = [:],
                          registeredCategories: Set<Category>? = nil) throws -> [Expense] {
        var ids = Set<UUID>()
        let decoder = JSONDecoder()
        return try context.fetch(expenseRequest(in: book)).compactMap { row in
            let fields = try expenseFields(for: row, decoder: decoder)
            guard edits[deletedExpenseKey(fields.id)] == nil, ids.insert(fields.id).inserted else { return nil }
            return try currentExpenseFields(fields, edits: edits, decoder: decoder)
                .expense(registeredCategories: registeredCategories)
        }.sorted { $0.date > $1.date }
    }

    private func expenseRequest(in book: LedgerBookRow, recurringIDs: [UUID]? = nil) -> NSFetchRequest<LedgerExpenseRow> {
        let request = NSFetchRequest<LedgerExpenseRow>(entityName: "LedgerExpenseRow")
        request.affectedStores = book.objectID.persistentStore.map { [$0] }
        if let recurringIDs {
            request.predicate = NSPredicate(format: "book == %@ AND recurringID IN %@",
                                            argumentArray: [book, recurringIDs])
        } else {
            request.predicate = NSPredicate(format: "book == %@", book)
        }
        return request
    }

    private func expenseFields(for row: LedgerExpenseRow, decoder: JSONDecoder) throws -> ExpenseFields {
        guard let data = row.payload else { throw ReadError.invalidEntry }
        return try decoder.decode(ExpenseFields.self, from: data)
    }

    private func expenseEditKey(_ id: UUID) -> String { "expense/\(id.uuidString)" }

    private func deletedExpenseKey(_ id: UUID) -> String { "deletedExpense/\(id.uuidString)" }

    private func currentExpenseFields(_ original: ExpenseFields, edits: [String: LedgerEditRow],
                                      decoder: JSONDecoder) throws -> ExpenseFields {
        guard let value = edits[expenseEditKey(original.id)]?.value else { return original }
        let fields = try decoder.decode(ExpenseFields.self, from: Data(value.utf8))
        guard fields.id == original.id else { throw ReadError.invalidEntry }
        return fields
    }

    private func receiptRows(for expenseID: UUID, in book: LedgerBookRow,
                             context: NSManagedObjectContext) throws -> [LedgerExpenseRow] {
        let decoder = JSONDecoder()
        let rows = try context.fetch(expenseRequest(in: book)).filter {
            try expenseFields(for: $0, decoder: decoder).id == expenseID
        }
        guard !rows.isEmpty else { throw BookError.unavailable }
        return rows
    }

    private func receiptPhotos(from rows: [LedgerExpenseRow]) -> Set<Data> {
        Set(rows.compactMap(\.receiptJPEG))
    }

    private func latestEdits(in book: LedgerBookRow, context: NSManagedObjectContext) throws -> [String: LedgerEditRow] {
        let request = NSFetchRequest<LedgerEditRow>(entityName: "LedgerEditRow")
        request.affectedStores = book.objectID.persistentStore.map { [$0] }
        request.predicate = NSPredicate(format: "book == %@", book)
        var latest: [String: LedgerEditRow] = [:]
        for edit in try context.fetch(request) {
            guard let key = edit.key, let order = edit.order else { continue }
            if key.hasPrefix("pro/") {
                guard let grant = purchaseGrant(in: edit) else { continue }
                if let previous = purchaseGrant(in: latest[key]), !grant.supersedes(previous) { continue }
                latest[key] = edit
                continue
            }
            if let previous = latest[key]?.order, previous >= order { continue }
            latest[key] = edit
        }
        return latest
    }

    private func insert(_ expense: Expense, in book: LedgerBookRow, store: NSPersistentStore,
                        context: NSManagedObjectContext, recurring: Bool = false,
                        receiptJPEG: Data? = nil) throws {
        let payload = try JSONEncoder().encode(ExpenseFields(expense))
        let row = LedgerExpenseRow(context: context)
        context.assign(row, to: store)
        row.book = book
        row.payload = payload
        row.recurringID = recurring ? expense.id : nil
        row.receiptJPEG = receiptJPEG
    }

    @discardableResult
    private func insertEdit(_ key: String, value: String, in book: LedgerBookRow, store: NSPersistentStore,
                            context: NSManagedObjectContext, after previous: Date? = nil) -> LedgerEditRow {
        let row = LedgerEditRow(context: context)
        context.assign(row, to: store)
        row.book = book
        row.key = key
        row.value = value
        // An edit made after observing a remote edit must win even when the device clock lags.
        row.time = max(.now, previous?.addingTimeInterval(0.001) ?? .distantPast)
        row.id = UUID()
        return row
    }

    private func monthKey(_ month: Month) -> String {
        "month/\(Int(month.start.timeIntervalSince1970))"
    }

    private func activeRow(in book: Book, writable: Bool = false) throws
        -> (LedgerBookRow, NSPersistentStore, NSManagedObjectContext) {
        guard snapshot?.book == book, let context, let container,
              let store = book.isGuest ? sharedStore : privateStore,
              let row = try rows(in: context, store: store).first(where: { $0.id == book.id })
        else { throw BookError.unavailable }
        if writable && (shareBusy || storageError || snapshot?.member == nil || !books.contains(book)
                        || (book.isGuest && !container.canUpdateRecord(forManagedObjectWith: row.objectID))) {
            throw BookError.unavailable
        }
        return (row, store, context)
    }

    private func write(to book: Book, _ change: (LedgerBookRow, NSPersistentStore, NSManagedObjectContext) throws -> Void) throws {
        let (row, store, context) = try activeRow(in: book, writable: true)
        do {
            try change(row, store, context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        refresh()
    }

    func add(_ expense: Expense, to book: Book) throws {
        if expense.category.isCustom && !plan.allowsProFeatures { throw BookError.proRequired }
        try write(to: book) { row, store, context in
            let key = monthKey(Month(containing: expense.date))
            guard try latestEdits(in: row, context: context)[key]?.value != "1" else { throw BookError.settled }
            try insert(expense, in: row, store: store, context: context)
        }
    }

    func update(_ expense: Expense, replacing original: Expense, in book: Book) throws {
        guard expense.id == original.id else { throw BookError.expenseChanged }
        if expense.category.isCustom && !plan.allowsProFeatures { throw BookError.proRequired }
        try write(to: book) { row, store, context in
            let edits = try latestEdits(in: row, context: context)
            let copies = try receiptRows(for: expense.id, in: row, context: context)
            let fields = try editableExpenseFields(copies, id: expense.id, edits: edits)
            try requireUnchanged(fields, original: original, edits: edits)
            guard edits[monthKey(Month(containing: expense.date))]?.value != "1" else { throw BookError.settled }
            // A separate edit keeps the newest fields authoritative even if an older photo row arrives later.
            let anchor = copies.first(where: { $0.receiptJPEG == nil }) ?? copies[0]
            guard !book.isGuest || container?.canUpdateRecord(forManagedObjectWith: anchor.objectID) == true
            else { throw BookError.unavailable }
            // Preserve an existing custom category if it is hidden after Pro expires.
            let updated = try Expense(id: expense.id, amount: expense.amount, date: expense.date,
                                      category: expense.category == original.category ? fields.expense().category : expense.category,
                                      payer: expense.payer, split: expense.split, label: expense.label)
            let key = expenseEditKey(expense.id)
            let payload = try JSONEncoder().encode(ExpenseFields(updated))
            insertEdit(key, value: String(decoding: payload, as: UTF8.self), in: row, store: store,
                       context: context, after: edits[key]?.time)
        }
    }

    func delete(_ expenseID: UUID, from book: Book, matching original: Expense) throws {
        try write(to: book) { row, store, context in
            let edits = try latestEdits(in: row, context: context)
            let copies = try receiptRows(for: expenseID, in: row, context: context)
            let fields = try editableExpenseFields(copies, id: expenseID, edits: edits)
            try requireUnchanged(fields, original: original, edits: edits)
            guard !book.isGuest || copies.allSatisfy({
                container?.canDeleteRecord(forManagedObjectWith: $0.objectID) == true
            }) else { throw BookError.unavailable }
            // Keep the ID suppressed if a receipt arrives late or a recurring template runs again.
            insertEdit(deletedExpenseKey(expenseID), value: "1", in: row, store: store, context: context)
            for copy in copies { context.delete(copy) }
        }
    }

    private func editableExpenseFields(_ copies: [LedgerExpenseRow], id: UUID,
                                       edits: [String: LedgerEditRow]) throws -> ExpenseFields {
        guard edits[deletedExpenseKey(id)] == nil, let row = copies.first else { throw BookError.expenseChanged }
        let decoder = JSONDecoder()
        let fields = try currentExpenseFields(expenseFields(for: row, decoder: decoder), edits: edits, decoder: decoder)
        guard edits[monthKey(Month(containing: fields.date))]?.value != "1" else { throw BookError.settled }
        return fields
    }

    private func requireUnchanged(_ fields: ExpenseFields, original: Expense,
                                  edits: [String: LedgerEditRow]) throws {
        let categories = Set(plan.allowsProFeatures ? Array(customCategories(from: edits).keys) : [])
        guard try fields.expense(registeredCategories: categories) == original else {
            throw BookError.expenseChanged
        }
    }

    func receipts(for expenseID: UUID, in book: Book) throws -> Set<Data> {
        let (row, _, context) = try activeRow(in: book)
        return try receiptPhotos(from: receiptRows(for: expenseID, in: row, context: context))
    }

    func setReceipt(_ photo: ReceiptPhoto?, replacing previous: Set<Data>, for expenseID: UUID, in book: Book) throws {
        try write(to: book) { row, store, context in
            guard try latestEdits(in: row, context: context)[deletedExpenseKey(expenseID)] == nil
            else { throw BookError.expenseChanged }
            let copies = try receiptRows(for: expenseID, in: row, context: context)
            guard receiptPhotos(from: copies) == previous else { throw ReceiptPhotoError.changed }
            // Keep a permanent photo-free expense row. Recurring rows also carry the lookup ID.
            let anchor = copies.first(where: { $0.receiptJPEG == nil }) ?? copies[0]
            for expense in copies where expense.receiptJPEG != nil {
                if expense === anchor || expense.recurringID != nil {
                    if book.isGuest && container?.canUpdateRecord(forManagedObjectWith: expense.objectID) != true {
                        throw BookError.unavailable
                    }
                    expense.receiptJPEG = nil
                } else {
                    if book.isGuest && container?.canDeleteRecord(forManagedObjectWith: expense.objectID) != true {
                        throw BookError.unavailable
                    }
                    context.delete(expense)
                }
            }
            if let photo {
                // Separate records let simultaneous photo uploads survive a CloudKit import.
                let attachment = LedgerExpenseRow(context: context)
                context.assign(attachment, to: store)
                attachment.book = row
                attachment.payload = anchor.payload
                attachment.receiptJPEG = photo.jpeg
            }
        }
    }

    func setSettled(_ settled: Bool, month: Month, in book: Book) throws {
        try write(to: book) { row, store, context in
            let key = monthKey(month)
            let previous = try latestEdits(in: row, context: context)[key]
            insertEdit(key, value: settled ? "1" : "0", in: row, store: store, context: context, after: previous?.time)
        }
    }

    func rename(_ names: Names, replacing previous: Names, in book: Book) throws {
        try write(to: book) { row, store, context in
            let edits = try latestEdits(in: row, context: context)
            let fields = [("first", names.first, previous.first), ("second", names.second, previous.second)]
            for (key, value, original) in fields where value != original && edits[key]?.value != value {
                insertEdit(key, value: value, in: row, store: store, context: context, after: edits[key]?.time)
            }
        }
    }

    private func activePartners(_ share: CKShare) -> [CKShare.Participant] {
        share.participants.filter {
            $0.role != .owner && ($0.acceptanceStatus == .accepted || $0.acceptanceStatus == .pending)
        }
    }

    private func partnerHistoryField(_ id: UUID) -> String {
        "ledger.hadPartner/\(id.uuidString)"
    }

    private func hadPartner(_ id: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: partnerHistoryField(id))
    }

    private func observePartner(in share: CKShare?, book: Book) {
        let partners = share.map(activePartners) ?? []
        let accepted = partners.contains { $0.acceptanceStatus == .accepted }
        if accepted {
            if !hadPartner(book.id) {
                UserDefaults.standard.set(true, forKey: partnerHistoryField(book.id))
            }
            partnerNotice = nil
        } else if partners.contains(where: { $0.acceptanceStatus == .pending }) {
            partnerNotice = "招待の承諾待ちです。相手にリンクを開いてもらってください"
        } else if hadPartner(book.id) {
            partnerNotice = "パートナーが共有から外れました。必要なら再招待してください"
        } else {
            partnerNotice = nil
        }
    }

    func invite(email: String, in book: Book) async throws -> URL {
        guard canShare, !book.isGuest, !shareBusy, let cloud, let container else { throw BookError.unavailable }
        shareBusy = true
        defer { shareBusy = false; refresh() }
        let (row, store, _) = try activeRow(in: book)
        let participant = try await cloud.shareParticipant(forEmailAddress: email)
        guard let target = participant.userIdentity.userRecordID else { throw BookError.unresolvedPartner }
        guard target != (try await cloud.userRecordID()) else { throw BookError.otherPartner }
        let share: CKShare
        if let cached = try container.fetchShares(matching: [row.objectID])[row.objectID] {
            guard let current = try await cloud.privateCloudDatabase.record(for: cached.recordID) as? CKShare
            else { throw BookError.unavailable }
            share = current
        } else {
            share = try await withCheckedThrowingContinuation { continuation in
                container.share([row], to: nil) { _, share, _, error in
                    if let share, error == nil { continuation.resume(returning: share) }
                    else { continuation.resume(throwing: error ?? BookError.unavailable) }
                }
            }
        }
        let partners = activePartners(share)
        guard !partners.contains(where: {
            $0.acceptanceStatus == .accepted && $0.userIdentity.userRecordID != target
        })
        else { throw BookError.otherPartner }
        let same = partners.first { $0.userIdentity.userRecordID == target }
        let replacements = partners.filter {
            $0.acceptanceStatus == .pending && $0.userIdentity.userRecordID != target
        }
        if replacements.isEmpty, share.publicPermission == .none, same?.permission == .readWrite, let url = share.url {
            observePartner(in: share, book: book)
            return url
        }
        for pending in replacements { share.removeParticipant(pending) }
        if share.publicPermission != .none { share.publicPermission = .none }
        share[CKShare.SystemFieldKey.title] = title(for: book) as NSString
        if let same {
            same.permission = .readWrite
        } else {
            participant.permission = .readWrite
            share.addParticipant(participant)
        }
        let saved: CKShare = try await withCheckedThrowingContinuation { continuation in
            container.persistUpdatedShare(share, in: store) { share, error in
                if let share, error == nil { continuation.resume(returning: share) }
                else { continuation.resume(throwing: error ?? BookError.unavailable) }
            }
        }
        guard let url = saved.url else { throw BookError.missingLink }
        observePartner(in: saved, book: book)
        return url
    }

    func participantShare(in book: Book) throws -> (CKShare, CKContainer) {
        guard canManageGuestShares, book.isGuest, let cloud, let container, let context, let sharedStore,
              books.contains(book) || lockedBooks.contains(book),
              let row = try rows(in: context, store: sharedStore).first(where: { $0.id == book.id }),
              let share = try container.fetchShares(matching: [row.objectID])[row.objectID],
              member(for: book, share: share) != nil
        else { throw BookError.unavailable }
        return (share, cloud)
    }

    var canManageGuestShares: Bool {
        account == .available && !shareBusy && sharedStore != nil
    }

    func sharingFailed() {
        message = "共有の設定を保存できませんでした"
        updateNotice()
    }

    func purgeSharedZone(_ zone: CKRecordZone.ID) async {
        guard let container, let sharedStore else { return }
        pendingLeave = zone
        shareBusy = true
        defer { shareBusy = false; refresh() }
        refresh()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.purgeObjectsAndRecordsInZone(with: zone, in: sharedStore) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            pendingLeave = nil
            context?.reset()
        } catch let error as CKError where error.code == .zoneNotFound {
            // UIKit may already have removed the zone before delivering its delegate callback.
            pendingLeave = nil
            context?.reset()
        } catch {
            NSLog("Ledger share cleanup: %@", String(describing: error))
        }
    }

    func retryInvite() async {
        guard !shareBusy, let failedInvite else { return }
        await checkAccount()
        guard self.failedInvite?.share.recordID == failedInvite.share.recordID else { return }
        await accept(failedInvite)
    }

    func accept(_ metadata: CKShare.Metadata) async {
        if awaitingZone == metadata.share.recordID.zoneID { return }
        guard let cloud, metadata.containerIdentifier == cloud.containerIdentifier else {
            failedInvite = nil
            inviteIssue = .expired
            return
        }
        if let sharingAccountIssue {
            failedInvite = metadata
            inviteIssue = sharingAccountIssue
            return
        }
        guard let container, let sharedStore, !shareBusy else {
            failedInvite = metadata
            inviteIssue = .retry
            return
        }
        failedInvite = nil
        inviteIssue = nil
        shareBusy = true
        defer { shareBusy = false; refresh() }
        do {
            let zone = metadata.share.recordID.zoneID
            if let row = try rows(in: container.viewContext, store: sharedStore).first(where: { row in
                try container.fetchShares(matching: [row.objectID])[row.objectID]?.recordID.zoneID == zone
            }), let id = row.id {
                let titled = try isTitled(row, context: container.viewContext)
                if books.contains(Book(id: id, isGuest: true)) || !titled {
                    remember(Book(id: id, isGuest: true))
                }
                clearInviteFailure(for: metadata)
                return
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            clearInviteFailure(for: metadata)
            awaitingZone = zone
            message = nil
            context?.reset()
        } catch {
            let issue = InviteIssue.classify(error, accepting: true)
            if let failedInvite, failedInvite.share.recordID != metadata.share.recordID { return }
            failedInvite = issue == .expired ? nil : metadata
            inviteIssue = issue
        }
    }

    private func clearInviteFailure(for metadata: CKShare.Metadata) {
        if let failedInvite, failedInvite.share.recordID != metadata.share.recordID { return }
        failedInvite = nil
        inviteIssue = nil
    }
}
