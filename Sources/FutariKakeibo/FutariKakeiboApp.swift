import Foundation
import Charts
import FutariDomain
import SwiftUI
import CloudKit
import UIKit

@main
@MainActor
final class FutariKakeiboApp: UIResponder, UIApplicationDelegate {
    lazy var ledger = CloudLedger()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if !ScreenshotDemo.isEnabled {
            application.registerForRemoteNotifications()
            _ = ledger.purchases
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = LedgerSceneDelegate.self
        return configuration
    }
}

@MainActor
final class LedgerSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var ledger: CloudLedger? { (UIApplication.shared.delegate as? FutariKakeiboApp)?.ledger }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, let ledger else { return }
        let window = UIWindow(windowScene: scene)
        if ScreenshotDemo.isEnabled {
            window.overrideUserInterfaceStyle = ScreenshotDemo.isDark ? .dark : .light
        }
        window.rootViewController = UIHostingController(rootView: Home(ledger: ledger))
        self.window = window
        window.makeKeyAndVisible()
        if !ScreenshotDemo.isEnabled, let metadata = options.cloudKitShareMetadata {
            Task { await ledger.accept(metadata) }
        }
        if !ScreenshotDemo.isEnabled,
           options.urlContexts.contains(where: { $0.url.scheme == "futarikakeibo" }) {
            ledger.requestQuickRecord()
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard !ScreenshotDemo.isEnabled,
              URLContexts.contains(where: { $0.url.scheme == "futarikakeibo" }) else { return }
        ledger?.requestQuickRecord()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !ScreenshotDemo.isEnabled, let ledger else { return }
        Task {
            await ledger.activate()
            await ledger.purchases.activate()
            await SettlementReminder.shared.refresh(access: ledger.access)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard !ScreenshotDemo.isEnabled else { return }
        Task { await ledger?.accept(metadata) }
    }
}

