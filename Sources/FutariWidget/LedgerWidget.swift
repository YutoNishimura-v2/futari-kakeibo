import FutariDomain
import SwiftUI
import WidgetKit

private struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: LedgerWidgetData?
    let pro: Bool
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, summary: nil, pro: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let now = Date.now
        let current = entry(at: now)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .autoupdatingCurrent
        if current.summary != nil, let monthEnd = local.dateInterval(of: .month, for: now)?.end {
            let next = min(monthEnd, current.summary?.proExpiresAt ?? monthEnd)
            completion(Timeline(entries: [current, entry(at: next)], policy: .atEnd))
        } else {
            completion(Timeline(entries: [current], policy: .never))
        }
    }

    private func entry(at date: Date) -> SummaryEntry {
        let data = LedgerWidgetData.defaults?.data(forKey: LedgerWidgetData.key)
        let decoded = data.flatMap { try? JSONDecoder().decode(LedgerWidgetData.self, from: $0) }
        let configured = Plan.configured.allowsProFeatures
        let valid = decoded.map { $0.proExpiresAt.map { $0 > date } ?? true } ?? false
        let summary = valid && decoded?.isCurrent(at: date) == true ? decoded : nil
        return SummaryEntry(date: date, summary: summary, pro: valid || configured)
    }
}

private struct SummaryView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let summary = entry.summary {
                Text(summary.book).font(.caption).lineLimit(1).privacySensitive()
                amount("今月の予算残額", summary.budgetRemaining)
                amount("今月の支払う精算額", summary.amountOwed)
            } else {
                Text("ふたりの家計簿").font(.headline)
                Text(entry.pro ? "アプリを開いて更新" : "有料プランで使う")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
    }

    private func amount(_ name: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { $0.formatted(.number.locale(Locale(identifier: "ja_JP"))) + "円" } ?? "—")
                .font(.headline.monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
                .privacySensitive()
        }
        .accessibilityElement(children: .combine)
    }
}

@main
struct LedgerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LedgerWidgetData.kind, provider: Provider()) { entry in
            SummaryView(entry: entry)
        }
        .configurationDisplayName("ふたりの家計簿")
        .description("今月の予算残額と支払う精算額を表示します。")
        .supportedFamilies([.systemSmall])
    }
}
