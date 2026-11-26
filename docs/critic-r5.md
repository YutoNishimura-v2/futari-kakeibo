# ふたりの家計簿・第5回独立批評（reference app 比較）

**総合評価: 57 / 100（7軸平均 5.7 / 10） — 公開品質の計算・同期基盤はあるが、reference app（★4.5・評価 15,240 件・「120万人」）水準で売れる状態には未達。**

本批評は Round 4（`042cbc40`、精算ファーストのホーム・予算残額/超過表示・空状態・精算日表示）反映後の `Sources/`、App Store 原稿、`docs/benchmark.md` を対象とする。実機や CI スクリーンショットが未取得のため、**ソースのみから行う見た目・配色・レイアウトの判定にはすべて「推測」を付す。**

---

## 1. 7軸スコアと一行理由

| 軸 | 点 (1–10) | 一行理由 |
| --- | ---: | --- |
| 1. 初回1分（導入〜初回保存・最初の価値・タップ数） | 6 | 記録は最短2操作＋金額桁数だが、iCloud 初回取込待ちで空ホームが止まり、保存直後も自分の明細がホームに出ない |
| 2. ホームの明快さ（主数値1つ・不要情報なし） | 6 | 精算額を最上段に置いた点は明快だが、「相手から ¥…」が動詞不足で、費目内訳や今月の視覚的な把握が欠ける |
| 3. 予算・精算画面 | 5 | 支出の編集・削除がなく誤入力を直せないうえ、予算行に「支払済」が出ず、支出ゼロ時は予算設定自体が塞がれている |
| 4. 課金画面（Paywall：内容・価格・体験・復元・一言価値） | 6 | StoreKit 価格表示・復元・規約リンクは堅実だが、Pro 8機能中3つしか訴求せず「1人分で2人使える」価値と無料体験 CTA が弱い |
| 5. 2〜7日目の継続理由（ウィジェット・通知・招待） | 4 | ウィジェットが無料時に「有料プランで使う」のみで、通知は20時固定・奥に埋没、招待は相手の Apple ID メアド必須で離脱しやすい |
| 6. ストア公開準備（掲載文・スクショ文言・審査メモ） | 6 | 掲載文と審査メモ・プライバシー回答は誠実かつ正確だが、ストア用スクショ見出し原稿・アイコン組込・本番設定が未完了 |
| 7. アクセシビリティ（Dynamic Type・VoiceOver・コントラスト） | 7 | 文字拡大の縦並び対応や等幅数字・読み上げ単位の配慮が厚い一方、`ProLock` が鍵状態を VoiceOver に伝えず、`.teal` の白文字コントラストに懸念（推測） |
| **総合スコア** | **57 / 100** | 誠実な無料＋買い切り設計と堅牢な精算計算が強みだが、**「編集・削除」「予算の支払済・グラフ」「招待の手軽さ」「日常の戻り先」**で reference app に大きく負ける |

---

## 2. 軸別の詳細所見

### (1) 初回1分（タップ数と最初の価値）
- **現状の動線**: ホーム（`Sources/FutariKakeibo/FutariKakeiboApp.swift:80-81`）の「支出を記録」を **1タップ** → `EntryForm`（`497-585`）で金額欄に自動フォーカス（`.defaultFocus($amountFocused, true)`, `571`）→ 数字キー **4タップ**（例: `1200`）→ 「保存」を **1タップ**（`574`）。計 **2操作＋金額桁数（約6タップ）** で最初の支出を保存できる。
- **つまずき**:
  1. `mayCreatePrimary`（`Sources/FutariKakeibo/CloudLedger.swift:131-133, 479`）が、iCloud サインイン中は private / shared 両ストアの初回 `.import` 完了まで primary book 作成を待つため、その間 `snapshot == nil` となり「iCloudの家計簿を読み込んでいます」（`428`）だけが出て「支出を記録」ボタンすら出ない。
  2. 保存直後にホームへ戻ると `settlementTitle`（`FutariKakeiboApp.swift:227-228`）は `"相手から 600円"` を表示するが、ホーム末尾の明細リンク（`131-145`）は `member.other`（相手）の支出しか拾わないため、**自分が今保存したばかりの支出がホームに見えない**。

