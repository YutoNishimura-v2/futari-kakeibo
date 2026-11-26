import Charts
import FutariDomain
import SwiftUI
import UniformTypeIdentifiers

struct ShoppingItem: Identifiable {
    let id: UUID
    let name: String
    let checked: Bool
}

enum LedgerTheme: String, CaseIterable {
    case standard, green, plum

    var title: String {
        switch self {
        case .standard: "標準"
        case .green: "深緑"
        case .plum: "すみれ"
        }
    }

    var tint: Color? {
        switch self {
        case .standard: nil
        case .green: .teal
        case .plum: .purple
        }
    }
}

@MainActor
struct PaidBookTools: View {
    @ObservedObject var ledger: CloudLedger
    let book: Book
    @AppStorage("ledger.theme") private var theme = LedgerTheme.standard
    @State private var exporting = false
    @State private var exportDocument: CSVDocument?
    @State private var exportFailed = false

    var body: some View {
        Form {
            if !ledger.plan.allowsProFeatures {
                ProLock("有料プランで使う", ledger: ledger)
            } else if let snapshot = ledger.snapshot, snapshot.book == book, snapshot.member != nil {
                NavigationLink("支出の推移") { SpendingCharts(ledger: ledger, book: book) }
                Button("CSVを書き出す") {
                    exportDocument = CSVDocument(snapshot: snapshot)
                    exporting = true
                }
                NavigationLink("買い物リスト") { ShoppingList(ledger: ledger, book: book) }
                NavigationLink("費目を追加・編集") { CustomCategories(ledger: ledger, book: book) }
                NavigationLink("精算日の通知") { SettlementReminderSettings(ledger: ledger) }
                Picker("テーマ", selection: $theme) {
                    ForEach(LedgerTheme.allCases, id: \.self) { option in
                        Label(option.title, systemImage: "paintpalette")
                            .foregroundStyle(option.tint ?? .primary)
                            .tag(option)
                    }
                }
                Section("ホーム画面") {
                    Text("ウィジェット一覧で「ふたりの家計簿」を追加できます。")
                        .font(.footnote)
                }

            } else {
                Text("この家計簿を開けません")
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: .commaSeparatedText, defaultFilename: "ふたりの家計簿.csv") { result in
            if case .failure = result { exportFailed = true }
        }
        .navigationTitle("家計簿の便利機能")
        .alert("CSVを書き出せませんでした", isPresented: $exportFailed) {
            Button("閉じる", role: .cancel) {}
        }
    }
}

private struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let data: Data

