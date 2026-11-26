import Foundation

/// The single gate for paid features.
public enum Plan: String {
    case free, pro

    public static var configured: Plan {
        let value = Bundle.main.object(forInfoDictionaryKey: "LedgerPlan") as? String
        return value.flatMap(Plan.init(rawValue:)) ?? .free
    }

    public var allowsProFeatures: Bool { self == .pro }
}

public enum ProAccess: Equatable {
    case free, until(Date), lifetime

    public var plan: Plan { self == .free ? .free : .pro }

    public var expiresAt: Date? {
        if case let .until(date) = self { return date }
        return nil
    }
}

public struct ProGrant: Codable {
    public let purchasedAt: Date
    public let expiresAt: Date?
    public let revoked: Bool

    public init(purchasedAt: Date, expiresAt: Date?, revoked: Bool) {
        self.purchasedAt = purchasedAt
        self.expiresAt = expiresAt
        self.revoked = revoked
    }

    public func supersedes(_ previous: Self) -> Bool {
        if purchasedAt != previous.purchasedAt { return purchasedAt > previous.purchasedAt }
        if revoked != previous.revoked { return revoked }
        // StoreKit may extend the expiry without issuing a new purchase.
        return (expiresAt ?? .distantFuture) > (previous.expiresAt ?? .distantFuture)
    }

    public static func access<S: Sequence>(from grants: S, at now: Date) -> ProAccess where S.Element == Self {
        var latest = now
        for grant in grants where !grant.revoked && grant.purchasedAt <= now {
            guard let expiry = grant.expiresAt else { return .lifetime }
            latest = max(latest, expiry)
        }
        return latest > now ? .until(latest) : .free
    }
}
