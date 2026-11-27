import FutariDomain
import SwiftUI

@MainActor
struct ProLock: View {
    let feature: String
    let ledger: CloudLedger
    @State private var showingPaywall = false

    init(_ feature: String, ledger: CloudLedger) {
        self.feature = feature
        self.ledger = ledger
    }

    var body: some View {
        Button {
            showingPaywall = true
        } label: {
            Label(feature, systemImage: "lock").frame(minHeight: 44)
        }
        .sheet(isPresented: $showingPaywall) {
            ProPaywall(ledger: ledger)
        }
    }
}

@MainActor
struct NewBookForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ledger: CloudLedger
    @State private var title = ""
    @State private var failure = false

    var body: some View {
        Form {
            TextField("家計簿名（旅行、子どもなど）", text: $title)
            Button("作成") {
                do {
                    try ledger.createBook(title: title)
                    dismiss()
                } catch { failure = true }
            }
            .frame(minHeight: 44)
            .disabled(cleanTitle.isEmpty || cleanTitle.count > 30 || !ledger.canCreateBook)
        }
        .navigationTitle("家計簿を追加")
        .alert("家計簿を作成できませんでした", isPresented: $failure) {
            Button("閉じる", role: .cancel) {}
        }
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}

@MainActor
struct BudgetSettings: View {
    @ObservedObject var ledger: CloudLedger
    let book: Book
    let month: Month
    @State private var selectedMonth: Month?
    @State private var copyFailed = false

    private var activeMonth: Month { selectedMonth ?? month }

