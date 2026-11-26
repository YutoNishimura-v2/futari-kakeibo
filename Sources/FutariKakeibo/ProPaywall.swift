import StoreKit
import SwiftUI

@MainActor
struct ProPaywall: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ledger: CloudLedger
    @State private var selection = ProProduct.yearly
    @State private var products: [ProProduct: Product] = [:]
    @State private var loading = !ScreenshotDemo.isEnabled
    @State private var priceLoadFailed = false
    @State private var busy = false
    @State private var status: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("用途に合わせて家計簿を追加する")
                    Text("費目ごとに予算と残額を確認する")
                    Text("家賃など毎月の支出を自動で記録する")
                } header: {
                    Text("Proでできること")
                } footer: {
                    Text("費目別予算と定期入力は、共有家計簿でふたりとも使えます。iCloudでの共有と同期は無料です。")
                }
                Section {
                    ForEach(ProProduct.allCases, id: \.self) { option in
                        optionRow(option)
                    }
                    if loading {
                        ProgressView("価格を読み込み中")
                    } else if !ScreenshotDemo.isEnabled && (priceLoadFailed || products.count < ProProduct.allCases.count) {
                        if priceLoadFailed {
                            Text("価格を取得できませんでした").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("価格を再読み込み") { Task { await loadProducts() } }
                            .frame(minHeight: 44)
                    }
                } footer: {
                    Text(purchaseTerms)
                        .accessibilityIdentifier("purchase-terms")
                }
                Section {
                    Button("購入手続きへ") { Task { await buy() } }
                        .fontWeight(.semibold)
                        .frame(minHeight: 44)
                        .disabled(busy || products[selection] == nil || !ledger.canPurchasePro)
                    Button("購入を復元") { Task { await restore() } }
                        .frame(minHeight: 44)
                        .disabled(busy || ScreenshotDemo.isEnabled)
                    if busy { ProgressView("購入情報を確認中") }
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
                LegalLinks()
            }
            .navigationTitle("ふたりの家計簿 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .task { await loadProducts() }
        }
    }

    private func optionRow(_ option: ProProduct) -> some View {
        return Button {
            selection = option
        } label: {
            LabeledContent {
                Text(price(for: option) ?? (loading ? "読み込み中" : "価格未取得"))
                    .foregroundStyle(.secondary)
            } label: {
                Label(option.title, systemImage: selection == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(.primary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selection == option ? .isSelected : [])
    }

    private func price(for option: ProProduct) -> String? {
        if let demo = ScreenshotDemo.price(for: option) { return demo }
        guard let product = products[option] else { return nil }
        return product.description.contains("仮の値") ? "\(product.displayPrice)（仮の値）" : product.displayPrice
    }

    private var purchaseTerms: String {
        let amount = price(for: selection).map { " \($0)" } ?? ""
        switch selection {
        case .monthly:
            return "月ごとに自動更新\(amount)。更新を止めるには、終了の24時間前までに「設定」→「サブスクリプション」で解約してください。"
        case .yearly:
            return "対象の方は14日間無料。年ごとに自動更新\(amount)。無料体験を含め、終了の24時間前までに「設定」→「サブスクリプション」で解約できます。"
        case .lifetime:
            return "お支払いは一回\(amount)。自動更新はありません。"
        }
    }

    private func loadProducts() async {
        guard !ScreenshotDemo.isEnabled else { return }
        loading = true
        priceLoadFailed = false
        defer { loading = false }
        do {
            products.merge(try await ledger.purchases.products()) { _, new in new }
        } catch {
            priceLoadFailed = true
        }
    }

    private func buy() async {
        guard !busy, let product = products[selection] else { return }
        busy = true
        status = nil
        defer { busy = false }
        do {
            status = try await ledger.purchases.buy(product) ?? "購入を確認しました"
        } catch PurchaseError.save {
            status = "購入情報を家計簿に保存できませんでした。「購入を復元」をお試しください。"
        } catch {
            status = "購入を確認できませんでした。もう一度お試しください。"
        }
    }

    private func restore() async {
        guard !busy else { return }
        busy = true
        status = nil
        defer { busy = false }
        do {
            if let restored = try await ledger.purchases.restore() {
                status = restored ? "購入を復元しました" : "有効な購入は見つかりませんでした"
            } else {
                status = "購入情報を確認しました。家計簿の準備ができ次第、反映します"
            }
        } catch {
            status = "購入を復元できませんでした。もう一度お試しください。"
        }
    }
}
