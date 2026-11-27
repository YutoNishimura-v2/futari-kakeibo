# ふたりの家計簿・第6回独立批評（参考パターン比較）

**総合評価: 63 / 100（7軸平均 6.3 / 10，第5回: 57 / 100・平均 5.7 / 10） — 支出の編集・削除と予算の「支払済・残り割合・前月引継」、ホームの精算動詞・支出内訳が入ったことで実用上の致命傷は大きく減った一方、2〜7日目の継続フック・課金訴求・初回iCloud待機・未ビルド課題により、国内トップ帯の夫婦・カップル向け家計簿パターン（★4.5・評価 15,240 件・公称 120 万人・無料＋有料）と売れる水準ではまだ差がある。**

- **基準コミットの確認**: `land/main`（`HEAD`）は `489636e7`（「Apply the top fixes from the round 5 household ledger critique (Codex)」）であり、第5回修正コミット `f341392a` と差分ゼロ（`git diff f341392a 489636e7` が空）の再適用コミットがベースに含まれていることを確認した。
- **検証制約と「推測」表記**: GitHub Actions の承認待ちにより CI スクリーンショットが未取得であり、実機・シミュレータ画像も存在しない。そのため、本批評は SwiftUI ソース・デモデータ・StoreKit 設定・App Store 掲載原稿のみを根拠とし、**視覚・配色・レイアウト・フォント・操作感に関する判定にはすべて「推測」を付す**。
- **価格表記の確認**: `FutariKakeibo.storekit:6,11,22,45,50,61,72,77,88`、`Sources/FutariKakeibo/ProPaywall.swift:86`、`Sources/FutariKakeibo/ScreenshotDemo.swift:21`、`docs/release-checklist.md:11-13` はいずれも「仮の値」「仮」と明記されており、`docs/app-store/metadata.ja.json:5`・`docs/app-store/subscription-terms.ja.md:7`・`docs/legal/terms.md:18` は未確定の金額を記載していない。**オーナー未確定の価格を確定値として表示している箇所は見つからなかった**が、正式価格は依然として未確定である。

---

## 1. 7軸スコア一覧（第5回との比較）

| 軸 | 第5回 (r5) | 第6回 (r6) | 主な変化と評価理由 |
| --- | ---: | ---: | --- |
| 1. 初回1分（最初の価値までのタップ数） | 6 | **7** | 保存直後に自分の最新支出がホームに表示されるようになった（+1）一方、iCloud 初期取込待ちの入力ブロックが未解消 |
| 2. ホームの明快さ（主数値1つ・過不足なし） | 6 | **7** | 精算文に「支払う／受け取る」が付き、支出合計の折りたたみ内に円グラフが入った（+1）が、予算残額がホームになく円グラフ凡例も隠れている |
| 3. メイン画面（予算・明細・精算） | 5 | **7** | 支出の編集・削除、予算の「支払済」「残り割合」「前月引継」と色分けが入り大きく改善（+2）。ただし既知課題 3 件と精算内訳の欠落が残る |
| 4. 課金画面（Paywall） | 6 | **6** | 第5回から未変更。全 Pro 機能・2人共用訴求・動的無料体験 CTA が弱く、正式価格も未確定 |
| 5. 2〜7日目の継続理由（ウィジェット・通知・招待） | 4 | **4** | 第5回から未変更。無料ウィジェット無表示、通知 20 時固定、メール手入力必須の招待導線がそのまま |
| 6. ストア公開準備（掲載文・画像・設定） | 6 | **6** | `ScreenshotTests.swift:63` の文言追従のみで、スクショ見出し原稿・アイコン組込・本番識別子・サポート URL は未整備 |
| 7. アクセシビリティ（文字拡大・VoiceOver・配色） | 7 | **7** | `BudgetProgressRow` の配色コントラスト検証と「予算」ラベル、ホーム円グラフの AX 回避は改善したが、`ProLock` と `.teal` 等が残課題 |
| **総合スコア** | **57 / 100** | **63 / 100** | 7軸合計 **44 / 70**（平均 **6.3 / 10**，r5 は 40 / 70・平均 5.7 / 10） |