### (2) ホームの明快さ
- `settlementHeader`（`FutariKakeiboApp.swift:178-231`）で月選択と精算額 1 つを最上段に置く構成はすっきりしている（推測）。
- 一方で reference app のホームが「円グラフ中央に『支出 325,600円』」で月全体の消費を直感的に見せるのに対し、本アプリは `今月の支出合計` が簡素な 1 行（`106`）でグラフがなく、`相手から 3,110円`（`227-228`）も「受け取る／支払う」の動詞が抜けている。また相手の最新支出行（`138-141`）に費目名・メモが出ないため、何を買ったか開くまで分からない。

### (3) 予算・精算画面
- **予算画面（`Sources/FutariKakeibo/ProSettings.swift:56-207`, `Sources/FutariDomain/Ledger.swift:151-170`）**:
  - Round 4 で `予算の合計` と各費目の `残り`/`超過`・割合・プログレスバーが入った。
  - しかし reference app（`食費 今月 40,000円 -103% 超過 41,098円 | 支払済 81,098円`）と比べると、**「支払済」額が `BudgetProgressRow` に欠落**している（`ProSettings.swift:145-160`）。また `Ledger.swift:156-160` は超過時に負の超過率（`-103%`）を出す一方、予算内は使用率（`83%`）を出しており、reference app の「残り割合（`17% 残り`）」と意味が反転して紛らわしい。
  - さらに `ProSettings.swift:68-71` が `snapshot.expenses.isEmpty` のときに `budgetRows` を隠して `FirstExpensePrompt` を出すため、月初に支出記録前から予算を組めない。月ごとの自動引継ぎ（前月コピー）もない（`CloudLedger.swift:810`）。
- **精算画面（`FutariKakeiboApp.swift:337-348, 433-494`）**:
  - 精算額の一文、1円の端数説明、0円精算の締め、精算日の表示は丁寧。ただし「はる支払合計・負担合計 vs あおい支払合計・負担合計」の**計算内訳**が出ないため、金額に疑問を持ったとき確認しづらい。
- **致命的欠落**: `ExpenseDetail.swift`（`21-46`）にも `MonthDetail`（`388-405`）にも**支出の編集・削除機能がない**（`CloudLedger.swift` にも更新・削除メソッドがない）。金額の打ち間違いを負の返金で相殺するしかなく、実用上大きな減点。

### (4) 課金画面（Paywall）
- **揃っている点**: 年額デフォルト選択（`ProPaywall.swift:8`）、StoreKit 実価格表示と失敗時の再読み込み（`33-39, 83-87`）、プラン別の自動更新／14日無料体験／買い切り条件（`89-99`）、`購入を復元`（`49-51`）、`LegalLinks()`（`55`）。
- **売る上で弱い点**:
  1. `Proでできること`（`19-21`）が「家計簿追加・費目別予算・定期入力」の 3 項目しか書かれておらず、実装済みの**買い物リスト・支出グラフ・CSV・ウィジェット・精算日通知・カスタム費目・テーマ**（`PaidBookTools.swift:46-64`）の価値が伝わらない。
  2. 「どちらかの購入で共有家計簿のふたりとも使える」という最大の差別化が脚注（`25`）に埋もれている。
  3. ボタンが常に「購入手続きへ」（`45`）で、年額選択時も「14日間無料で始める」にならず、対象資格判定（StoreKit の introductory offer eligibility）も行っていない（`95` は静的文言）。
  4. `FutariKakeibo.storekit`（`6, 45, 72`）は「仮の値」（480円 / 4,800円 / 7,800円）のままで、正式価格が未確定。