@MainActor
private struct Home: View {
    @ObservedObject var ledger: CloudLedger
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedMonth: Month?
    @State private var enteringExpense: LedgerSnapshot?
    @State private var entryUnavailable = false
    @AppStorage("ledger.theme") private var theme = LedgerTheme.standard

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let currentMonth = Month(containing: ScreenshotDemo.day ?? Month.localDay(context.date))
                let month = selectedMonth ?? currentMonth
                List {
                    if let snapshot = ledger.snapshot {
                        if snapshot.expenses.isEmpty && snapshot.settlementDates[month] == nil {
                            FirstExpensePrompt(canRecord: ledger.canStartRecording, record: startExpense)
                        } else {
                            settlementHeader(month: month, currentMonth: currentMonth, snapshot: snapshot)
                        }
                    }
                    if let issue = ledger.inviteIssue {
                        InviteRecovery(issue: issue)
                        if ledger.canRetryInvite {
                            Button("招待をもう一度開く") { Task { await ledger.retryInvite() } }
                                .frame(minHeight: 44)
                                .disabled(ledger.shareBusy)
                        }
                    }
                    if let notice = ledger.notice {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                        if ledger.canRetry {
                            Button("再試行") { Task { await ledger.retry() } }
                                .disabled(ledger.shareBusy)
                        }
                    }
                    if let partnerNotice = ledger.partnerNotice {
                        Text(partnerNotice).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let snapshot = ledger.snapshot, !snapshot.expenses.isEmpty {
                        let previous = month.advanced(by: -1)
                        if month == currentMonth, snapshot.settlementDates[previous] == nil,
                           snapshot.expenses.contains(where: { previous.dates.contains($0.date) }) {
                            NavigationLink {
                                MonthDetail(month: previous, ledger: ledger, book: snapshot.book)
                            } label: {
                                Text("先月の精算を確認").frame(minHeight: 44)
                            }
                        }
                    }
                    if let snapshot = ledger.snapshot,
                       !snapshot.expenses.isEmpty || snapshot.settlementDates[month] != nil {
                        RecordExpenseButton(canRecord: ledger.canStartRecording, record: startExpense)
                            .accessibilityIdentifier("home-entry")
                    }
                    if let snapshot = ledger.snapshot, !snapshot.expenses.isEmpty, snapshot.book.isGuest,
                       let member = snapshot.member, ledger.canStartRecording,
                       !snapshot.expenses.contains(where: { $0.payer == member }) {
                        Text("自分の支払いを記録すると、ふたりの家計簿に反映されます")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let snapshot = ledger.snapshot, !snapshot.expenses.isEmpty,
                       !snapshot.book.isGuest, ledger.canShare, !ledger.isBookShared, ledger.partnerNotice == nil {
                        NavigationLink {
                            InvitePartner(ledger: ledger, book: snapshot.book)
                        } label: {
                            Text("パートナーを招待").frame(minHeight: 44)
                        }
                    }
                    if let snapshot = ledger.snapshot,
                       let expense = recentExpense(in: month, snapshot: snapshot) {
                        NavigationLink {
                            ExpenseDetail(ledger: ledger, book: snapshot.book, expenseID: expense.id)
                        } label: {
                            let layout = typeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                : AnyLayout(HStackLayout(spacing: 12))
                            layout {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: expense.category.systemImage)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(expense.label ?? snapshot.title(for: expense.category))
                                        Text("\(snapshot.title(for: expense.category)) · \(expense.date.formatted(japaneseDate.month().day())) · \(expense.payerCaption(names: snapshot.names))")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                                Text(expense.amount.yen).font(.headline).monospacedDigit()
                            }
                            .frame(minHeight: 44)
                            .accessibilityElement(children: .combine)
                        }
                        NavigationLink {
                            MonthDetail(month: month, ledger: ledger, book: snapshot.book)
                        } label: {
                            Text(month == currentMonth ? "今月の明細をすべて見る" : "この月の明細をすべて見る")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                                .frame(minHeight: 44)
                        }
                    }
                    if let snapshot = ledger.snapshot, ledger.plan.allowsProFeatures {
                        let budgetTitle = month == currentMonth ? "今月の予算" : "この月の予算"
                        let limits = snapshot.budgets[month]?.filter({ snapshot.categories.contains($0.key) }) ?? [:]
                        if !limits.isEmpty,
                           let totals = try? Ledger.totals(for: snapshot.expenses, in: month),
                           let progress = try? Ledger.budgetTotal(limits: limits, totals: totals) {
                            NavigationLink {
                                BudgetSettings(ledger: ledger, book: snapshot.book, month: month)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    YenRow(
                                        title: budgetTitle,
                                        value: progress.overspend > 0 ? "超過 \(progress.overspend.yen)" : "残り \(progress.remaining.yen)"
                                    )
                                    .foregroundStyle(budgetTone(overspend: progress.overspend > 0, colorScheme: colorScheme))
                                    HomeBudgetSummary(progress: progress, colorScheme: colorScheme)
                                }
                                .frame(minHeight: 44)
                            }
                        } else {
                            NavigationLink {
                                BudgetSettings(ledger: ledger, book: snapshot.book, month: month)
                            } label: {
                                if limits.isEmpty && snapshot.expenses.isEmpty {
                                    Text("費目別予算を設定").frame(minHeight: 44)
                                } else if limits.isEmpty {
                                    YenRow(title: budgetTitle, value: "設定する")
                                        .frame(minHeight: 44)
                                } else {
                                    Text("予算の合計を表示できません").frame(minHeight: 44)
                                }
                            }
                        }
                    }
                    if let snapshot = ledger.snapshot, !snapshot.expenses.isEmpty {
                        if !ledger.plan.allowsProFeatures {
                            ProLock("費目別予算", ledger: ledger)
                        }
                        HomeSpending(month: month, snapshot: snapshot)
                    }
                }
                .onChange(of: currentMonth) { _, _ in ledger.refresh() }
            }
            .navigationTitle(ledger.snapshot.map { ledger.title(for: $0.book) } ?? "ふたりの家計簿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BookSettings(ledger: ledger, book: ledger.snapshot?.book)
                    } label: {
                        Image(systemName: "person.2")
                            .accessibilityLabel("ふたりと共有")
                    }
                }
            }
        }
        .tint(ledger.plan.allowsProFeatures ? theme.tint : nil)
        .id(ledger.snapshot?.book)
        .onChange(of: ledger.snapshot?.book) { _, _ in selectedMonth = nil }
        .onChange(of: ledger.pendingQuickRecord) { _, _ in openQuickRecordIfReady() }
        .onChange(of: ledger.canStartRecording) { _, _ in openQuickRecordIfReady() }
        .onAppear { openQuickRecordIfReady() }
        .sheet(item: $enteringExpense) { snapshot in
            EntryForm(snapshot: snapshot, repository: ledger)
        }
        .alert("記録を開けませんでした。もう一度お試しください", isPresented: $entryUnavailable) {
            Button("閉じる", role: .cancel) {}
        }
    }

    private func openQuickRecordIfReady() {
        guard ledger.pendingQuickRecord, ledger.canStartRecording, enteringExpense == nil else { return }
        ledger.consumeQuickRecord()
        startExpense()
    }

    private func startExpense() {
        do { enteringExpense = try ledger.startRecording() }
        catch { entryUnavailable = true }
    }

    private func recentExpense(in month: Month, snapshot: LedgerSnapshot) -> Expense? {
        let records = snapshot.expenses.filter { month.dates.contains($0.date) }
        if let member = snapshot.member, let partnerExpense = records.first(where: { $0.payer == member.other }) {
            return partnerExpense
        }
        return records.first
    }

    private func settlementHeader(month: Month, currentMonth: Month, snapshot: LedgerSnapshot) -> some View {
        let layout = VStackLayout(alignment: .leading, spacing: 8)
        return layout {
            NavigationLink {
                MonthDetail(month: month, ledger: ledger, book: snapshot.book)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settlementTitle(in: month, snapshot: snapshot))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if let date = snapshot.settlementDates[month] {
                        Text(Month.localDay(date).formatted(japaneseDate.year().month().day()))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityHint("月の明細を開きます")
            }
            .accessibilityIdentifier("home-month")

            let metadataLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 8))
            metadataLayout {
                Label(
                    ledger.isBookShared || snapshot.book.isGuest
                        ? "\(snapshot.names.first)・\(snapshot.names.second) で共有中"
                        : "\(snapshot.names.first)・\(snapshot.names.second)",
                    systemImage: ledger.isBookShared || snapshot.book.isGuest ? "person.2.fill" : "person.2"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Menu {
                    Button("前の月") { selectedMonth = month.advanced(by: -1) }
                    Button("次の月") { selectedMonth = month.advanced(by: 1) }
                    if month != currentMonth {
                        Button("今月に戻る") { selectedMonth = nil }
                    }
                } label: {
                    Label(month.start.formatted(japaneseDate.year().month()), systemImage: "chevron.down")
                        .font(.subheadline)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("表示する月を変更します")
            }
        }
        .padding(.vertical, 8)
    }

    private func settlementTitle(in month: Month, snapshot: LedgerSnapshot) -> String {
        switch try? settlement(in: month, snapshot: snapshot) {
        case .settled?: return "精算済み"
        case .open(nil)?: return "精算なし"
        case .open(let payment?)?:
            guard let member = snapshot.member else {
                return "\(snapshot.names[payment.from])から\(snapshot.names[payment.to])へ \(payment.amount.yen)"
            }
            return payment.from == member
                ? "\(snapshot.names[payment.to])へ \(payment.amount.yen) 支払う"
                : "\(snapshot.names[payment.from])から \(payment.amount.yen) 受け取る"
        case nil: return "精算額を表示できません"
        }
    }
}