---

## 2. 場面別の詳細比較（参考パターンとの対比）

### (1) 初回1分（最初の有用な答えまでのタップ数）
- **参考パターンの型**: アプリ起動後すぐ入力や月の全体像に触れられ、初回の保存から画面上の反映まで待たせない。
- **現状の実装**:
  - 既存の家計簿が開いていれば、ホーム「支出を記録」（`Sources/FutariKakeibo/FutariKakeiboApp.swift:82,125`）1タップ → 金額欄自動フォーカス（`691`）→ 数字入力 →「保存」1タップ（`694`）の **2操作＋桁数** で保存でき、保存後は `recentExpense`（`183-189`）のフォールバックにより **自分だけの支出も即座にホームへ表示される** ようになった。
  - しかし、`mayCreatePrimary`（`Sources/FutariKakeibo/CloudLedger.swift:131-133,479`）は iCloud サインイン時に private / shared 両ストアの初回 `.import` 完了まで主家計簿作成を待つため、その間 `snapshot == nil` となり「iCloudの家計簿を読み込んでいます」（`428`）の1行だけが出て記録ボタンすら表示されない（`80-93`）。初期同期の遅延時に初回1分目標を割るリスクが残る。

### (2) ホームの明快さ
- **参考パターンの型**: ホームの最上段を「誰がいくら払うか」または「予算の残り」の1つの主数値で導き、残額と超過を色で直感的に見分けさせ、月の支出内訳を一目で把握させる。
- **現状の実装**:
  - `settlementHeader`（`Sources/FutariKakeibo/FutariKakeiboApp.swift:191-230`）と `settlementTitle`（`232-245`）により、最大フォント（`.largeTitle.weight(.bold)`）1つで「あおいから 3,110円 受け取る」／「はるへ 3,110円 支払う」と方向まで明確になった（推測）。
  - 一方で、`HomeSpending`（`248-303`）は `DisclosureGroup` が閉じた状態から始まるため、初回表示のホームは「精算額・記録ボタン・直近1件・支出合計1行」だけとなり、参考パターンのようなカテゴリ別消費の全体像や予算残額・超過色が一目では入らない（推測）。
  - さらに `HomeSpending` を開いた場合の `SectorMark`（`276-282`）は `.chartLegend(.hidden)` を指定しており、直下の `YenRow`（`294-296`）にも色見本がないため、**円グラフの各色がどの費目か見た目で結びつかない**（推測）。

### (3) メイン画面（予算・明細・精算）
- **参考パターンの型**: 予算の「残り／超過」を色で即時判別し、「支払済」と残額・割合を並べて管理する。明細の修正・削除が迷わず行える。
- **現状の実装（改善点）**:
  - **編集・削除の実装**: `ExpenseDetail.swift:43-75` に編集ボタンと削除確認ダイアログ、`FutariKakeiboApp.swift:479-520` にスワイプ削除、`CloudLedger.swift:1130-1167` に精算済み月保護と写真同時削除が入り、誤入力を直せない致命傷が解消した。
  - **予算画面の充実**: `BudgetProgressRow`（`Sources/FutariKakeibo/ProSettings.swift:127-165`）に `予算`・`支払済`・`残り / 超過`・`残り割合`（`Ledger.swift:153-163`）が揃い、正残額（濃緑 `#174938` / 明緑 `#96E1B1`）と超過（濃赤 `#A61B29` / 明赤 `#FF929B`）が色分けされた。支出ゼロでも予算設定可能になり（`ProSettings.swift:66-123`）、前月予算の引継ぎボタン（`84-91`）も追加された。