### (5) 2〜7日目の継続理由（ウィジェット・通知・招待）
- **ウィジェット（`Sources/FutariWidget/LedgerWidget.swift`, `Sources/FutariKakeibo/WidgetPublishing.swift`）**: `.systemSmall` のみで、無料ユーザーには金額を一切出さず「有料プランで使う」（`LedgerWidget.swift:54`）と表示するだけ。クイック入力用の `widgetURL` もない。
- **通知（`BookSettings.swift:125-184`, `SettlementReminder.swift`）**: 無料の記録リマインダーは**毎日20時固定**（`BookSettings.swift:173`）で時刻変更不可、かつ `person.2` 設定画面の奥にある。Pro の精算日通知も 3 階層奥（`person.2 -> 家計簿の便利機能 -> 精算日の通知`）。
- **パートナー招待（`BookSettings.swift:199-216`, `CloudLedger.swift:1177`）**: `cloud.shareParticipant(forEmailAddress:)` を使うため**相手の Apple Account メールアドレス手入力が必須**。普段 LINE 等でやり取りするカップルは相手の Apple ID メールを知らない／別アドレスを使っており、2人目の参加前に離脱しやすい。またホーム上に未招待オーナー向けの導線バナーがない。

### (6) ストア公開準備
- `docs/app-store/metadata.ja.json`、`review-notes.ja.md`、`subscription-terms.ja.md`、`app-privacy.md` は Apple の審査要件に沿って極めて丁寧に書かれている。
- ただし、reference app を含む人気アプリが実利用価値や主要ベネフィットを強調した**ストア用スクリーンショット見出し原稿**（`screenshots.ja.md` 等）がリポジトリに存在せず、`ScreenshotTests.swift` は素のシミュレータ画面を撮るのみ。また `project.yml` には `AppIcon` アセット、`LEDGER_LEGAL_BASE_URL`、本番 Bundle ID / CloudKit コンテナが未反映で、サポート URL も未確定（`docs/release-checklist-detail.md:19`）。

### (7) アクセシビリティ
- **良い点**: `Home.settlementHeader`（`FutariKakeiboApp.swift:179`）と `YenRow`（`683`）の `typeSize.isAccessibilitySize` 対応、`monospacedDigit()`、精算文と支払者読み上げの `.accessibilityElement(children: .combine)`、`BudgetProgressRow.tone`（`ProSettings.swift:139-141`：白地に対する `#A61B29` は理論コントラスト比約 7.5:1、暗色背景に対する `#FF929B` も約 8.0:1 で高い視認性 — ただし実描画の最終確認は `推測`）。
- **課題**:
  1. `ProLock`（`ProSettings.swift:19`）と `PaidBookTools` 導線（`BookSettings.swift:45`）が `Label(..., systemImage: "lock")` を使っており、SwiftUI の `Label` は装飾アイコンを読み上げないため、**VoiceOver 利用者に「有料機能でロック中」と伝わらない**。
  2. `BudgetProgressRow`（`ProSettings.swift:146`）が金額に「予算」を付けず読み上げるため、予算額と超過額の 2 つの金額の区別がつきにくい。
  3. `MonthDetail`（`FutariKakeiboApp.swift:330-336`）と `SpendingCharts`（`PaidBookTools.swift:124-130`）の月送り `HStack` が最大文字サイズ時に縦積みへ切り替わらず折返し崩れの恐れがある（`推測`）。
  4. `.systemSmall` ウィジェット（`LedgerWidget.swift:47-70`）は 5 行表示＋ `minimumScaleFactor(0.5)` のため、文字拡大時に文字が極小化・省略される恐れがある（`推測`）。
  5. `LedgerTheme.green`（`PaidBookTools.swift:26`）が `.tint(.teal)` を指定しており、ライトモードで `.borderedProminent` ボタン（`FutariKakeiboApp.swift:258`）の白文字と低コントラストになる恐れがある（`推測`）。

---

## 3. オーナーのこれまでの仮説に対する独立検証（使われ・勧められるか軸）