private struct HomeBudgetSummary: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let progress: BudgetProgress
    let colorScheme: ColorScheme

    private var tone: Color {
        budgetTone(overspend: progress.overspend > 0, colorScheme: colorScheme)
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress.progress)
                .tint(tone)
                .accessibilityHidden(true)
            layout {
                Text(progress.percentageCaption)
                    .foregroundStyle(tone)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("予算 \(progress.limit.yen)")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .monospacedDigit()
        }
    }
}

private struct HomeSpending: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = true
    let month: Month
    let snapshot: LedgerSnapshot
    private let chartPalette: [Color] = [
        Color(red: 23.0 / 255, green: 73.0 / 255, blue: 56.0 / 255),
        Color(red: 31.0 / 255, green: 98.0 / 255, blue: 142.0 / 255),
        Color(red: 158.0 / 255, green: 84.0 / 255, blue: 18.0 / 255),
        Color(red: 112.0 / 255, green: 42.0 / 255, blue: 158.0 / 255),
        Color(red: 166.0 / 255, green: 27.0 / 255, blue: 41.0 / 255),
        Color(red: 67.0 / 255, green: 109.0 / 255, blue: 32.0 / 255),
        Color(red: 120.0 / 255, green: 72.0 / 255, blue: 96.0 / 255),
        Color(red: 85.0 / 255, green: 92.0 / 255, blue: 102.0 / 255),
    ]

    var body: some View {
        if let total = try? Ledger.spendingTotal(for: snapshot.expenses, in: month),
           let totals = try? Ledger.totals(for: snapshot.expenses, in: month) {
            let categories = totals.keys.sorted {
                let left = totals[$0, default: 0]
                let right = totals[$1, default: 0]
                return left == right ? $0.rawValue < $1.rawValue : left > right
            }
            if categories.isEmpty {
                YenRow(title: "支出合計", value: total.yen)
            } else {
                breakdown(categories: categories, totals: totals, total: total)
            }
        } else {
            Text("合計を表示できません").foregroundStyle(.secondary)
        }
    }

    private func swatchColor(for category: Category, in positive: [Category]) -> Color? {
        guard let index = positive.firstIndex(of: category) else { return nil }
        return chartPalette[index % chartPalette.count]
    }

    private func breakdown(categories: [Category], totals: [Category: Int], total: Int) -> some View {
        let positive = categories.filter { totals[$0, default: 0] > 0 }
        let showChart = !typeSize.isAccessibilitySize && !positive.isEmpty && totals.values.allSatisfy { $0 >= 0 }
        return DisclosureGroup(isExpanded: $expanded) {
            if showChart {
                ZStack {
                    Chart(positive, id: \.self) { category in
                        SectorMark(angle: .value("支出", totals[category, default: 0]), innerRadius: .ratio(0.72))
                            .foregroundStyle(swatchColor(for: category, in: positive) ?? .accentColor)
                            .accessibilityLabel(Text(snapshot.title(for: category)))
                            .accessibilityValue(Text(totals[category, default: 0].yen))
                    }
                    Text("支出合計\n\(total.yen)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 122)
                        .accessibilityHidden(true)
                }
                .frame(height: 184)
            }
            ForEach(categories, id: \.self) { category in
                HStack(spacing: 10) {
                    if showChart, let swatch = swatchColor(for: category, in: positive) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(swatch)
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                    }
                    YenRow(title: snapshot.title(for: category), value: totals[category, default: 0].yen)
                }
            }
        } label: {
            YenRow(title: "支出合計", value: total.yen)
                .frame(minHeight: 44)
                .accessibilityHint("費目別の内訳を表示します")
        }
    }
}