- **現状の課題**:
  - `MonthDetail` の「費目別の合計」（`FutariKakeiboApp.swift:426-435`）では `残り / 超過` が `.foregroundStyle(.secondary)` のままで、残額と超過を色で区別できていない（推測）。
  - `SettlementReview`（`FutariKakeiboApp.swift:544-584`）に各人の支払合計・負担合計の内訳がなく、計算根拠を確認しづらい。
  - **既知課題（1）写真行の残留**: `CloudLedger.swift:1154-1167` で支出削除時にローカルの `copies` は消すが、別端末から遅れて同期された `LedgerExpenseRow`（最大 2 MB の `receiptJPEG` を含む）は `expenses(in:)`（`998`）が非表示にするだけでデータベースから削除されないため、ストレージが増え続ける。
  - **既知課題（2）定期入力の一時再生成**: `CloudLedger.swift:730-761` は `values[deletedExpenseKey(expense.id)] == nil`（`752`）で削除済み定期入力を抑止するが、別端末で `importedStores` 登録後に `LedgerExpenseRow` の削除だけ先に届き、`deletedExpense/<id>` の `LedgerEditRow` が後続の CloudKit バッチで届く順序になると、その間に `generateRecurring` が同じ `recurringID` の支出行を一時的に再生成し得る。
  - **既知課題（3）iOS 未ビルド・正規表現検査依存**: `checks/*.test.mjs` は Node の純粋関数テストと正規表現チェックのみで、Xcode での Swift コンパイル・UI テストは未実行。

### (4) 課金画面（Paywall）
- **参考パターンの型**: 無料枠で習慣づいたユーザーに対し、有料の価値・代表価格・お試し導線・2人利用の得を明確に提示する。
- **現状の実装**:
  - `ProPaywall.swift:18-26` は「家計簿追加・費目別予算・定期入力」の 3 点のみ記載し、実装済みの買い物リスト・支出推移グラフ・CSV・ウィジェット・精算日通知・カスタム費目・テーマ（`PaidBookTools.swift:46-60`）が伝わらない。
  - 最大の訴求である「1人の購入で共有家計簿のふたりとも Pro」がセクション脚注（`ProPaywall.swift:25`）に埋もれている。
  - 購入ボタンが常に「購入手続きへ」（`45`）で、`isEligibleForIntroOffer` 判定による「14日間無料で始める」等の動的 CTA がなく（`95` は静的文言）、正式価格も `FutariKakeibo.storekit` で仮の値（480 / 4,800 / 7,800 円）のままである。

### (5) 2〜7日目の継続理由（ウィジェット・通知・招待）
- **参考パターンの型**: ホーム画面ウィジェットや通知から毎日1タップで戻り、相手をすぐ招待して2人利用を定着させる。
- **現状の実装**:
  - `WidgetPublishing.swift:10` と `LedgerWidget.swift:54` は無料ユーザーに「有料プランで使う」とだけ出し、今月の支出や精算額を見せない。入力画面へ飛ぶ `widgetURL` もない（`LedgerWidget.swift:75-83`）。
  - 記録リマインダーは `person.2` 設定の奥で毎日 20 時固定（`BookSettings.swift:136-143,172-175`）で時刻変更ができない。
  - パートナー招待（`BookSettings.swift:199-216`）は相手の Apple Account メールアドレス手入力が必須で、未共有オーナー向けのホーム導線バナーもない。

### (6) ストア公開準備
- **参考パターンの型**: 実績数値や明確な価値訴求をストア画像・見出しに載せ、アイコンと法務・課金情報を揃えて公開する。
- **現状の実装**:
  - `docs/app-store/metadata.ja.json`・`review-notes.ja.md`・`subscription-terms.ja.md`・`app-privacy.md` は審査要件に対して正確。
  - 一方、参考パターンが実績数値（ユーザー数・評価等）や明快なベネフィットを大きく見せるのに対し、本リポジトリには **ストア用スクリーンショット見出し原稿** がなく、`ScreenshotTests.swift:23-81` は素の画面撮影のみ（しかも未実行）。なお実績数値が未到達の段階で架空の数字は載せられないため、実測値がない間は機能・数値例に基づく具体的見出しを作る必要がある。
  - `project.yml:15,29-39,77-78` には `AppIcon` アセット・本番 Bundle ID・本番 CloudKit コンテナ・`LEDGER_LEGAL_BASE_URL` が未反映で、サポート URL も未確定（`docs/release-checklist-detail.md:19`）。