| オーナーの初期仮説 | 市場・利用者の観点からの検証結果 | 結論・推奨 |
| --- | --- | --- |
| **仮説 A: ホームは「支出総額」より「精算額（相手に/相手から）」を最上段にすべき** | 月末に割り勘を締めるカップルには刺さるが、月の大半（1〜29日）や招待前の単独利用時は「今月いくら使ったか／予算あと幾らか」の方が毎日見る動機になる。また「相手から ¥…」だけでは使いすぎ抑制の行動に繋がりにくい。 | **部分採用で修正**。最上段の精算額は維持しつつ、直下にカテゴリ別の支出可視化（円グラフ等）と月の予算残額サマリを置き、毎日開く価値を補う。 |
| **仮説 B: 極端なミニマリズム（ホームにグラフ無し・便利機能は `person.2` の奥に格納）** | 初期画面は静かだが（推測）、2日目に開く理由（予算残額・買い物リスト・支出内訳）が2〜3階層奥に隠れ、「ただの割り勘メモ帳」と見なされて定着・口コミが起きにくい。reference app はホーム円グラフと予算タブを第1階層に置いている。 | **見直し推奨**。少なくとも「ホーム」「予算（または明細・分析）」「共有/設定」が1タップで見渡せる導線へ整理し、機能の価値を隠さない。 |
| **仮説 C: 予算・グラフ・ウィジェット・カスタム費目まで一括で Pro 課金にすべき** | 無料でできるのが「記録＋精算＋iCloud共有」だけだと、無料ユーザーの2〜7日目の継続フック（ウィジェット・予算確認）がなく、習慣化する前に離脱して Paywall に辿り着かない。reference app は基本の予算・グラフを無料で体験させている。 | **一部開放を推奨**。無料のウィジェット（今月の支出/精算表示）と基本予算（例：合計または1〜2費目体験）を無料枠に入れ、「複数家計簿・全費目予算・定期入力・CSV・広告なし相当の便利機能」で Pro 転換を狙う方が売上に効く。 |
| **仮説 D: Apple Account メール指定の厳格な 1 対 1 招待で安全性を担保する** | 不正参加を防げる設計は堅実だが、日本のカップルはパートナーの Apple ID 用メールアドレスを知らないケースが多く、招待前の最大の離脱壁になる。 | **摩擦低減が必要**。メールアドレス検索の前提説明＋1アクション共有導線、あるいは一般的な共有シートでの招待追加を検討すべき。 |
| **仮説 E: 480円/月・4,800円/年（14日無料）・7,800円買い切り** | カップル2人で実質半額（1人あたり月240円相当）になる点は日本の家計簿市場でも競争力がある。買い切りオプションもサブスク疲れ層に好まれる。ただし現在の Paywall ではその安さ（2人分で1人分の価格）が伝わっていない。 | **価格帯は妥当・訴求を修正**。正式価格の確定と同時に「1人の購入でふたりとも利用可能・年額は月400円相当」を前面に出す。 |

---

## 4. reference app に負けている点の改善案（売上インパクト順）

### 改善 1（売上インパクト最優先）: 支出の編集・削除機能の実装
- **該当箇所**: `Sources/FutariKakeibo/ExpenseDetail.swift:21-46`, `Sources/FutariKakeibo/CloudLedger.swift:1079-1086`, `Sources/FutariKakeibo/FutariKakeiboApp.swift:388-405`, `Sources/FutariKakeibo/FutariKakeiboApp.swift:497-585`
- **問題**: 一度保存した支出の金額・費目・支払者・日付・分け方を修正することも、誤入力を削除することもできない。実利用初日に「金額を間違えたが消せない」で低評価・アンインストールに直結する。
- **変更内容**:
  1. `CloudLedger` に `update(_ expense: Expense, in book: Book)` および `delete(_ expenseID: UUID, from book: Book)` を追加する（精算済み月の保護 `BookError.settled` と共有ゲストの更新/削除権限 `canUpdateRecord` / `canDeleteRecord`、添付レシート行の同時削除を含む）。
  2. `EntryForm` が既存 `Expense` を受け取る編集モードに対応し、`ExpenseDetail` のツールバーに「編集」ボタンと一覧末尾に「この支出を削除」（確認ダイアログ付き）を追加する。`MonthDetail` の一覧にもスワイプ削除を付ける。