struct FirstExpensePrompt: View {
    let canRecord: Bool
    let record: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("この家計簿にはまだ支出の記録がありません。")
            RecordExpenseButton(canRecord: canRecord, record: record)
                .accessibilityIdentifier("home-entry")
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }
}

private struct RecordExpenseButton: View {
    let canRecord: Bool
    let record: () -> Void

    var body: some View {
        Button(action: record) {
            Label("支出を記録", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .listRowBackground(Color.clear)
        .disabled(!canRecord)
    }
}

private enum MonthlySettlement {
    case settled
    case open(Settlement?)
}

private func settlement(in month: Month, snapshot: LedgerSnapshot) throws -> MonthlySettlement {
    if snapshot.settlementDates[month] != nil { return .settled }
    return .open(try Ledger.settlement(for: snapshot.expenses, in: month.dates))
}

private struct SettlementAmount: View {
    let value: MonthlySettlement
    let names: Names

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch value {
            case .open(let payment):
                if let payment {
                    Text("\(honorific(names[payment.from]))が\(honorific(names[payment.to]))に\(payment.amount.yen)支払えば精算完了です。")
                } else {
                    Text("精算の支払いなし")
                }
            case .settled:
                Text("精算済み")
            }
        }
        .font(.title3.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func honorific(_ name: String) -> String {
        name.hasSuffix("さん") ? name : name + "さん"
    }
}

@MainActor
private struct MonthDetail: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var ledger: CloudLedger
    @State private var month: Month
    let book: Book
    @State private var showingSettlement = false
    @State private var showingEntry = false
    @State private var pendingDeletion: Expense?
    @State private var confirmDeletion = false
    @State private var deletionFailure: String?

    init(month: Month, ledger: CloudLedger, book: Book) {
        _month = State(initialValue: month)
        self.ledger = ledger
        self.book = book
    }

    var body: some View {
        if let snapshot = ledger.snapshot, snapshot.book == book {
            details(snapshot)
        } else {
            Text(ledger.notice ?? "この家計簿を開けません")
        }
    }

    private func details(_ snapshot: LedgerSnapshot) -> some View {
        let records = snapshot.expenses.filter { month.dates.contains($0.date) }
        let isSettled = snapshot.settlementDates[month] != nil
        let result = try? settlement(in: month, snapshot: snapshot)
        let totals = try? Ledger.totals(for: records, in: month)
        let budgets = snapshot.budgets[month] ?? [:]
        let names = snapshot.names
        return List {
            HStack {
                monthButton(-1, icon: "chevron.left", title: "前の月")
                Spacer()
                Text(month.start.formatted(japaneseDate.year().month())).font(.headline)
                Spacer()
                monthButton(1, icon: "chevron.right", title: "次の月")
            }
            Section("精算額") {
                if let result {
                    SettlementAmount(value: result, names: names)
                } else {
                    Text("精算額を表示できません")
                }
                if isSettled || (result != nil && !records.isEmpty) {
                    Button("精算を確認") { showingSettlement = true }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("month-settlement")
                }
            }
            Section("費目別の合計") {
                if let totals {
                    ForEach(snapshot.categories, id: \.self) { category in
                        if let limit = budgets[category] {
                            let remaining = Ledger.budgetRemaining(limit: limit, spent: totals[category, default: 0])
                            VStack(alignment: .trailing, spacing: 4) {
                                YenRow(title: snapshot.title(for: category), value: totals[category, default: 0].yen)
                                Text(remaining < 0 ? "超過 \((-remaining).yen)" : "残り \(remaining.yen)")
                                    .font(.footnote)
                                    .foregroundStyle(budgetTone(overspend: remaining < 0, colorScheme: colorScheme))
                            }
                        } else if let total = totals[category] {
                            YenRow(title: snapshot.title(for: category), value: total.yen)
                        }
                    }
                } else {
                    Text("合計を表示できません")
                }
                if ledger.plan.allowsProFeatures {
                    NavigationLink {
                        BudgetSettings(ledger: ledger, book: book, month: month)
                    } label: {
                        Text(budgets.isEmpty ? "費目別予算を設定" : "費目別予算").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("month-budgets")
                } else {
                    ProLock("費目別予算", ledger: ledger)
                }
            }
            Section("支出") {
                if records.isEmpty {
                    if isSettled {
                        Text("記録を追加するには精算済みを解除してください")
                    } else if snapshot.member != nil {
                        Button("この月の支出を記録") { showingEntry = true }
                            .disabled(ledger.shareBusy)
                    } else {
                        Text("この月に記録がありません。共有の設定を確認してください")
                    }
                }
                ForEach(records) { expense in
                    NavigationLink {
                        ExpenseDetail(ledger: ledger, book: book, expenseID: expense.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            let title = expense.label ?? snapshot.title(for: expense.category)
                            Text(title)
                            Text(expense.amount.yen).font(.headline).monospacedDigit()
                                .accessibilityLabel(expense.spokenAmount(names: names))
                            Text("\(expense.date.formatted(japaneseDate.month().day())) · \(expense.payerCaption(names: names))")
                                .font(.footnote).foregroundStyle(.secondary)
                                .accessibilityLabel(expense.date.formatted(japaneseDate.month().day()))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .frame(minHeight: 44)
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        if !isSettled, snapshot.member != nil, !ledger.shareBusy {
                            Button {
                                pendingDeletion = expense
                                confirmDeletion = true
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("月の明細")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSettlement) {
            SettlementReview(ledger: ledger, book: book, month: month)
        }
        .sheet(isPresented: $showingEntry) {
            let today = Month.localDay(.now)
            EntryForm(snapshot: snapshot, repository: ledger,
                      initialDate: month.dates.contains(today) ? today : month.start)
        }
        .confirmationDialog("この支出を削除しますか？", isPresented: $confirmDeletion,
                            titleVisibility: .visible, presenting: pendingDeletion) { expense in
            Button("削除", role: .destructive) {
                do { try ledger.delete(expense.id, from: book, matching: expense) }
                catch BookError.settled { deletionFailure = "月の明細で精算済みを解除してください。" }
                catch { deletionFailure = "支出を削除できませんでした。明細を確認してください。" }
            }
        } message: { expense in
            Text("\(expense.label ?? snapshot.title(for: expense.category)) \(expense.amount.yen)とレシート写真を削除します。")
        }
        .alert("支出の削除", isPresented: Binding(
            get: { deletionFailure != nil },
            set: { if !$0 { deletionFailure = nil } }
        )) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(deletionFailure ?? "")
        }
    }

    private func monthButton(_ offset: Int, icon: String, title: String) -> some View {
        Button {
            month = month.advanced(by: offset)
        } label: {
            Image(systemName: icon).frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }
}

@MainActor
private struct SettlementReview: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ledger: CloudLedger
    let book: Book
    let month: Month
    @State private var confirming = false
    @State private var failure = false

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = ledger.snapshot, snapshot.book == book,
                   let result = try? settlement(in: month, snapshot: snapshot) {
                    let isSettled = snapshot.settlementDates[month] != nil
                    let action = isSettled ? "精算済みを解除" : "精算済みにする"
                    Section {
                        SettlementAmount(value: result, names: snapshot.names)
                            .accessibilityIdentifier("settlement-amount")
                        DisclosureGroup("1円の端数の扱い") {
                            Text("折半と比率では、支払った人が端数の1円を負担します。返金では、受け取った人に端数の1円を割り当てます。固定額では、指定した人以外が残額を負担します。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(month.start.formatted(japaneseDate.year().month()))
                    }
                    Section {
                        Button(action) { confirming = true }
                            .frame(minHeight: 44)
                            .disabled(snapshot.member == nil || ledger.shareBusy)
                    } footer: {
                        switch result {
                        case .settled:
                            Text("解除すると、この月に支出を追記できます。")
                        case .open(nil):
                            Text("送金は不要です。精算済みにすると、この月の記録が締まります。")
                        case .open(.some(_)):
                            Text("支払いを確認してから記録してください。この操作で送金は行われません。")
                        }
                    }
                    .confirmationDialog(action, isPresented: $confirming, titleVisibility: .visible) {
                        Button(action) {
                            do { try ledger.setSettled(!isSettled, month: month, in: book) }
                            catch { failure = true }
                        }
                    }
                } else {
                    Text("精算額を表示できません")
                }
            }
            .navigationTitle("月の精算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("精算の状態を保存できませんでした", isPresented: $failure) {
                Button("閉じる", role: .cancel) {}
            }
        }
    }
}

@MainActor
struct EntryForm: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: LedgerSnapshot
    let repository: any BookRepository
    let isRecurring: Bool
    private let original: Expense?
    private var names: Names { snapshot.names }
    @State private var amount = ""
    @State private var date: Date
    @FocusState private var amountFocused: Bool
    @State private var category = Category.groceries
    @State private var payer: Member
    @State private var mode = Mode.equal
    @State private var first = ""
    @State private var second = ""
    @State private var fixedAmount = ""
    @State private var label = ""
    @State private var refund = false
    @State private var failure = ""

    init(snapshot: LedgerSnapshot, repository: any BookRepository, isRecurring: Bool = false,
         initialDate: Date = ScreenshotDemo.day ?? Month.localDay(.now), editing expense: Expense? = nil) {
        self.snapshot = snapshot
        self.repository = repository
        self.isRecurring = isRecurring
        original = expense
        _payer = State(initialValue: expense?.payer ?? snapshot.member ?? .first)
        _date = State(initialValue: expense?.date ?? initialDate)
        _amount = State(initialValue: expense.map { String(abs($0.amount)) } ?? "")
        _category = State(initialValue: expense?.category ?? .groceries)
        _label = State(initialValue: expense?.label ?? "")
        _refund = State(initialValue: (expense?.amount ?? 0) < 0)
        switch expense?.split ?? .equal {
        case .equal:
            break
        case let .ratio(first, second):
            _mode = State(initialValue: .ratio)
            _first = State(initialValue: String(first))
            _second = State(initialValue: String(second))
        case let .fixed(firstYen):
            _mode = State(initialValue: .fixed)
            _fixedAmount = State(initialValue: String(firstYen))
        }
    }

    private enum Mode: String, CaseIterable {
        case equal = "折半"
        case ratio = "比率"
        case fixed = "固定額"
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("金額（円）", text: $amount)
                    .font(.title2.monospacedDigit())
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                Picker("支払った人", selection: $payer) {
                    ForEach(Member.allCases, id: \.self) { Text(names[$0]).tag($0) }
                }
                Picker("費目", selection: $category) {
                    ForEach(snapshot.categories, id: \.self) { Text(snapshot.title(for: $0)).tag($0) }
                }
                DisclosureGroup(isRecurring ? "メモ・分け方 \(mode.rawValue)" : "日付・返金・メモ・分け方 \(mode.rawValue)") {
                    if !isRecurring {
                        Toggle("返金として記録", isOn: $refund)
                        DatePicker("日付", selection: $date, displayedComponents: .date)
                            .environment(\.calendar, Month.calendar)
                            .environment(\.timeZone, Month.calendar.timeZone)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                    TextField("メモ（任意）", text: $label)
                    Picker("分け方", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    switch mode {
                    case .equal:
                        EmptyView()
                    case .ratio:
                        TextField("\(names.first) の負担（%）", text: $first).keyboardType(.numberPad)
                        TextField("\(names.second) の負担（%）", text: $second).keyboardType(.numberPad)
                    case .fixed:
                        TextField("\(names.first) の負担（円）", text: $fixedAmount).keyboardType(.numberPad)
                        Text("\(names.second) が残りを負担します。").font(.footnote)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(original != nil ? "支出を編集" : (isRecurring ? "定期入力を追加" : "支出を記録"))
            .navigationBarTitleDisplayMode(.inline)
            .defaultFocus($amountFocused, true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("記録できません", isPresented: Binding(
                get: { !failure.isEmpty },
                set: { if !$0 { failure = "" } }
            )) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text(failure)
            }
        }
    }

    private func save() {
        let split: SplitRule
        switch mode {
        case .equal: split = .equal
        case .ratio: split = .ratio(first: Int(first) ?? -1, second: Int(second) ?? -1)
        case .fixed: split = .fixed(firstYen: Int(fixedAmount) ?? -1)
        }
        do {
            let day = isRecurring ? Month.localDay(.now) : Month.calendar.startOfDay(for: date)
            guard let yen = Int(amount), yen > 0 else { throw LedgerError.invalidAmount }
            let expense = try Expense(id: original?.id ?? UUID(), amount: refund ? -yen : yen, date: day,
                                      category: category, payer: payer, split: split, label: label)
            if let original {
                try repository.update(expense, replacing: original, in: snapshot.book)
            } else if isRecurring {
                try repository.addTemplate(expense, to: snapshot.book)
            } else {
                try repository.add(expense, to: snapshot.book)
            }
            dismiss()
        } catch BookError.settled {
            failure = "月の明細で精算済みを解除してから保存してください。"
        } catch BookError.expenseChanged {
            failure = "支出が変更されました。編集画面を閉じ、最新の明細を確認してください。"
        } catch LedgerError.invalidAmount {
            failure = "金額を1円以上の整数で入力してください。"
        } catch LedgerError.invalidRatio {
            failure = "負担の比率を整数で入力し、合計を100%にしてください。"
        } catch LedgerError.invalidFixedAmount {
            failure = "固定額を0円から入力した金額までの整数で入力してください。"
        } catch LedgerError.labelTooLong {
            failure = "メモを30文字以内にしてください。"
        } catch {
            failure = "保存できませんでした。もう一度お試しください。"
        }
    }
}

@MainActor
struct EditNames: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let repository: any BookRepository
    let original: Names
    @State private var first: String
    @State private var second: String
    @State private var failure = false

    init(snapshot: LedgerSnapshot, repository: any BookRepository) {
        book = snapshot.book
        self.repository = repository
        original = snapshot.names
        _first = State(initialValue: snapshot.names.first)
        _second = State(initialValue: snapshot.names.second)
    }

    var body: some View {
        let firstValue = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondValue = second.trimmingCharacters(in: .whitespacesAndNewlines)
        Form {
            TextField(Names.firstDefault, text: $first)
            TextField(Names.secondDefault, text: $second)
            Text("それぞれ異なる名前を8文字以内で入力してください。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("ふたりの名前")
        .alert("名前を保存できませんでした", isPresented: $failure) {
            Button("閉じる", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do {
                        try repository.rename(Names(first: firstValue, second: secondValue),
                                              replacing: original, in: book)
                        dismiss()
                    } catch {
                        failure = true
                    }
                }
                .disabled(firstValue.isEmpty || secondValue.isEmpty || firstValue == secondValue
                          || firstValue.count > 8 || secondValue.count > 8)
            }
        }
    }
}

let japaneseDate = Date.FormatStyle(locale: Locale(identifier: "ja_JP"),
                                    calendar: Month.calendar, timeZone: Month.calendar.timeZone)

extension Int {
    var yen: String { formatted(.number.locale(Locale(identifier: "ja_JP"))) + "円" }
}

struct YenRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let value: String

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text(title)
                Text(value).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(title, value: value)
        }
    }
}

extension Expense {
    func payerCaption(names: Names) -> String {
        "\(names[payer])が\(amount < 0 ? "返金を受け取り" : "支払い")"
    }

    func spokenAmount(names: Names) -> String {
        "\(payerCaption(names: names))、\(abs(amount).yen)"
    }
}

// Use the ledger category throughout the app where Objective-C also exposes Category.
typealias Category = FutariDomain.Category

extension Category {
    var title: String {
        switch self {
        case .groceries: return "食料品"
        case .dining: return "外食"
        case .household: return "日用品"
        case .housing: return "住居"
        case .utilities: return "水道光熱"
        case .transport: return "交通"
        case .leisure: return "娯楽"
        default: return "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .groceries: return "cart.fill"
        case .dining: return "fork.knife"
        case .household: return "basket.fill"
        case .housing: return "house.fill"
        case .utilities: return "bolt.fill"
        case .transport: return "tram.fill"
        case .leisure: return "sparkles"
        case .other: return "ellipsis.circle.fill"
        default: return "tag.fill"
        }
    }
}
