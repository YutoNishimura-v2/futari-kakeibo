import XCTest

final class ScreenshotTests: XCTestCase {
    @MainActor
    func testLight() throws {
        try captureBook(style: "light", partner: false)
        try capturePaywall(style: "light")
    }

    @MainActor
    func testDark() throws {
        try captureBook(style: "dark", partner: true)
        try capturePaywall(style: "dark")
    }

    @MainActor
    private func captureBook(style: String, partner: Bool) throws {
        continueAfterFailure = false
        let app = launch(style: style, partner: partner)
        let homeMonth = element("home-month", in: app)
        let entry = element("home-entry", in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 12))
        capture("home", style, in: app)

        entry.tap()
        let amount = app.textFields["金額（円）"]
        waitForAmountKeyboard(amount, in: app)
        capture("entry", style, in: app)
        app.buttons["閉じる"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))

        homeMonth.tap()
        waitForTitle("月の明細", in: app)
        capture("monthly-detail", style, in: app)

        let settlement = element("month-settlement", in: app)
        try reveal(settlement, in: app)
        settlement.tap()
        waitForTitle("月の精算", in: app)
        let summary = app.staticTexts.matching(NSPredicate(
            format: "label == %@", "あおいさんがはるさんに3,110円支払えば精算完了です。"
        )).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        capture("settlement", style, in: app)
        app.buttons["閉じる"].tap()

        let budgets = element("month-budgets", in: app)
        try reveal(budgets, in: app)
        budgets.tap()
        waitForTitle("費目別予算", in: app)
        capture("budgets", style, in: app)
        if style == "light" {
            app.navigationBars["費目別予算"].buttons.firstMatch.tap()
            app.navigationBars["月の明細"].buttons.firstMatch.tap()
            entry.tap()
            waitForAmountKeyboard(amount, in: app)
            amount.typeText("1200")
            app.buttons["保存"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            let updatedMonth = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "home-month", "あおいから 3,710円 受け取る")
            ).firstMatch
            XCTAssertTrue(updatedMonth.waitForExistence(timeout: 5))
        }
        app.terminate()
    }

    @MainActor
    private func waitForAmountKeyboard(_ amount: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func capturePaywall(style: String) throws {
        let app = launch(style: style, free: true)
        let homeMonth = element("home-month", in: app)
        XCTAssertTrue(homeMonth.waitForExistence(timeout: 12))
        homeMonth.tap()
        let lock = app.buttons["費目別予算"]
        try reveal(lock, in: app)
        lock.tap()
        waitForTitle("ふたりの家計簿 Pro", in: app)
        XCTAssertTrue(app.staticTexts["Proでできること"].waitForExistence(timeout: 5))
        capture("paywall", style, in: app)
        let terms = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "purchase-terms", "年ごとに自動更新", "3,600円"
        )).firstMatch
        try reveal(terms, in: app)
        app.terminate()
    }

    @MainActor
    private func launch(style: String, partner: Bool = false, free: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-demo", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if style == "dark" { app.launchArguments.append("--screenshot-dark") }
        if partner { app.launchArguments.append("--screenshot-partner") }
        if free { app.launchArguments.append("--screenshot-free") }
        if free {
            app.launchEnvironment = Self.prices
        }
        app.launch()
        return app
    }

    private static var prices: [String: String] {
        get {
            guard let url = Bundle(for: ScreenshotTests.self).url(forResource: "FutariKakeibo", withExtension: "storekit"),
                  let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
                XCTFail("The local StoreKit catalog is missing or invalid.")
                return [:]
            }
            let products = catalog.products + catalog.subscriptionGroups.flatMap(\.subscriptions)
            return Dictionary(uniqueKeysWithValues: products.map { ($0.productID, $0.displayPrice) })
        }
    }

    private struct Catalog: Decodable {
        struct Product: Decodable {
            let productID: String
            let displayPrice: String
        }

        struct SubscriptionGroup: Decodable {
            let subscriptions: [Product]
        }

        let products: [Product]
        let subscriptionGroups: [SubscriptionGroup]
    }

    @MainActor
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func waitForTitle(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        for _ in 0..<3 {
            if element.isHittable { return }
            app.swipeUp()
        }
        _ = try XCTUnwrap(element.isHittable ? element : nil, "Missing control: \(element)")
    }

    @MainActor
    private func capture(_ screen: String, _ style: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(screen)-\(style)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