    var body: some View {
        List {
            if !ledger.plan.allowsProFeatures {
                ProLock("費目別予算", ledger: ledger)
            } else if let snapshot = ledger.snapshot, snapshot.book == book {
                budgetRows(snapshot)
            } else {
                Text("予算を表示できません。家計簿を開き直してください")
            }
        }
        .navigationTitle("費目別予算")
        .alert("前月の予算を引き継げませんでした", isPresented: $copyFailed) {
            Button("閉じる", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func budgetRows(_ snapshot: LedgerSnapshot) -> some View {
        let targetMonth = activeMonth
        let categories = snapshot.categories
        let limits = (snapshot.budgets[targetMonth] ?? [:]).filter { categories.contains($0.key) }
        let previousLimits = (snapshot.budgets[targetMonth.advanced(by: -1)] ?? [:]).filter { categories.contains($0.key) }
        let totals = try? Ledger.totals(for: snapshot.expenses, in: targetMonth)
        let unsetCategories = categories.filter { limits[$0] == nil }

        Section {
            HStack {
                Menu {
                    Button("前の月") { selectedMonth = targetMonth.advanced(by: -1) }
                    Button("次の月") { selectedMonth = targetMonth.advanced(by: 1) }
                    if targetMonth != month {
                        Button("最初に表示した月に戻る") { selectedMonth = nil }
                    }
                } label: {
                    Label(targetMonth.start.formatted(japaneseDate.year().month()), systemImage: "chevron.down")
                        .font(.headline)
                        .frame(minHeight: 44)
                }
                Spacer()
            }
            if limits.isEmpty, !previousLimits.isEmpty {
                Button("前月の予算を引き継ぐ") {
                    do { try ledger.copyPreviousBudget(to: targetMonth, in: book) }
                    catch { copyFailed = true }
                }
                .frame(minHeight: 44)
                .disabled(snapshot.member == nil || ledger.shareBusy)
            }
            if let totals {
                if !limits.isEmpty {
                    if let total = try? Ledger.budgetTotal(limits: limits, totals: totals) {
                        BudgetProgressRow(title: "予算の合計", progress: total)
                    } else {
                        Text("予算の合計を表示できません")
                    }
                }
            } else {
                Text("支出の合計を表示できません")
            }
        }

        if !limits.isEmpty {
            Section("設定済みの費目") {
                ForEach(categories.filter { limits[$0] != nil }, id: \.self) { category in
                    let limit = limits[category]
                    NavigationLink {
                        BudgetEditor(ledger: ledger, book: book, month: targetMonth, category: category, limit: limit)
                    } label: {
                        let title = snapshot.title(for: category)
                        if let limit, let totals {
                            BudgetProgressRow(
                                title: title,
                                systemImage: category.systemImage,
                                progress: Ledger.budgetProgress(limit: limit, spent: totals[category, default: 0])
                            )
                        } else {
                            Label(title, systemImage: category.systemImage)
                                .frame(minHeight: 44)
                        }
                    }
                    .disabled(snapshot.member == nil || ledger.shareBusy)
                }
            }
        }

        if !unsetCategories.isEmpty {
            Section {
                DisclosureGroup("予算を追加する費目（\(unsetCategories.count)）") {
                    ForEach(unsetCategories, id: \.self) { category in
                        NavigationLink {
                            BudgetEditor(ledger: ledger, book: book, month: targetMonth, category: category, limit: nil)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: category.systemImage)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                    .accessibilityHidden(true)
                                YenRow(title: snapshot.title(for: category), value: "未設定")
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(snapshot.member == nil || ledger.shareBusy)
                    }
                }
            }
        }
    }

}

func budgetTone(overspend: Bool, colorScheme: ColorScheme) -> Color {
    guard overspend else {
        return colorScheme == .dark
            ? Color(red: 150.0 / 255, green: 225.0 / 255, blue: 177.0 / 255)
            : Color(red: 23.0 / 255, green: 73.0 / 255, blue: 56.0 / 255)
    }
    return colorScheme == .dark
        ? Color(red: 1, green: 146.0 / 255, blue: 155.0 / 255)
        : Color(red: 166.0 / 255, green: 27.0 / 255, blue: 41.0 / 255)
}

extension BudgetProgress {
    var percentageCaption: String {
        guard let displayPercentage else { return "割合なし" }
        if overspend > 0 {
            return "超過 \((-displayPercentage).formatted(.number.precision(.fractionLength(0))))%"
        }
        let used = (percentageUsed ?? 0).rounded()
        let remaining = spent < 0 ? (100 * Double(self.remaining) / Double(limit)).rounded() : 100 - used
        return "使用 \(used.formatted(.number.precision(.fractionLength(0))))%（残り \(remaining.formatted(.number.precision(.fractionLength(0))))%）"
    }
}

private struct BudgetProgressRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var systemImage: String? = nil
    let progress: BudgetProgress
    private var tone: Color {
        budgetTone(overspend: progress.overspend > 0, colorScheme: colorScheme)
    }

    var body: some View {
        let rowLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 6) {
            rowLayout {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(tone)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }
                Text(title)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text("予算 \(progress.limit.yen)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            rowLayout {
                ProgressView(value: progress.progress)
                    .tint(tone)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text(progress.percentageCaption)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            rowLayout {
                Text(progress.overspend > 0 ? "超過 \(progress.overspend.yen)" : "残り \(progress.remaining.yen)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(tone)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text("支払済 \(progress.spent.yen)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct BudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ledger: CloudLedger
    let book: Book
    let month: Month
    let category: Category
    @State private var amount: String
    @State private var failure = false

    init(ledger: CloudLedger, book: Book, month: Month, category: Category, limit: Int?) {
        self.ledger = ledger
        self.book = book
        self.month = month
        self.category = category
        _amount = State(initialValue: limit.map { String($0) } ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("予算（円）", text: $amount).keyboardType(.numberPad)
                Button("保存") { save() }
                    .frame(minHeight: 44)
                    .disabled(!amount.isEmpty && !(1...Ledger.maximumYen).contains(Int(amount) ?? 0))
            } footer: {
                Text("空欄で保存すると予算を解除します。")
            }
        }
        .navigationTitle(ledger.snapshot?.title(for: category) ?? category.title)
        .alert("予算を保存できませんでした", isPresented: $failure) {
            Button("閉じる", role: .cancel) {}
        }
    }

    private func save() {
        do {
            try ledger.setBudget(Int(amount), category: category, month: month, in: book)
            dismiss()
        } catch { failure = true }
    }
}

@MainActor
struct RecurringSettings: View {
    @ObservedObject var ledger: CloudLedger
    let book: Book
    @State private var adding: LedgerSnapshot?
    @State private var stopping: Expense?
    @State private var failure = false

    var body: some View {
        List {
            if let snapshot = ledger.snapshot, snapshot.book == book {
                let writable = snapshot.member != nil && !ledger.shareBusy
                Section {
                    ForEach(snapshot.recurring) { template in
                        LabeledContent(template.label ?? snapshot.title(for: template.category), value: template.amount.yen)
                            .frame(minHeight: 44)
                            .swipeActions {
                                if writable {
                                    Button("停止", role: .destructive) { stopping = template }
                                }
                            }
                            .accessibilityAction(named: Text("定期入力を停止")) {
                                if writable { stopping = template }
                            }
                    }
                    Button("定期入力を追加") { adding = snapshot }
                        .frame(minHeight: 44)
                        .disabled(!writable)
                } footer: {
                    Text("アプリを開くと、その月の支出を毎月1件記録します。")
                }
            }
        }
        .navigationTitle("定期入力")
        .sheet(item: $adding) { EntryForm(snapshot: $0, repository: ledger, isRecurring: true) }
        .confirmationDialog("この定期入力を停止しますか？", isPresented: Binding(
            get: { stopping != nil },
            set: { if !$0 { stopping = nil } }
        ), titleVisibility: .visible, presenting: stopping) { template in
            Button("停止", role: .destructive) {
                do { try ledger.stopTemplate(template, in: book) }
                catch { failure = true }
            }
        } message: { _ in
            Text("記録済みの支出は明細に残ります。")
        }
        .alert("定期入力を停止できませんでした", isPresented: $failure) {
            Button("閉じる", role: .cancel) {}
        }
    }
}
