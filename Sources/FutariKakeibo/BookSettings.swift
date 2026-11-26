import CloudKit
import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct BookSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ledger: CloudLedger
    let book: Book?
    @State private var sharing: ParticipantSheet?
    @State private var failure = false
    @State private var showingPaywall = false

    var body: some View {
        Form {
            if let book, let snapshot = ledger.snapshot, snapshot.book == book {
                if ledger.canShare {
                    if book.isGuest {
                        Button("共有の管理") { manageShare(book) }
                            .disabled(!ledger.canManageGuestShares)
                    } else {
                        NavigationLink("パートナーを招待") {
                            InvitePartner(ledger: ledger, book: book)
                        }
                    }
                }
                NavigationLink("ふたりの名前") {
                    EditNames(snapshot: snapshot, repository: ledger)
                }
                .disabled(snapshot.member == nil)
                RecordingReminder()
                if ledger.plan.allowsProFeatures {
                    NavigationLink {
                        RecurringSettings(ledger: ledger, book: book)
                    } label: {
                        Text("定期入力").frame(minHeight: 44)
                    }
                } else {
                    ProLock("定期入力", ledger: ledger)
                }
                NavigationLink {
                    PaidBookTools(ledger: ledger, book: book)
                } label: {
                    Label("家計簿の便利機能", systemImage: ledger.plan.allowsProFeatures ? "chart.bar" : "lock")
                        .frame(minHeight: 44)
                }
            }
            if let partnerNotice = ledger.partnerNotice {
                Text(partnerNotice).font(.footnote).foregroundStyle(.secondary)
            }
            if let issue = ledger.sharingAccountIssue {
                InviteRecovery(issue: issue)
            }
            if let notice = ledger.notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
                if ledger.canRetry {
                    Button("再試行") { Task { await ledger.retry() } }
                }
            }
            let listed = ledger.books + ledger.lockedBooks
            let titles = listed.map { ledger.title(for: $0) }
            let duplicateTitles = Set(titles).count != titles.count
            if ledger.books.count > 1 || (book == nil && !ledger.books.isEmpty) {
                Section("家計簿を切り替え") {
                    ForEach(Array(ledger.books.enumerated()), id: \.element) { index, target in
                        Button {
                            ledger.select(target)
                            dismiss()
                        } label: {
                            Text(duplicateTitles ? "\(index + 1). \(titles[index])" : titles[index])
                                .frame(minHeight: 44)
                        }
                        .disabled(ledger.snapshot?.book == target || ledger.shareBusy)
                    }
                }
            }
            ForEach(Array(ledger.lockedBooks.enumerated()), id: \.element) { offset, target in
                let index = ledger.books.count + offset
                let title = duplicateTitles ? "\(index + 1). \(titles[index])" : titles[index]
                Section(title) {
                    ProLock(title, ledger: ledger)
                    if target.isGuest {
                        Button("共有の管理") { manageShare(target) }
                            .frame(minHeight: 44)
                            .disabled(!ledger.canManageGuestShares)
                    }
                }
            }
            Section("家計簿") {
                if ledger.personalPlan.allowsProFeatures {
                    NavigationLink {
                        NewBookForm(ledger: ledger)
                    } label: {
                        Text("家計簿を追加").frame(minHeight: 44)
                    }
                    .disabled(!ledger.canCreateBook)
                } else {
                    ProLock("家計簿を追加", ledger: ledger)
                }
                Button("Proプラン・購入の復元") { showingPaywall = true }
                    .frame(minHeight: 44)
            }
            LegalLinks()
        }
        .navigationTitle("ふたりと共有")
        .sheet(item: $sharing) { $0 }
        .sheet(isPresented: $showingPaywall) { ProPaywall(ledger: ledger) }
        .alert("共有を開けませんでした", isPresented: $failure) {
            Button("閉じる", role: .cancel) {}
        }
    }

    private func manageShare(_ target: Book) {
        do {
            let (share, container) = try ledger.participantShare(in: target)
            sharing = ParticipantSheet(share: share, container: container, ledger: ledger)
        } catch {
            failure = true
        }
    }
}