- **機械検証できる合格条件**:
  - Node 純粋関数テスト（`checks/shared-book.test.mjs` 等）で、支出の編集・削除後に同一 `id` の重複が残らず、`monthlyTotals` と `settlement` が正しく再計算され、精算済み月の編集・削除が拒否されること。
  - Node ソースチェックで `Sources/FutariKakeibo/ExpenseDetail.swift` に編集導線と削除確認（`.confirmationDialog` または `.alert`）、`Sources/FutariKakeibo/CloudLedger.swift` に更新・削除メソッドが存在すること。

### 改善 2: 予算行への「支払済」表示・割合定義の統一・空家計簿での予算設定解禁・前月引継ぎ
- **該当箇所**: `Sources/FutariDomain/Ledger.swift:142-164`, `Sources/FutariKakeibo/ProSettings.swift:68-71`, `Sources/FutariKakeibo/ProSettings.swift:133-164`, `Sources/FutariKakeibo/CloudLedger.swift:808-812`
- **問題**: reference app の予算タブ（`合計 218,000円 17% 残り 37,756円`、`食費 今月 40,000円 -103% 超過 41,098円 | 支払済 81,098円`）に対し、本アプリは「支払済」が表示されず、予算内は使用率・超過時はマイナス超過率と基準が混在し、さらに支出 0 件時は `ProSettings.swift:68-71` が `FirstExpensePrompt` で予算設定自体をブロックする。月ごとの予算引継ぎもない。
- **変更内容**:
  1. `BudgetProgress`（`Ledger.swift:142-149`）に `spent: Int` を持たせ、`BudgetProgressRow`（`ProSettings.swift:145-160`）に `"予算 \(progress.limit.yen)"` と `"支払済 \(progress.spent.yen)"` を表示する。
  2. `displayPercentage` の意味を統一し、予算内は「残り割合（例：`残り 17%`）」または明示ラベル付き表記にし、超過時は赤系色・残額時は区別できるポジティブ色で色分けする（コントラスト検証必須・`推測`）。
  3. `BudgetSettings`（`ProSettings.swift:68-71`）の `snapshot.expenses.isEmpty` 分岐を外し、支出 0 件でも予算を設定可能にする。`limits.isEmpty` かつ前月に予算がある場合は「前月の予算を引き継ぐ」ボタンを出す。
- **機械検証できる合格条件**:
  - `checks/pro-ledger.test.mjs` の純粋関数テストで、`budgetProgress(limit: 218000, spent: 180244)` が `spent: 180244`, `remaining: 37756`, 残り割合 `17`（または明示定義値）を返し、`budgetProgress(limit: 40000, spent: 81098)` が `spent: 81098`, `overspend: 41098`, `displayPercentage: -103` を返すこと。
  - Node ソースチェックで `ProSettings.swift` に `支払済` が含まれ、`expenses.isEmpty` で `budgetRows` を遮断していないこと。

### 改善 3: ホーム画面の視認性・即時フィードバック強化（精算文言の明確化・費目円グラフ・自分の初回支出表示）
- **該当箇所**: `Sources/FutariKakeibo/FutariKakeiboApp.swift:104-145`, `Sources/FutariKakeibo/FutariKakeiboApp.swift:219-231`
- **問題**: ホームの `"相手から 3,110円"` は受け取るのか払われたのか一読で曖昧。さらに reference app の主役である「カテゴリ別の支出内訳（円グラフ＋支出合計）」がなく、自分が最初に記録した支出すらホームに出ず、相手の支出行（`138-141`）も費目名・メモが欠落している。
- **変更内容**:
  1. `settlementTitle`（`227-228`）を `"\(names[payment.from])から \(payment.amount.yen) 受け取る"` / `"\(names[payment.to])へ \(payment.amount.yen) 支払う"` 等の動詞付き文言にする（`payment.from == member` で判定）。
  2. ホームに `Charts` の `SectorMark` を用いたコンパクトな当月費目別内訳（中央に `支出合計`、上位費目を表示）を追加する（レイアウトは実画面確認まで `推測`）。
  3. ホーム末尾の最近行（`131-145`）は、相手の支出がない単独状態では自分の最新支出も表示し、必ず `expense.label ?? snapshot.title(for: expense.category)` を含めて表示する。
