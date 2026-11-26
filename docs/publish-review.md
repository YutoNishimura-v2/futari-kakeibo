# 公開前の文字列監査

追跡対象68ファイル中68ファイルを確認した。該当した40行に、公開前に取り除くべき認証情報の実値は見つからなかった。隠しパスにある5ファイルは、専門担当者の確認結果を反映した。

`token`、`key`、`secret`、`password`、`auth`、`credential` を含む代入や設定を、大文字・小文字を区別せず確認した。設定やスキーマへの引数と、公開スキャンで指摘された費目IDも含めた。7文字以上の引用値は先頭4文字と `…` を表示する。

| ファイルと行 | 該当行 | 判定 |
| --- | --- | --- |
| `Sources/FutariDomain/Ledger.swift:26` | `rawValue = "cust…"` | identifier |
| `Sources/FutariDomain/LedgerWidgetData.swift:5` | `public static let key = "ledg…"` | identifier |
| `Sources/FutariDomain/LedgerWidgetData.swift:8` | `guard let group = Bundle.main.object(forInfoDictionaryKey: "Ledg…") as? String else { return nil }` | identifier |
| `Sources/FutariDomain/Plan.swift:8` | `let value = Bundle.main.object(forInfoDictionaryKey: "Ledg…") as? String` | identifier |
| `Sources/FutariKakeibo/BookModel.swift:62` | `attribute("id", .UUIDAttributeType), attribute("key", .stringAttributeType),` | identifier |
| `Sources/FutariKakeibo/CloudLedger.swift:116` | `UserDefaults.standard.set(zone, forKey: "ledg…")` | identifier |
| `Sources/FutariKakeibo/CloudLedger.swift:120` | `private var selectedID = ScreenshotDemo.isEnabled ? nil : UserDefaults.standard.string(forKey: "ledg…")` | identifier |
| `Sources/FutariKakeibo/CloudLedger.swift:148` | `if let zone = UserDefaults.standard.dictionary(forKey: "ledg…"),` | identifier |
| `Sources/FutariKakeibo/CloudLedger.swift:152` | `if let id = Bundle.main.object(forInfoDictionaryKey: "Ledg…") as? String,` | identifier |
| `Sources/FutariKakeibo/CloudLedger.swift:273` | `let key = "ledg…"` | identifier |
| `Sources/FutariKakeibo/CloudLedger.swift:444` | `UserDefaults.standard.set(selectedID, forKey: "ledg…")` | identifier |
| `Sources/FutariKakeibo/FutariLedgerMigration.xcdatamodeld/FutariLedgerV1.xcdatamodel/contents:11` | `<attribute name="key" optional="YES" attributeType="String"/>` | identifier |
| `Sources/FutariKakeibo/FutariLedgerMigration.xcdatamodeld/FutariLedgerV2.xcdatamodel/contents:11` | `<attribute name="key" optional="YES" attributeType="String"/>` | identifier |
| `Sources/FutariKakeibo/LaunchScreen.storyboard:13` | `<view key="view" contentMode="scal…" id="laun…">` | identifier |
| `Sources/FutariKakeibo/LaunchScreen.storyboard:14` | `<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>` | identifier |
| `Sources/FutariKakeibo/LaunchScreen.storyboard:15` | `<autoresizingMask key="auto…" widthSizable="YES" heightSizable="YES"/>` | identifier |
| `Sources/FutariKakeibo/LaunchScreen.storyboard:16` | `<color key="back…" systemColor="syst…"/>` | identifier |
| `Sources/FutariKakeibo/LegalLinks.swift:36` | `guard let base = Bundle.main.object(forInfoDictionaryKey: "Ledg…") as? String,` | identifier |
| `Sources/FutariKakeibo/SettlementReminder.swift:10` | `private let key = "ledg…"` | identifier |
| `Sources/FutariKakeibo/Store.swift:25` | `splitKey = "equal"` | identifier |
| `Sources/FutariKakeibo/Store.swift:28` | `splitKey = "ratio"` | identifier |
| `Sources/FutariKakeibo/Store.swift:31` | `splitKey = "fixed"` | identifier |
| `Sources/FutariKakeibo/Store.swift:132` | `let names = Names(first: defaults.string(forKey: "firs…") ?? Names.firstDefault,` | identifier |
| `Sources/FutariKakeibo/Store.swift:133` | `second: defaults.string(forKey: "seco…") ?? Names.secondDefault)` | identifier |
| `checks/paid-tools.test.mjs:52` | `return { bookID, key: 'shop…' + field + '/' + item, value, time, id };` | identifier |
| `checks/pro-ledger.test.mjs:74` | `const templateKey = 'recu…' + rentID;` | identifier |
| `checks/pro-ledger.test.mjs:75` | `const monthKey = 'month/' + february / 1000;` | identifier |
| `checks/shared-book.test.mjs:12` | `amount: 101, date: january, categoryKey: 'groc…', payerKey: 'second',` | identifier |
| `checks/shared-book.test.mjs:13` | `splitKey: 'equal', firstValue: 0, label: ' お米 ',` | identifier |
| `checks/shared-book.test.mjs:20` | `{ ...oldEntry, id: '0000…', splitKey: 'ratio', firstValue: 60 },` | identifier |
| `checks/shared-book.test.mjs:21` | `{ ...oldEntry, id: '0000…', splitKey: 'fixed', firstValue: 28 },` | identifier |
| `checks/shared-book.test.mjs:100` | `const invalid = { ...legacy, expenses: [...legacy.expenses, { ...oldEntry, payerKey: 'some…' }] };` | placeholder |
| `checks/shared-book.test.mjs:107` | `{ key: 'first', value: '花', time: 50, id: '0000…' },` | identifier |
| `checks/shared-book.test.mjs:108` | `{ key: 'second', value: '空', time: 40, id: '0000…' },` | identifier |
| `checks/shared-book.test.mjs:111` | `{ key: 'first', value: '春', time: 60, id: '0000…' },` | identifier |
| `.github/workflows/screenshots.yml:19` | `persist-credentials: false` | CIの真偽値設定 |
| `.github/workflows/screenshots.yml:33` | `key=lambda r: …` | Pythonの並べ替え用の引数 |
| `.github/workflows/screenshots.yml:75` | `GH_TOKEN: ${{ github.token }}` | GitHubが実行時に渡すトークンの参照 |
| `.github/workflows/screenshots.yml:83` | `basic="$(printf 'x-ac…' "$GH_TOKEN" …)"` | 実行時のトークンから認証ヘッダーの値を生成する処理 |
| `.github/workflows/screenshots.yml:85` | `http.extraHeader=Authorization: Basic $basic` | 実行時に生成したシェル変数の参照 |