@MainActor
private struct RecordingReminder: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderEnabled: Bool?
    @State private var reminderBusy = false
    @State private var reminderFailure = false
    private let reminderID = "ledger.recording"
    private let center = UNUserNotificationCenter.current()

    var body: some View {
        Section("記録のリマインダー") {
            if let reminderEnabled {
                Button {
                    reminderBusy = true
                    Task { await save(enabled: !reminderEnabled) }
                } label: {
                    Text(reminderEnabled ? "毎日20時の通知をオフ" : "毎日20時に通知する")
                        .frame(minHeight: 44)
                }
                .disabled(reminderBusy)
            } else {
                ProgressView("通知設定を確認中").frame(minHeight: 44)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !reminderBusy else { return }
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled, !reminderBusy else { return }
            reminderEnabled = pending.contains { $0.identifier == reminderID }
        }
        .alert("通知を設定できませんでした", isPresented: $reminderFailure) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("iPhoneの設定で通知を許可してから、もう一度お試しください。")
        }
    }

    private func save(enabled: Bool) async {
        defer { reminderBusy = false }
        do {
            if enabled {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    throw BookError.unavailable
                }
                let content = UNMutableNotificationContent()
                content.title = "支出を記録する時間です"
                content.body = "今日の支出をふたりの家計簿に記録しましょう。"
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: 20, minute: 0), repeats: true
                )
                try await center.add(UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger))
            } else {
                center.removePendingNotificationRequests(withIdentifiers: [reminderID])
            }
            reminderEnabled = enabled
        } catch {
            reminderFailure = true
        }
    }
}

@MainActor
private struct InvitePartner: View {
    @ObservedObject var ledger: CloudLedger
    let book: Book
    @State private var email = ""
    @State private var link: URL?
    @State private var failure: InviteIssue?

    var body: some View {
        Form {
            if let notice = ledger.partnerNotice ?? ledger.notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            TextField("相手のApple Accountのメールアドレス", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(ledger.shareBusy)
                .onChange(of: email) { _, _ in link = nil; failure = nil }
            if let link, ledger.canShare {
                ShareLink(item: link) {
                    Label("招待リンクを送る", systemImage: "square.and.arrow.up")
                }
                Text("リンクを相手に送ってください。相手が承諾すると共有が始まります。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button(ledger.shareBusy ? "リンクを作成中…" : "招待リンクを作る") {
                    Task { await createLink() }
                }
                .disabled(!ledger.canShare || ledger.shareBusy || !target.contains("@"))
            }
            if let issue = ledger.sharingAccountIssue ?? failure {
                InviteRecovery(issue: issue)
            }
        }
        .navigationTitle("パートナーを招待")
    }

    private var target: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func createLink() async {
        failure = nil
        do {
            link = try await ledger.invite(email: target, in: book)
        } catch {
            failure = InviteIssue.classify(error, accepting: false)
        }
    }
}

struct InviteRecovery: View {
    let issue: InviteIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.message)
            Text(issue.nextAction).foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}

@MainActor
private struct ParticipantSheet: UIViewControllerRepresentable, Identifiable {
    var id: CKRecord.ID { share.recordID }
    let share: CKShare
    let container: CKContainer
    let ledger: CloudLedger

    func makeCoordinator() -> Coordinator { Coordinator(ledger: ledger, zone: share.recordID.zoneID) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let ledger: CloudLedger
        let zone: CKRecordZone.ID

        init(ledger: CloudLedger, zone: CKRecordZone.ID) {
            self.ledger = ledger
            self.zone = zone
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { "ふたりの家計簿" }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in ledger.sharingFailed() }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { await ledger.purgeSharedZone(zone) }
        }
    }
}