- **機械検証できる合格条件**:
  - Node ソースチェックで `FutariKakeiboApp.swift` の `settlementTitle` が「受け取る」「支払う」を含み、ホームの最近支出表示に `expense.label ?? snapshot.title(for: expense.category)` が含まれ、`SectorMark`（または費目集計表示）が `Ledger.totals` に接続されていること。

### 改善 4: 2〜7日目の継続フックと招待摩擦の低減（無料ウィジェット開放・通知時刻選択・ホーム招待導線）
- **該当箇所**: `Sources/FutariKakeibo/WidgetPublishing.swift:10`, `Sources/FutariWidget/LedgerWidget.swift:48-56, 82`, `Sources/FutariKakeibo/BookSettings.swift:140, 173, 199-216`, `Sources/FutariKakeibo/FutariKakeiboApp.swift:78-160`
- **問題**: ウィジェットが無料時に「有料プランで使う」しか出ず継続フックにならない。記録通知が20時固定で奥に隠れており、招待も相手の Apple ID メール手入力が必須。ホームに「パートナーを招待」の導線もない。
- **変更内容**:
  1. 無料ユーザーでもウィジェットに「今月の支出合計（または精算額）」を表示し、タップで入力画面を開く `widgetURL` を付ける（予算残額のみ Pro 限定とする）。
  2. `RecordingReminder`（`BookSettings.swift:125-184`）で通知時刻を `DatePicker(..., displayedComponents: .hourAndMinute)` で変更可能にする。
  3. ホーム上で未共有かつ支出 1 件以上のオーナーに「パートナーを招待」導線を表示し、`InvitePartner`（`BookSettings.swift:187-234`）のリンク作成〜共有シート起動の 2 段階操作を整理して Apple Account メールが必要な理由を明示する（可能なら `UICloudSharingController` による柔軟な共有導線を併設）。
- **機械検証できる合格条件**:
  - Node ソースチェックで `WidgetPublishing.swift` が無料プランでも支出/精算サマリを書き出し、`LedgerWidget.swift` が `widgetURL` を持ち無料時に `"有料プランで使う"` のみの空表示にしないこと。
  - `BookSettings.swift` に通知時刻の選択状態（`hour` / `minute` または `Date`）があり、`FutariKakeiboApp.swift` に未共有オーナー向けの招待導線が存在すること。

### 改善 5: 初回起動時に CloudKit 初期取込完了を待たず即時記録可能にする
- **該当箇所**: `Sources/FutariKakeibo/CloudLedger.swift:128-133`, `Sources/FutariKakeibo/CloudLedger.swift:427-428`, `Sources/FutariKakeibo/CloudLedger.swift:479-485`
- **問題**: `mayCreatePrimary`（`131-133`）が iCloud サインイン時に private / shared 両ストアの初回 `.import` 完了まで primary book 作成を止めるため、初回起動・低速回線環境で `snapshot == nil` のまま「iCloudの家計簿を読み込んでいます」（`428`）で足止めされ、初回 1 分以内の保存目標を達成できないリスクがある。
- **変更内容**:
  初回起動時は即座に記録可能なローカル主家計簿（またはオフライン仮家計簿）を開きつつバックグラウンドで iCloud 取込を進め、取込完了後に既存の共有/記録済み家計簿が見つかった場合は既存の `mergeSoloEntries` / `preferredOwned` ロジック（`886-942`）で重複なく統合する。
- **機械検証できる合格条件**:
  - `checks/shared-book.test.mjs` の純粋関数テスト（`ownedBookPlan` 相当）で、「取込前の仮記録 → 取込後に既存の記録済み家計簿が出現」のケースで明細が失われず統合されること、および `CloudLedger.swift` が `mayCreatePrimary` 未完了時でも入力ブロックしない状態遷移を持つこと。

