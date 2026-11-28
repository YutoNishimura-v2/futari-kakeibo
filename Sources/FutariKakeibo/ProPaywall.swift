import Foundation
import StoreKit
import SwiftUI

@MainActor
struct ProPaywall: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ledger: CloudLedger
    @State private var selection = ProProduct.yearly
    @State private var products: [ProProduct: Product] = [:]
    @State private var yearlyIntroEligible = ScreenshotDemo.isEnabled
    @State private var loading = !ScreenshotDemo.isEnabled
    @State private var priceLoadFailed = false
    @State private var busy = false
    @State private var status: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1契約で共有家計簿のふたりともProを使えます")
                                .font(.headline)
                            Text("iCloudでの共有と同期は無料です。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    featureRow("家計簿を追加・費目ごとの予算と残額", systemImage: "chart.pie.fill")
                    featureRow("毎月の支出を自動で記録・精算日の通知", systemImage: "repeat.circle.fill")
                    featureRow("ふたりで共有できる買い物リスト・支出推移グラフ", systemImage: "cart.fill")
                    featureRow("CSV書き出し・ウィジェット・費目やテーマ変更", systemImage: "square.and.arrow.up.fill")
                } header: {
                    Text("Proでできること")
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
                    // Keep the terms addressable separately from the savings text in the list.
                    if let yearlySavings {
                        Text("年額は月額12か月分より約\(yearlySavings)%お得")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    Text(purchaseTerms)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("purchase-terms")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    if selection == .yearly && yearlyIntroEligible {
                        Label("無料体験終了の24時間前までに解約すれば請求されません", systemImage: "checkmark.shield.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Button {
                        Task { await buy() }
                    } label: {
                        Text(purchaseButtonTitle)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0, green: 91.0 / 255, blue: 191.0 / 255))
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .disabled(busy || (!ScreenshotDemo.isEnabled && (products[selection] == nil || !ledger.canPurchasePro)))
                    Button("購入を復元") { Task { await restore() } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.accentColor)
                        .disabled(busy)
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

    private func featureRow(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Color.accentColor)
        }
    }

    private var yearlyMonthlyAnchor: (perMonth: String, perPerson: String)? {
        if let demo = ScreenshotDemo.price(for: .yearly) {
            return ((demo / 12).yen, (demo / 24).yen)
        }
        guard let product = products[.yearly], product.price > 0 else { return nil }
        return (
            (product.price / 12).formatted(product.priceFormatStyle),
            (product.price / 24).formatted(product.priceFormatStyle)
        )
    }

    private func optionRow(_ option: ProProduct) -> some View {
        let title = option == .yearly && yearlyIntroEligible ? "年額（14日間無料）" : option.title
        return Button {
            selection = option
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .foregroundStyle(.primary)
                        if option == .yearly {
                            Text("おすすめ")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    if option == .yearly, let anchor = yearlyMonthlyAnchor {
                        Text("実質 月\(anchor.perMonth)（1人あたり月\(anchor.perPerson)）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 8)
                Text(price(for: option) ?? (loading ? "読み込み中" : "価格未取得"))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(selection == option ? .primary : .secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selection == option ? .isSelected : [])
    }

    private var purchaseButtonTitle: String {
        selection == .yearly && yearlyIntroEligible ? "14日間無料で始める" : "購入手続きへ"
    }

    private func price(for option: ProProduct) -> String? {
        if let demo = ScreenshotDemo.price(for: option) { return demo.yen }
        return products[option]?.displayPrice
    }

    private func priceAmount(for option: ProProduct) -> Decimal? {
        if let demo = ScreenshotDemo.price(for: option) { return Decimal(demo) }
        return products[option]?.price
    }

    private var yearlySavings: Int? {
        guard let monthly = priceAmount(for: .monthly), let yearly = priceAmount(for: .yearly),
              yearly > 0, yearly < monthly * 12 else { return nil }
        let savings = NSDecimalNumber(decimal: (1 - yearly / (monthly * 12)) * 100).intValue
        return savings > 0 ? savings : nil
    }

    private var purchaseTerms: String {
        let amount = price(for: selection).map { " \($0)" } ?? ""
        switch selection {
        case .monthly:
            return "月ごとに自動更新\(amount)。更新を止めるには、終了の24時間前までに「設定」→「サブスクリプション」で解約してください。"
        case .yearly:
            if yearlyIntroEligible {
                return "14日間無料でお試し後、年ごとに自動更新\(amount)。無料体験を含め、終了の24時間前までに「設定」→「サブスクリプション」で解約できます。"
            }
            return "年ごとに自動更新\(amount)。終了の24時間前までに「設定」→「サブスクリプション」で解約できます。"
        }
    }

    private func loadProducts() async {
        guard !ScreenshotDemo.isEnabled else { return }
        loading = true
        priceLoadFailed = false
        defer { loading = false }
        do {
            products.merge(try await ledger.purchases.products()) { _, new in new }
            if let subscription = products[.yearly]?.subscription, subscription.introductoryOffer != nil {
                yearlyIntroEligible = await subscription.isEligibleForIntroOffer
            } else {
                yearlyIntroEligible = false
            }
        } catch {
            priceLoadFailed = true
        }
    }

    private func buy() async {
        if ScreenshotDemo.isEnabled {
            status = "プレビューでは購入できません"
            return
        }
        guard !busy, ledger.canPurchasePro, let product = products[selection] else { return }
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
        if ScreenshotDemo.isEnabled {
            status = "プレビューでは購入を復元できません"
            return
        }
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