| ファイル（全行を確認） | 確認内容 | 判定 |
| --- | --- | --- |
| `.github/scripts/export-screenshots.py` | 検索条件に一致する行なし | 該当なし |
| `.github/workflows/ios.yml` | 検索条件に一致する行なし | 該当なし |
| `.gitignore` | 除外パターン5件 | 該当なし |
| `Sources/FutariKakeibo/FutariLedgerMigration.xcdatamodeld/.xccurrentversion` | `_XCCurrentVersionName` の値は `Futa…` | Core Dataのモデル名。検索条件に一致する行なし |

## Publication allowlist

2026年11月27日の公開スキャンが報告した10件。引用符の内側をエスケープ展開せずに UTF-8 で SHA-256 にかけ、基点のコミットで9件、過去のコミットで残る1件の一致を確認した。

| SHA-256 | ファイルと行 | コミット | 値（先頭4文字） | 判定 |
| --- | --- | --- | --- | --- |
| `d2e36bb8b95b472c8108d4de482f3d8b27717b291f90ebd183d509c5da040ad0` | `Sources/FutariDomain/Ledger.swift:26` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `cust…` | 許可（カスタム費目の UUID） |
| `72610d3c9e48c32bd354a739eb016aa58824b4e2fcccb1b38d4ffb9661d61727` | `Sources/FutariDomain/RecurringEntry.swift:7` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `\(bo…` | 許可（家計簿と繰り返し項目の UUID および月の時刻） |
| `3be04c27fcd52603e3d497fc9766c5f294c5c1c63a6237ca8f5738e22b86a833` | `Sources/FutariKakeibo/CloudLedger.swift:248` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `\(ev…` | 許可（ストア識別子とイベント種別） |
| `c91915104460bbc34cd8adcc193891a25c74236f2c15a7446325528d2116bcc3` | `Sources/FutariKakeibo/CloudLedger.swift:809` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `budg…` | 許可（月の時刻と費目コードを使う予算フィールド） |
| `f1f25ea358b5588e9ac8705e19c223010eb5900852f83b261ce08d4cb73ee1e3` | `Sources/FutariKakeibo/CloudLedger.swift:816` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `recu…` | 許可（繰り返し項目の UUID を使うフィールド） |
| `3aaa5e8c06d5df31b15bbeca551bce5e8455da326936df38acf45eb83805d000` | `Sources/FutariKakeibo/CloudLedger.swift:1147` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `ledg…` | 許可（家計簿の UUID を使う共有履歴の保存キー） |
| `dd6c780710601f9ef98352949fc558bdbdceb8041e7f285d47a3b8b4b4d3c28f` | `Sources/FutariKakeibo/CloudLedger.swift:1113` | `c8acf819240582f610e683f1d3b4b718871fb15d` | `ledg…` | 許可（固定の接頭辞と家計簿の UUID を使う UserDefaults の保存キー） |
| `3f7dcb5214608a9ff750b9272f94085082fbc123e39aea455da6965e2a67a5ef` | `Sources/FutariKakeibo/ProPurchases.swift:127` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `\(tr…` | 許可（ストア環境、購入の所有区分、元取引 ID） |
| `0f04bc89beab3c541e046ee9612c31773c738d49fadd8c0a2478bfec252237bd` | `checks/pro-ledger.mjs:9` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `${bo…` | 許可（家計簿と繰り返し項目の識別子および月の時刻） |
| `7cee51587a78647f5435cd6e2b1cf266ef60c5f2dba73447a6662e2aebae9029` | `checks/shared-book.test.mjs:9` | `ff9d81db63a3ae494af170bcb0373b2b915801dc` | `mont…` | 許可（テスト用の月フィールド） |
