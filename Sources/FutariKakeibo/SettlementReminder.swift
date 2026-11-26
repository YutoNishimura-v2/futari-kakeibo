import Combine
import Foundation
import FutariDomain
import UserNotifications

@MainActor
final class SettlementReminder: ObservableObject {
    @Published private(set) var refreshFailed = false
    static let shared = SettlementReminder()
    private let key = "ledger.settlementDay"
    private let prefix = "ledger.settlement."
    private let center = UNUserNotificationCenter.current()
    private var busy = false
    private var pendingAccess: ProAccess?

    var day: Int { UserDefaults.standard.integer(forKey: key) }

    func save(day: Int, access: ProAccess) async throws {
        guard access.plan.allowsProFeatures, !busy, (0...31).contains(day) else { throw BookError.unavailable }
        busy = true
        defer {
            busy = false
            if pendingAccess != nil {
                Task { await applyPendingAccess() }
            }
        }
        if day == 0 {
            await clear()
        } else {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw BookError.unavailable
            }
            try await schedule(day: day, before: access.expiresAt)
        }
        UserDefaults.standard.set(day, forKey: key)
        refreshFailed = false
    }

    func refresh(access: ProAccess) async {
        pendingAccess = access
        await applyPendingAccess()
    }

    private func applyPendingAccess() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        while let access = pendingAccess {
            pendingAccess = nil
            do {
                try await refreshSchedule(access: access)
                refreshFailed = false
            } catch {
                refreshFailed = true
            }
        }
    }

    private func refreshSchedule(access: ProAccess) async throws {
        if !access.plan.allowsProFeatures || day == 0 {
            await clear()
        } else {
            let status = await center.notificationSettings().authorizationStatus
            guard [.authorized, .provisional, .ephemeral].contains(status) else { throw BookError.unavailable }
            try await schedule(day: day, before: access.expiresAt)
        }
    }

    private func clear() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }

    private func schedule(day: Int, before expiry: Date?) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let now = Date.now
        guard let start = calendar.dateInterval(of: .month, for: now)?.start else { throw BookError.unavailable }
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        let byID = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        let delivered = Set(await center.deliveredNotifications().map { $0.request.identifier })
        var wanted: Set<String> = []
        var changes: [UNNotificationRequest] = []
        for offset in 0...12 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: start),
                  let date = ProInsights.settlementDate(day: day, in: month, calendar: calendar),
                  date > now, expiry.map({ date < $0 }) ?? true else { continue }
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            parts.calendar = calendar
            let id = "\(prefix)\(parts.year ?? 0)-\(parts.month ?? 0)"
            guard !delivered.contains(id) else { continue }
            wanted.insert(id)
            if let trigger = byID[id]?.trigger as? UNCalendarNotificationTrigger,
               trigger.dateComponents == parts { continue }
            let content = UNMutableNotificationContent()
            content.title = "今日は精算日です"
            content.body = "ふたりの家計簿で今月の精算額を確認できます。"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            changes.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        var applied: [String] = []
        do {
            for request in changes {
                try await center.add(request)
                applied.append(request.identifier)
            }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: applied.filter { byID[$0] == nil })
            for id in applied {
                if let previous = byID[id] {
                    do {
                        try await center.add(previous)
                    } catch {
                        refreshFailed = true
                    }
                }
            }
            throw error
        }
        center.removePendingNotificationRequests(withIdentifiers: Array(Set(byID.keys).subtracting(wanted)))
    }
}