### (7) アクセシビリティ
- **現状の良い点**: `BudgetProgressRow.tone`（`ProSettings.swift:131-140`）の明暗コントラスト、`YenRow`（`FutariKakeiboApp.swift:801-819`）の `isAccessibilitySize` 縦積み、`HomeSpending`（`274,279-280,290`）の最大文字サイズ時のグラフ非表示・`SectorMark` 読み上げ設定は丁寧。
- **残る課題**:
  - `ProLock`（`ProSettings.swift:19`）と便利機能リンク（`BookSettings.swift:45`）が `Label(..., systemImage: "lock")` のみで、VoiceOver に「ロック中・Pro案内を開く」ことが伝わらない。
  - `MonthDetail`（`FutariKakeiboApp.swift:404-410`）と `SpendingCharts`（`PaidBookTools.swift:124-130`）の月送り `HStack` が最大文字サイズで縦積みに切り替わらず折り返し崩れの恐れがある（推測）。
  - `LedgerWidget`（`LedgerWidget.swift:67`）の `minimumScaleFactor(0.5)` による極小化懸念（推測）、および `LedgerTheme.green`（`PaidBookTools.swift:26`）の `.teal` と白文字ボタン（`FutariKakeiboApp.swift:329`）のコントラスト低下懸念（推測）。

---

## 3. 参考パターンとのギャップ一覧（売上インパクト上位3件を順位付け）

