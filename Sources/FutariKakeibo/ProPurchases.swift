import Foundation
import FutariDomain
import StoreKit

enum ProProduct: String, CaseIterable {
    case monthly = "local.futarikakeibo.pro.monthly"
    case yearly = "local.futarikakeibo.pro.yearly"
    case lifetime = "local.futarikakeibo.pro.lifetime"

    var title: String {
        switch self {
        case .monthly: "月額"
        case .yearly: "年額"
        case .lifetime: "買い切り"
        }
    }
}

@MainActor
final class ProPurchases {
    private weak var ledger: CloudLedger?
    private var listener: Task<Void, Never>?
    private var entitlementScan: Task<Bool?, Error>?
    private var activating = false
    private var busy = false

    init(ledger: CloudLedger) {
        self.ledger = ledger
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.receive(result)
            }
        }
    }

    deinit { listener?.cancel() }

    func activate() async {
        guard !activating else { return }
        activating = true
        defer { activating = false }
        _ = try? await refresh()
        for await result in Transaction.unfinished {
            await receive(result)
        }
    }

    func products() async throws -> [ProProduct: Product] {
        let products = try await Product.products(for: ProProduct.allCases.map(\.rawValue))
        return products.reduce(into: [:]) { catalog, product in
            guard let option = ProProduct(rawValue: product.id) else { return }
            catalog[option] = product
        }
    }

    func buy(_ product: Product) async throws -> String? {
        guard !busy else { return "購入手続き中です" }
        guard ledger?.canPurchasePro == true else { return "家計簿の準備ができてから購入できます" }
        busy = true
        defer { busy = false }
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            guard try await refresh(including: transaction) != nil else {
                return "購入を確認しました。家計簿の準備ができ次第、反映します"
            }
            await transaction.finish()
            return nil
        case .success(.unverified):
            throw PurchaseError.verification
        case .pending:
            return "購入の承認を待っています"
        case .userCancelled:
            return "購入を取り消しました"
        @unknown default:
            throw PurchaseError.verification
        }
    }

    func restore() async throws -> Bool? {
        guard !busy else { throw PurchaseError.save }
        busy = true
        defer { busy = false }
        try await AppStore.sync()
        return try await refresh()
    }

    private func receive(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            if ProProduct(rawValue: result.unsafePayloadValue.productID) != nil {
                ledger?.purchaseUpdateFailed()
            }
            return
        }
        guard ProProduct(rawValue: transaction.productID) != nil else { return }
        if (try? await refresh(including: transaction)) != nil {
            await transaction.finish()
        }
    }

    /// Returns nil while awaiting a book, otherwise whether this Apple Account has Pro.
    /// Failures are published to the ledger before being thrown.
    private func refresh(including transaction: Transaction? = nil) async throws -> Bool? {
        while let pending = entitlementScan {
            _ = await pending.result
        }
        let task = Task {
            defer { entitlementScan = nil }
            return try await scanEntitlements(including: transaction)
        }
        entitlementScan = task
        return try await task.value
    }

    private func scanEntitlements(including transaction: Transaction?) async throws -> Bool? {
        var grants: [String: ProGrant] = [:]
        var unverified = false

        func include(_ transaction: Transaction, current: Bool) {
            guard let option = ProProduct(rawValue: transaction.productID),
                  option == .lifetime || transaction.expirationDate != nil else { return }
            let revoked = transaction.revocationDate != nil || transaction.isUpgraded
            guard current || revoked else { return }
            let grant = ProGrant(purchasedAt: transaction.purchaseDate, expiresAt: transaction.expirationDate,
                                 revoked: revoked)
            let ownership = transaction.ownershipType == .familyShared ? "family" : "purchased"
            let grantID = "\(transaction.environment.rawValue)/\(ownership)/\(transaction.originalID)"
            if let previous = grants[grantID], !grant.supersedes(previous) { return }
            grants[grantID] = grant
        }

        for option in ProProduct.allCases {
            switch await Transaction.latest(for: option.rawValue) {
            case .verified(let latest)?: include(latest, current: false)
            case .unverified?: unverified = true
            case nil: break
            }
        }
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let current): include(current, current: true)
            case .unverified(let current, _):
                if ProProduct(rawValue: current.productID) != nil { unverified = true }
            }
        }
        if let transaction { include(transaction, current: true) }
        let active = ProGrant.access(from: grants.values, at: .now).plan.allowsProFeatures
        guard let ledger else { throw PurchaseError.save }
        let saved = try ledger.updatePurchases(grants, verificationFailed: unverified)
        guard !unverified else { throw PurchaseError.verification }
        return saved ? active : nil
    }
}

enum PurchaseError: Error {
    case verification, save
}