    init(snapshot: LedgerSnapshot) {
        let header = ["日付", "費目", "金額（円）", "支払った人", "メモ", "精算済み"]
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        day.timeZone = Month.calendar.timeZone
        let rows = snapshot.expenses.map { expense in
            [day.string(from: expense.date),
             snapshot.title(for: expense.category), String(expense.amount), snapshot.names[expense.payer],
             expense.label ?? "", snapshot.settled.contains(Month(containing: expense.date)) ? "はい" : "いいえ"]
        }
        data = ProInsights.csv([header] + rows)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
private struct SpendingCharts: View {
    @ObservedObject var ledger: CloudLedger
    let book: Book
    @State private var month = Month(containing: Month.localDay(.now))
    @State private var yearly = true

    var body: some View {
        let start = yearly ? month.advanced(by: 1 - Month.calendar.component(.month, from: month.start))
            : month.advanced(by: -1)
        List {
            Picker("期間", selection: $yearly) {
                Text("年間").tag(true)
                Text("前月比").tag(false)
            }
            .pickerStyle(.segmented)
            HStack {
                arrow(-1)
                Spacer()
                Text(yearly ? month.start.formatted(japaneseDate.year()) : month.start.formatted(japaneseDate.year().month()))
                Spacer()
                arrow(1)
            }
            if let snapshot = ledger.snapshot, snapshot.book == book,
               !snapshot.expenses.contains(where: {
                   (start.start..<start.advanced(by: yearly ? 12 : 2).start).contains($0.date)
               }) {
                Text("この期間の支出がありません。家計簿で支出を記録してください")
            } else if let snapshot = ledger.snapshot, snapshot.book == book,
               let values = try? ProInsights.spending(snapshot.expenses, starting: start, count: yearly ? 12 : 2) {
                Chart(values) { value in
                    BarMark(x: .value("月", monthLabel(value)), y: .value("支出（円）", value.amount))
                        .accessibilityLabel(Text(monthLabel(value)))
                        .accessibilityValue(Text(value.amount.yen))
                }
                .chartXAxis {
                    let labels = values.enumerated().compactMap { index, value in
                        !yearly || index.isMultiple(of: 3) ? monthLabel(value) : nil
                    }
                    AxisMarks(values: labels)
                }
                .frame(height: 180)
                DisclosureGroup("月ごとの支出額") {
                    ForEach(values) { value in
                        Text("\(value.month.start.formatted(japaneseDate.year().month())) \(value.amount.yen)")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !yearly, let previous = values.first, let current = values.last {
                    let change = current.amount - previous.amount
                    YenRow(title: "前月との差", value: (change > 0 ? "+" : "") + change.yen)
                }
            } else {
                Text("支出の推移を表示できません")
            }
        }
        .navigationTitle("支出の推移")
    }

    private func monthLabel(_ value: MonthlySpending) -> String {
        value.month.start.formatted(japaneseDate.month())
    }

    private func arrow(_ direction: Int) -> some View {
        Button {
            month = month.advanced(by: direction * (yearly ? 12 : 1))
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(direction < 0 ? (yearly ? "前年" : "前月") : (yearly ? "翌年" : "翌月"))
    }
}

@MainActor
private struct ShoppingList: View {
    @ObservedObject var ledger: CloudLedger
    let book: Book
    @State private var name = ""
    @State private var failed = false

    var body: some View {
        List {
            if let snapshot = ledger.snapshot, snapshot.book == book {
                let writable = snapshot.member != nil && !ledger.shareBusy
                Section {
                    TextField("品目名", text: $name)
                    Button("追加") {
                        update {
                            try ledger.addShoppingItem(name, in: book)
                            name = ""
                        }
                    }
                    .frame(minHeight: 44)
                    .disabled(!writable || !(1...60).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count))
                }
                Section {
                    if snapshot.shopping.isEmpty {
                        Text(writable ? "品目名を入力して「追加」を押してください"
                             : "買い物を追加するには共有の設定を確認してください")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.shopping) { item in
                        Toggle(item.name, isOn: Binding(
                            get: { item.checked },
                            set: { checked in update { try ledger.setShoppingItem(item, checked: checked, in: book) } }
                        ))
                        .disabled(!writable)
                        .swipeActions {
                            if writable {
                                Button("削除", role: .destructive) {
                                    update { try ledger.removeShoppingItem(item, in: book) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("買い物リスト")
        .alert("買い物リストを保存できませんでした", isPresented: $failed) {
            Button("閉じる", role: .cancel) {}
        }
    }

    private func update(_ action: () throws -> Void) {
        do { try action() } catch { failed = true }
    }
}

@MainActor
private struct CustomCategories: View {
    @ObservedObject var ledger: CloudLedger
    let book: Book

    var body: some View {
        List {
            if let snapshot = ledger.snapshot, snapshot.book == book {
                NavigationLink("費目を追加") {
                    CategoryEditor(ledger: ledger, book: book, category: Category(customID: UUID()), name: "")
                }
                ForEach(snapshot.categories.filter(\.isCustom), id: \.self) { category in
                    NavigationLink(snapshot.title(for: category)) {
                        CategoryEditor(ledger: ledger, book: book, category: category, name: snapshot.title(for: category))
                    }
                }
            }
        }
        .disabled(ledger.snapshot?.member == nil || ledger.shareBusy)
        .navigationTitle("費目を追加・編集")
    }
}

@MainActor
private struct CategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    let ledger: CloudLedger
    let book: Book
    let category: Category
    @State private var name: String
    @State private var failed = false

    init(ledger: CloudLedger, book: Book, category: Category, name: String) {
        self.ledger = ledger
        self.book = book
        self.category = category
        _name = State(initialValue: name)
    }

    var body: some View {
        Form {
            TextField("費目名", text: $name)
            Button("保存") {
                do {
                    try ledger.saveCategory(category, name: name, in: book)
                    dismiss()
                } catch { failed = true }
            }
            .disabled(!(1...30).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count))
        }
        .navigationTitle("費目名")
        .alert("費目を保存できませんでした", isPresented: $failed) {
            Button("閉じる", role: .cancel) {}
        }
    }
}

@MainActor
private struct SettlementReminderSettings: View {
    @ObservedObject private var reminder = SettlementReminder.shared
    @ObservedObject var ledger: CloudLedger
    @State private var day = SettlementReminder.shared.day
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Picker("通知日", selection: $day) {
                    Text("オフ").tag(0)
                    ForEach(1...31, id: \.self) { Text("毎月\($0)日").tag($0) }
                }
                Button("保存") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await reminder.save(day: day, access: ledger.access) }
                        catch { failed = true }
                    }
                }
            } footer: {
                Text("朝9時に通知します。指定日がない月は月末になります。")
            }
            if reminder.refreshFailed {
                Text("通知を更新できませんでした。設定で通知を許可してから、もう一度保存してください。")
                    .font(.footnote)
            }
        }
        .disabled(busy)
        .navigationTitle("精算日の通知")
        .alert("通知を設定できませんでした", isPresented: $failed) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("設定で通知を許可してから、もう一度お試しください。")
        }
    }
}