### ギャップ 1（売上インパクト 1位）: 2〜7日目の継続フック欠如（無料ウィジェット未開放・通知時刻固定・招待摩擦）
- **場面**: 2〜7日目の継続利用・招待（ホーム／ウィジェット／設定）
- **該当箇所**: `Sources/FutariKakeibo/WidgetPublishing.swift:10`、`Sources/FutariWidget/LedgerWidget.swift:48-56,75-83`、`Sources/FutariKakeibo/BookSettings.swift:136-143,172-175,199-216`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:79-151`
- **内容**: 無料ユーザーはウィジェットに金額が出ず、クイック入力遷移（`widgetURL`）もない。記録通知は 20 時固定で設定奥に隠れ、招待も相手の Apple ID メール入力が必須でホーム上に誘う導線がないため、課金検討前に離脱しやすい。
- **機械検証できる合格条件**:
  - Node ソースチェックで、`WidgetPublishing.swift` が無料プランでも今月の支出合計または精算額を書き出し（`budgetRemaining` のみ Pro 限定）、`LedgerWidget.swift` が `.widgetURL(` を持ち無料時に `"有料プランで使う"` のみの空表示をしないこと。
  - `BookSettings.swift` に記録通知時刻（`hour` / `minute`）のユーザー選択状態があり、`FutariKakeiboApp.swift` に未共有かつ支出1件以上のオーナー向け招待導線が存在すること。

### ギャップ 2（売上インパクト 2位）: 課金画面（Paywall）の訴求不足と未確定価格
- **場面**: 課金画面（Paywall）
- **該当箇所**: `Sources/FutariKakeibo/ProPaywall.swift:18-26,45-48,83-99`、`FutariKakeibo.storekit:6,45,72`
- **内容**: 実装済み Pro 8機能のうち 3 つしか見せず、「1人分でパートナーも使える」主価値が脚注にある。年額選択時も動的対象判定付きの無料体験ボタン文言にならず、価格も仮の値のまま。
- **機械検証できる合格条件**:
  - Node ソースチェックで、`ProPaywall.swift` がプラン一覧より前に「1人分の購入で2人とも使える」旨と全主要 Pro 機能（複数家計簿・費目別予算・定期入力・買い物リスト・支出推移グラフ・CSV・ウィジェット・精算日通知）を含み、`isEligibleForIntroOffer` に応じてボタン文言を切り替えること。
  - オーナーの価格確定後、`FutariKakeibo.storekit` と `ProPaywall.swift` に `仮の値` 表記が残らないこと。

### ギャップ 3（売上インパクト 3位）: ホームの予算残額／超過色の欠如と円グラフ凡例の非表示
- **場面**: ホーム画面・月明細（日常の残額確認）
- **該当箇所**: `Sources/FutariKakeibo/FutariKakeiboApp.swift:90-92,148-150,271-302,426-435`
- **内容**: 参考パターンがホームで主数値と予算の残額／超過色を即座に伝えるのに対し、本アプリのホームは予算残額を一切出さず、費目別グラフも閉じた `DisclosureGroup` の中で `.chartLegend(.hidden)`（`282`）により色と費目の対応が読めない（推測）。`MonthDetail` の費目行（`430-431`）も残額・超過が同色（`.secondary`）のまま。
- **機械検証できる合格条件**:
  - Node ソースチェックで、`HomeSpending` 内に色と費目名を対応付ける凡例表示があり、`.chartLegend(.hidden)` 単独で色情報を隠していないこと、および `MonthDetail` の `残り` / `超過` 行（またはホームの予算サマリ）が `BudgetProgressRow.tone` 相当の色分けを持つこと。
  - Node 純粋関数テストで、その明暗カラーの相対輝度コントラスト比が 4.5:1 以上であること。

### ギャップ 4: 初回1分における iCloud 初期取込待ちの入力ブロック
- **場面**: 初回1分（初回起動〜最初の保存）
- **該当箇所**: `Sources/FutariKakeibo/CloudLedger.swift:131-133,427-428,479-485`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:80-93`
- **内容**: iCloud サインイン中に両ストアの初回 `.import` 完了まで `snapshot == nil` のまま入力ボタンを出さないため、低速回線環境で初回 1 分以内の保存を逃す。
- **機械検証できる合格条件**:
  - `checks/shared-book.test.mjs` の純粋関数テストで「取込前の仮ローカル記録 → 取込後に既存の記録済み／共有家計簿が到着」ケースで明細が重複・欠損なく統合されることを検証し、`CloudLedger.swift` が `mayCreatePrimary` 完了前でも入力開始を妨げない構成を持つこと。

### ギャップ 5: ストア公開準備（スクショ見出し原稿・アイコン・本番設定の未完了）
- **場面**: ストア公開準備（App Store 掲載・リリース設定）
- **該当箇所**: `docs/app-store/metadata.ja.json:1-7`、`Tests/FutariScreenshotTests/ScreenshotTests.swift:23-81`、`project.yml:15,29-39,77-78`、`docs/release-checklist-detail.md:19`
- **内容**: 参考パターンのストア画像は明確なベネフィットや実績数字を訴求しているが、本アプリはスクショ見出し原稿が未作成で、`AppIcon`・本番 Bundle ID / CloudKit コンテナ・法務 URL・サポート URL も未設定。
- **機械検証できる合格条件**:
  - `checks/app-store-metadata.test.mjs` が `docs/app-store/screenshots.ja.md` の存在、見出し 5 枚以上（各 22 文字以内）、未確定の架空実績数値なし、他社名・画像なしを検証し、`project.yml` に `AppIcon` と本番用識別子プレースホルダ不在の検査項目があること（実績数字は公開・計測後に追記）。

### ギャップ 6（既知課題 1）: 削除済み支出に後から到着したレシート写真行のストレージ残留
- **場面**: メイン画面（支出削除後の同期・ストレージ保全）
- **該当箇所**: `Sources/FutariKakeibo/CloudLedger.swift:991-1002,1154-1167,1186-1189,1212-1219`
- **内容**: 支出削除時に `deletedExpense/<id>` 編集行を残してローカルの `LedgerExpenseRow` を消すが、オフライン端末から後から同期された写真専用 `LedgerExpenseRow`（最大 2 MB の `receiptJPEG`）は `expenses(in:)`（`998`）で非表示化されるだけで削除されないため、端末と iCloud のストレージを圧迫し続ける。
- **機械検証できる合格条件**:
  - `checks/pro-ledger.test.mjs` の純粋関数テストで、`deletedExpense/<id>` が存在する状態の行集合に対して不要な遅着写真行をパージ対象として抽出しつつ削除マーカーを保持できること。
  - Node ソースチェックで、`CloudLedger.swift` が `deletedExpenseKey` 該当の不要 `LedgerExpenseRow` を削除可能なストア権限下で `context.delete` する清掃処理を持つこと。

### ギャップ 7（既知課題 2）: CloudKit 同期順序による削除済み定期入力の一時的再生成
- **場面**: メイン画面（定期入力の自動生成・同期）
- **該当箇所**: `Sources/FutariKakeibo/CloudLedger.swift:135-138,251-257,730-761`
- **内容**: 他端末で定期入力の当月明細を削除しても、CloudKit のレコード到着順によって `LedgerExpenseRow` 削除のみ先に反映され `deletedExpense/<id>` の `LedgerEditRow` が後続バッチで届く場合、`importedStores` が既に true になっていると `generateRecurring`（`752`）が欠損と誤認して同じ `recurringID` の支出を一時的に再生成し得る。
- **機械検証できる合格条件**:
  - `checks/pro-ledger.test.mjs` の純粋関数テストで、再生成後に遅れて `deletedExpense/<id>` が到着したケースでも表示が非表示に戻り、かつ孤立行の自動掃除ルールが通ること（または生成前条件・再照合規則で重複行を残さないこと）。
  - Node ソースチェックで `CloudLedger.swift` に遅着削除マーカー到着時の孤立 `recurringID` 行削除または生成抑止の整合ロジックが存在すること。

### ギャップ 8（既知課題 3 ＋ 精算内訳・アクセシビリティ未修正）: iOS 実ビルド未検証、精算内訳欠落、`ProLock` VoiceOver 等の残課題
- **場面**: 品質検証全般・精算確認画面・アクセシビリティ
- **該当箇所**: `checks/pro-ledger.test.mjs:108-120`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:404-410,544-584`、`Sources/FutariKakeibo/ProSettings.swift:19`、`Sources/FutariKakeibo/BookSettings.swift:45`、`Sources/FutariKakeibo/PaidBookTools.swift:26,124-130`
- **内容**:
  - **既知課題（3）**: 現在の Node 検査は純粋関数と Swift ソースへの正規表現マッチのみであり、iOS ビルド・XCUITest スクショ撮影は一度も通っていない（型不整合や実描画崩れを検出できないため、明確なギャップと判定する）。
  - `SettlementReview` に各人の支払合計・負担合計の内訳がなく、`ProLock` の鍵状態読み上げ、月送り `HStack` の最大文字サイズ対応、`.teal` テーマのコントラスト修正が未反映。
- **機械検証できる合格条件**:
  - `checks/ledger.test.mjs` / `checks/pro-ledger.test.mjs` にメンバー別支払合計・負担合計の内訳純粋関数テストと `PaidBookTools.swift` のテーマ色コントラスト比（>= 4.5:1）テストを追加し、ソースチェックで `ProLock` の `.accessibilityValue`/`.accessibilityHint` と `MonthDetail` / `SpendingCharts` の `isAccessibilitySize` 分岐を検証すること。加えて CI 承認後に `xcodebuild` と `FutariScreenshots` の成功ログを取得すること。

---

## 4. UI-RULES 準拠チェック（`file:line` 一覧）

`C:\Users\yuton\workspace\ai-secretary\docs\UI-RULES.md` に照合した確認結果は以下のとおり。なお **V1（紺のグラデーション・光る線・色の点の凡例・絵文字の多用・明朝の混在）および P5（英語の内部 ID・生エラー露出）に該当する違反は 0 件** だった。

| ルール | 該当箇所 (`file:line`) | 指摘内容 |
| --- | --- | --- |
| **C1（凡例）・G5** | `Sources/FutariKakeibo/FutariKakeiboApp.swift:276-296` | `HomeSpending` の `SectorMark` が `.foregroundStyle(by:)` で費目を色分けしつつ `.chartLegend(.hidden)`（`282`）にしており、直下の `YenRow`（`294-296`）にも色見本がないため色だけで費目を識別できない（推測）。 |
| **C1（1カード＝見出し＋主数値1つ・詳細折りたたみ）** | `Sources/FutariKakeibo/FutariKakeiboApp.swift:139-143` | ホームの直近支出行が「費目/メモ」「支払者キャプション」「金額」の3情報を常に並べており、支払者内訳を詳細画面へ寄せる余地がある（文字数自体は概ね 40 字以内・推測）。 |
| **C1（1カード＝見出し＋主数値1つ）** | `Sources/FutariWidget/LedgerWidget.swift:48-51` | `.systemSmall` ウィジェット内に家計簿名・`今月の予算残額`・`今月の支払う精算額` の 2 つの主数値と 5 要素が同時表示されている（推測）。 |
| **C1（詳細折りたたみ）** | `Sources/FutariKakeibo/ProSettings.swift:143-160` | `BudgetProgressRow` が 1 行内に「費目＋予算」「支払済」「残り/超過」「プログレスバー」「残り割合」の 5 要素をすべて展開表示している（推測）。 |
| **I3（読み込み中・失敗画面の質）** | `Sources/FutariKakeibo/FutariKakeiboApp.swift:80`, `Sources/FutariKakeibo/CloudLedger.swift:427-428` | iCloud 初期取込待ち（`snapshot == nil`）の間、ホームが読み込み文言 1 行のみの空画面になり、即時の入力や構造表示がない（推測）。 |
| **V2（文字切れ・はみ出し）・P1** | `Sources/FutariKakeibo/FutariKakeiboApp.swift:404-410`, `Sources/FutariKakeibo/PaidBookTools.swift:124-130` | `MonthDetail` と `SpendingCharts` の月・年送り `HStack` が `typeSize.isAccessibilitySize` で縦積みに切り替わらず、最大文字サイズで圧迫・切れの恐れがある（推測）。 |
| **V2（最小文字サイズ）** | `Sources/FutariWidget/LedgerWidget.swift:67` | `.systemSmall` 上の金額に `.minimumScaleFactor(0.5)` を使っており、桁数増や文字拡大時に可読性を損なう恐れがある（推測）。 |
| **V3 / アクセシビリティ配色** | `Sources/FutariKakeibo/PaidBookTools.swift:26`, `Sources/FutariKakeibo/FutariKakeiboApp.swift:167,329` | テーマ `green` の `.teal` がライトモードの `.borderedProminent` 白文字ボタンと低コントラストになる恐れがある（推測）。 |

---

## 5. 既知課題（Context 記載 3 件）の扱い整理

1. **既知課題 (1) 削除後に遅れて届いた写真行がストレージに残る**: **ギャップ 6 として計上**（`CloudLedger.swift:998,1154-1167,1212-1219`）。UI 上は隠れるが Core Data / CloudKit 上の最大 2 MB バイナリが解放されないため要修正。
2. **既知課題 (2) CloudKit 同期順による削除済み定期入力の一時的再生成**: **ギャップ 7 として計上**（`CloudLedger.swift:135-138,251-257,730-761`）。`importedStores` 到達後のバッチ分割到着で一時生成・孤立行発生が起こり得るため要修正。
3. **既知課題 (3) Swift チェックが正規表現のみで iOS ビルド未通**: **ギャップ 8 として計上**（`checks/pro-ledger.test.mjs` 全般）。コンパイル整合性・実画面レイアウト・Core Data / CloudKit 実動作が未確認である以上、出荷判定上の明確なギャップとして扱う。

---

## 対応

| ギャップ | 対応 |
| --- | --- |
| 1. 2〜7日目の継続フック（無料ウィジェット・通知時刻・招待導線） | **直した**（`Sources/FutariKakeibo/WidgetPublishing.swift:10`、`Sources/FutariWidget/LedgerWidget.swift:48`、`Sources/FutariKakeibo/BookSettings.swift:125`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:145`、`Sources/FutariKakeibo/CloudLedger.swift:635`）。無料プランでも精算額をウィジェット表示し（`budgetRemaining` のみ Pro 限定）、`.widgetURL` からの即記録導線を追加。記録リマインダー時刻を `DatePicker` で選択可能にし、未共有かつ支出1件以上のオーナー向けにホーム招待導線を追加。検証は `checks/pro-ledger.test.mjs:621` と `checks/pro-ledger.test.mjs:650`。 |
| 2. 課金画面（Paywall）の訴求強化と動的無料体験 CTA | **直した**（`Sources/FutariKakeibo/ProPaywall.swift:19`）。プラン一覧の前に「1人分の購入で、共有家計簿のふたりともProを使えます」および全主要 Pro 機能を明記し、`isEligibleForIntroOffer` に応じてボタン文言を切り替えるよう変更。なお正式価格はオーナー未確定のため `仮の値` 表記を保持している。検証は `checks/pro-ledger.test.mjs:481`。 |
| 3. ホームの予算サマリ・円グラフ凡例・月明細の残額/超過色 | **直した**（`Sources/FutariKakeibo/FutariKakeiboApp.swift:292`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:170`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:500`、`Sources/FutariKakeibo/ProSettings.swift:127`）。`HomeSpending` の `.chartLegend(.hidden)` を外して費目ごとの色見本付き凡例を表示し、`MonthDetail` の残り/超過およびホームの予算サマリに `budgetTone`（明暗コントラスト比 4.5:1 以上）を適用。検証は `checks/pro-ledger.test.mjs:469` と `checks/pro-ledger.test.mjs:666`。 |
| 4. 初回1分における iCloud 初期取込待ちの入力ブロック | **見送り**（取込前の仮ローカル記録から既存の個人・共有家計簿へ重複・欠損なく統合する動作は、複数 iCloud アカウントと実機・Xcode 環境での CloudKit 同期検証が必要であり Windows 上では検証できない。現行の `mayCreatePrimary` 待機を前提とする既存テストとも整合確認が別途必要）。 |
| 5. ストア公開準備（スクショ見出し原稿・アイコン・本番設定） | **見送り**（採用アイコン・本番 Bundle ID・CloudKit コンテナ・公開/サポート URL がオーナー未確定であり、`AppIcon` アセット組込および `FutariScreenshots` 実行には Xcode が必要）。 |
| 6. 削除済み支出に後から到着したレシート写真行の残留 | **直した**（`Sources/FutariKakeibo/CloudLedger.swift:917`、`Sources/FutariKakeibo/CloudLedger.swift:610`）。`deletedExpense/<id>` が存在する支出の遅着 `LedgerExpenseRow` を削除権限確認下で `context.delete` により清掃し、削除マーカーを保持する。検証は `checks/pro-ledger.mjs:76` と `checks/pro-ledger.test.mjs:677`。 |
| 7. CloudKit 同期順による削除済み定期入力の一時的再生成 | **直した**（`Sources/FutariKakeibo/CloudLedger.swift:610`、`Sources/FutariKakeibo/CloudLedger.swift:917`）。遅れて `deletedExpense/<id>` が到着した際も表示を非表示にしつつ、孤立した `recurringID` 行を `purgeDeletedExpenseRows` で自動削除する。検証は `checks/pro-ledger.mjs:76` と `checks/pro-ledger.test.mjs:677`。 |
| 8. iOS 実ビルド、精算内訳、`ProLock` VoiceOver・AX 等 | **次回**（今回の約 10 ファイル制限内で売上インパクト上位のギャップ 1〜3 と既知課題 6〜7 を優先実装した。加えて iOS ビルド・`FutariScreenshots`・VoiceOver・最大文字サイズの実画面確認には Xcode が必要）。 |

Windows で Node の純粋関数テストとソースチェックを実施。iOS ビルド、実画面、CloudKit の実機同期は未確認。