### 改善 6: Paywall の訴求強化（全 8 機能の可視化・1人分で2人訴求・動的無料体験 CTA）
- **該当箇所**: `Sources/FutariKakeibo/ProPaywall.swift:18-26`, `Sources/FutariKakeibo/ProPaywall.swift:45`, `Sources/FutariKakeibo/ProPaywall.swift:66-99`, `FutariKakeibo.storekit:6, 45, 72`
- **問題**: Paywall が Pro の 8 機能中 3 つしか見せず、「1人分の購入で共有家計簿のふたりとも使える」という最強の訴求も脚注に沈んでいる。年額の「14日間無料」がボタン文言に反映されず、StoreKit の導入オファー対象判定も行っていない。
- **変更内容**:
  1. 上部にワンライン価値訴求（例：「1人分の購入で、パートナーもそのまま使える」）を置き、全主要機能（追加家計簿・費目別予算・定期入力・買い物リスト・支出グラフ・CSV・ウィジェット・精算日通知）を簡潔に並べる。
  2. StoreKit の `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` を確認し、年額かつ対象者には年額行のバッジとボタン文言「14日間無料で始める」を表示、非対象者には「対象の方は」を付けず通常購入文言に切り替える。
  3. 公開ブランチ前に `FutariKakeibo.storekit` の「仮の値」と `ProPaywall.swift:86` の仮表示を正式価格へ差し替える。
- **機械検証できる合格条件**:
  - Node ソースチェックで `ProPaywall.swift` が全主要 Pro 機能名（予算・定期入力・買い物・グラフ・CSV・ウィジェット・通知）と 2 人利用の主訴求を含み、`isEligibleForIntroOffer` に応じた CTA 文言分岐を持つこと。

### 改善 7: ストア公開準備（スクリーンショット見出し原稿・AppIcon 組込・本番設定の確定）
- **該当箇所**: `docs/app-store/`（スクショ見出し原稿なし）, `Tests/FutariScreenshotTests/ScreenshotTests.swift:23-81`, `project.yml:15, 29-39, 77-78`, `docs/app-store/metadata.ja.json:3, 5`
- **問題**: 掲載文と審査メモは整っているが、App Store の CVR を左右する**スクリーンショット用の見出し・構成原稿**が存在せず、アイコン（`docs/icon/candidates/`）も `project.yml` に組み込まれていない。また本番 Bundle ID・CloudKit コンテナ・`LEDGER_LEGAL_BASE_URL`・サポート URL が未設定。
- **変更内容**:
  1. `docs/app-store/screenshots.ja.md` を新設し、6 枚のストア画像それぞれの見出し（15〜22文字以内）・サブコピー・対応する撮影画面を定義する（例：「1. ふたりの支出を入れるだけ、差額を自動計算」「2. 招待リンクで無料共有、相手の記録もすぐ届く」等。未到達の実績数値は書かない）。
  2. 選定したアイコンを `Assets.xcassets/AppIcon.appiconset` として `project.yml` に登録し、本番 Bundle ID / CloudKit コンテナ / `LEDGER_LEGAL_BASE_URL` / サポート URL を確定する。
- **機械検証できる合格条件**:
  - `checks/app-store-metadata.test.mjs` で `docs/app-store/screenshots.ja.md` が 5 枚以上の見出しを持ち、各見出し文字数上限以内・実装済み機能と矛盾しない・他社名を含まないことを検証し、`project.yml` に `AppIcon` リソース定義が含まれることをチェックすること。

### 改善 8: アクセシビリティ修正と精算内訳の提示（`ProLock` VoiceOver・月ヘッダ文字拡大・`.teal` コントラスト）
- **該当箇所**: `Sources/FutariKakeibo/ProSettings.swift:19, 146`, `Sources/FutariKakeibo/BookSettings.swift:45`, `Sources/FutariKakeibo/FutariKakeiboApp.swift:330-336, 448-457`, `Sources/FutariKakeibo/PaidBookTools.swift:26, 124-130`
- **問題**: `ProLock` の `Label(..., systemImage: "lock")` が VoiceOver にロック状態を伝えず、`BudgetProgressRow` も予算額にラベルがない。`MonthDetail` と `SpendingCharts` の月送り `HStack` は AX5 で窮屈になり得る（`推測`）。`.teal` テーマはライトモードの白文字ボタンでコントラスト不足の恐れがある（`推測`）。また `SettlementReview` に各メンバーの支払合計・負担合計の内訳がない。
- **変更内容**:
  1. `ProLock` と `BookSettings` の鍵付き項目に `.accessibilityValue("Pro機能・ロック中")` または `.accessibilityHint("ふたりの家計簿 Pro の案内を開きます")` を付与する。
  2. `BudgetProgressRow` に `.accessibilityLabel("\(title)の予算 \(progress.limit.yen)")` を付与する。
  3. `MonthDetail` / `SpendingCharts` の月送り行を `typeSize.isAccessibilitySize` 時に `VStack` へ切り替える。
  4. `LedgerTheme.green`（`PaidBookTools.swift:26`）を白文字と WCAG AA（4.5:1 以上）を満たす濃緑（例：`#174938`）へ変更する。
  5. `SettlementReview` に各メンバーの当月支払合計・負担額の内訳行を追加する。
- **機械検証できる合格条件**:
  - Node テストで、メンバー別支払合計・負担額の純粋関数が立替相殺と一致すること、および `PaidBookTools.swift` のカスタムテーマ色の白文字に対する相対輝度コントラスト比が 4.5:1 以上であることを計算検証すること。
  - Node ソースチェックで `ProSettings.swift` の `ProLock` にアクセシビリティ属性があり、`MonthDetail` の月送り行に `isAccessibilitySize` 分岐があること。

## 対応

| 改善 | 対応 |
| --- | --- |
| 1. 支出の編集・削除 | **直した**（`Sources/FutariKakeibo/ExpenseDetail.swift:54`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:479`、`Sources/FutariKakeibo/CloudLedger.swift:1130`、`Sources/FutariKakeibo/CloudLedger.swift:1154`）。精算済みの月を保護し、支出の削除時に写真も削除する。検証は `checks/pro-ledger.test.mjs:72`。 |
| 2. 予算 | **直した**（`Sources/FutariDomain/Ledger.swift:153`、`Sources/FutariKakeibo/ProSettings.swift:56`、`Sources/FutariKakeibo/ProSettings.swift:127`、`Sources/FutariKakeibo/CloudLedger.swift:819`）。支払済額と残り割合を表示し、支出ゼロでも設定できる。未設定の月は前月の予算を引き継げる。検証は `checks/pro-ledger.test.mjs:405` と `checks/pro-ledger.test.mjs:433`。 |
| 3. ホーム | **直した**（`Sources/FutariKakeibo/FutariKakeiboApp.swift:183`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:232`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:248`）。精算の方向を動詞で示し、自分だけの支出も表示する。支出合計を開くと費目別の金額を金額順で表示し、円グラフも確認できる。マイナスの費目がある月やアクセシビリティ文字サイズでは一覧で表示する。検証は `checks/pro-ledger.test.mjs:382`。 |
| 4. ウィジェット・通知・招待 | **次回**。無料時の表示と入力画面への遷移、通知時刻、招待導線をまとめて扱う。 |
| 5. 初回取込中の記録 | **見送り**（取込前の仮記録から既存の個人・共有家計簿へ移す際のデータ保全を、複数のiCloudアカウントと端末で確認する必要がある。WindowsのNodeチェックで確認できるのは統合規則まで）。 |
| 6. 購入画面 | **次回**。正式価格は未確定。無料体験の表示はStoreKitで対象資格を確かめる。 |
| 7. ストア公開準備 | **見送り**（本番の識別子・URLと採用アイコンが未確定。アセットの組込とストア画像の撮影にはXcodeが必要）。 |
| 8. アクセシビリティ・精算内訳 | **次回**。VoiceOverと最大文字サイズはiOSで確認する。 |

WindowsでNodeの純粋関数テストとソースチェックを実施。iOSビルド、実画面、CloudKitの実機同期は未確認。
