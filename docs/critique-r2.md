# ふたりの家計簿・初回体験の比較

初回は支出の記録と今月の合計を優先する。招待で止まった場合は次の操作を示し、精算と Pro はそれぞれ支払いの判断に必要な情報を先に出す。

- **OsidOri** は個人と共有の家計管理、分担の可視化、予算管理を訴求している。日本のファイナンス部門トップセールス14位、評価約1.1万件。[日本の App Store](https://apps.apple.com/jp/app/id1473751623)
- **シェアルー（Shareroo）** は明細の手入力から共有や立替の精算までを案内し、無料で始められることも示している。同17位、評価約1.5万件。[日本の App Store](https://apps.apple.com/jp/app/id1475406336)

2026年11月26日の日本向け公開掲載と SwiftUI ソースを比較した。順位は取得時点の値。影響は利用者の行動を想定した評価で、各社のアプリ内操作、初回の所要時間、実測の離脱率は未確認。[Apple のファイナンス部門トップセールス](https://itunes.apple.com/jp/rss/topgrossingapplications/limit=100/genre=6015/xml)

| 優先 | 比較と修正前の差 | インストール後・購入への影響 | 修正と根拠 |
| --- | --- | --- | --- |
| 1 | OsidOri は個人で家計を管理する価値を示す。こちらは招待前に入力できるが、空の家計簿で利用者にそのことが伝わらなかった。 | 相手の準備待ちだと思い、最初の1件を保存する前に閉じる。 | 空の持ち主の家計簿では、記録ボタンのそばに一人で始められると表示。持ち主への入力権限は既存の仕組みを利用。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:111`、`Sources/FutariKakeibo/CloudLedger.swift:719`、`Sources/FutariKakeibo/BookRepository.swift:52` |
| 2 | シェアルーは支出の見える化を精算と並べて訴求する。こちらはホームに精算額を出していたため、記録した支出額をひと目で確認できなかった。 | 1件保存しても支出合計が見えず、記録が反映された実感が弱い。 | ホームカードは返金を差し引いた当月の支出合計を1つ表示。精算額はタップ先の月明細で確認できる。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:94`、`Sources/FutariDomain/Ledger.swift:165` |
| 3 | シェアルーは二人で記録できる点を前面に出す。こちらは iCloud のサインアウトと古いリンクへの案内が散在し、権限エラーも期限切れと同じ扱いだった。各社のエラー画面は掲載から確認できない。 | 招待相手が次の手を選べず、二人目の参加が止まる。権限の問題でリンクだけ送り直すと失敗を繰り返し得る。 | 作成と承諾で日本語の説明・次の操作を共通化。サインイン、再招待の依頼、メールアドレス・国や地域の確認を案内。 `Sources/FutariKakeibo/CloudLedger.swift:7`、`Sources/FutariKakeibo/CloudLedger.swift:1275`、`Sources/FutariKakeibo/BookSettings.swift:153`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:76` |
| 4 | シェアルーは支払う人と受け取る人、送金額の自動計算を訴求する。こちらにも送金方向の文はあったが、端数の説明は該当する明細があるときだけ表示し、固定額の説明も残りが1円のときだけ出ていた。 | 金額に1円の差があると、理由を確認できず精算を保留する。 | 送金指示は金額まで一文で表示。精算確認画面で端数の扱いを開ける。折半・比率は明細ごとに支払った人が端数の1円を負担し、返金は受け取った人に配分する既存の整数計算を検証。固定額では指定した人以外が残額を負担する。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:173`、`Sources/FutariKakeibo/FutariKakeiboApp.swift:341`、`Sources/FutariDomain/Ledger.swift:49`、`checks/ledger.test.mjs:41` |
| 5 | OsidOri は予算管理や固定費に触れ、シェアルーは家計簿の使い分けと基本無料を訴求する。こちらの Pro 画面では、追加の家計簿と無料で使える共有・同期の範囲が見えなかった。 | 価格を見ても自分に必要な機能か判断できず、無料の共有まで購入が必要だと受け取られ得る。 | 追加の家計簿、費目別予算と残額、定期入力の使い道を価格より先に表示。iCloud の共有と同期は無料と明示。 `Sources/FutariKakeibo/ProPaywall.swift:17` |

## 第2回の対応状況

| 優先 | 状況 | チェック |
| --- | --- | --- |
| 1 | 修正済み | `an empty owner ledger offers recording before the partner is invited` |
| 2 | 修正済み | `the home card shows net spending for the current Japan month` |
| 3 | 修正済み | `invite failures select distinct Japanese recovery steps in both invite flows` |
| 4 | 修正済み | `settlement, empty states and accessibility text are wired into the Swift views`、`Swift rounds the nonpayer share down per entry before netting expenses and refunds`、`fixed amount assigns the remainder to the second member` |
| 5 | 修正済み | `the paywall explains the three Pro benefits and free sharing before plans or purchase` |

## round 2b

OsidOri とシェアルーの日本向け App Store 掲載を読み直し、インストール前の説明から記録・招待・精算・購入画面まで、掲載で確認できる訴求とこちらのソースを突き合わせた。[OsidOri](https://apps.apple.com/jp/app/id1473751623) ・ [シェアルー](https://apps.apple.com/jp/app/id1475406336)

| 場面 | 比較で見つかった差と修正 | 状況とチェック |
| --- | --- | --- |
| インストール | OsidOri は個人でも使えること、シェアルーは基本無料を掲載に明示している。こちらの掲載案では招待前に使えるか、共有と同期に料金がかかるかを判断しにくかった。両方を Pro の説明より前に記載した。 `docs/app-store/metadata.ja.json:5` | 修正済み。 `the listing explains solo entry and free iCloud sharing before Pro` |
| 最初の記録 | シェアルーは簡単な入力と折半・割合・金額指定の両方を訴求する。こちらの入力フォームは分け方を閉じたままだと、保存時に折半が適用されると分からなかった。設定を開かなくても現在の分け方を見えるようにした。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:427` | 修正済み。 `the collapsed entry details show the active split mode` |
| 招待への入口 | 両社は二人でつける家計簿を掲載の前半で紹介する。こちらは「ふたりと共有」を開いても招待より先に定期入力や便利機能が並び、無料の共有を見つけにくかった。招待・共有の管理をフォームの先頭に置いた。 `Sources/FutariKakeibo/BookSettings.swift:17` | 修正済み。 `the settings offer free sharing before Pro controls` |
| 招待リンクの送信 | シェアルーは参加後に誰の記録もすぐ共有されると説明している。こちらのリンク生成後の説明は相手の承諾だけに触れ、リンク生成と送信が別の操作だと分かりにくかった。送信が必要と結果画面に明記した。 `Sources/FutariKakeibo/BookSettings.swift:141` | 修正済み。 `a generated invitation tells the owner to send the link` |
| 精算 | シェアルーは送金額の自動計算と簡単な精算を訴求する。こちらは過去月も精算できる一方、確認画面を開くと対象月が消えていた。送金額の上に更新対象と同じ年月を表示した。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:338` | 修正済み。 `settlement review identifies the same month it updates` |
| 購入画面 | 両社の App Store 掲載にはアプリ内購入の欄があり、購入の判断に料金を使える。こちらは料金の取得エラーが再試行ボタンから離れており、再取得に成功してもエラー表示が残った。料金欄で再試行の隣に取得エラーを表示し、次の取得開始時に消すようにした。 `Sources/FutariKakeibo/ProPaywall.swift:31`、`Sources/FutariKakeibo/ProPaywall.swift:101` | 修正済み。 `price lookup failures appear by retry and clear on a new lookup` |

## round 3

2〜7日目に二人で使う場面を、日本向け掲載の共有・記録・精算の説明と照らし合わせた。アプリ内の手順や通知の仕様は掲載から分かる範囲で扱った。[OsidOri](https://apps.apple.com/jp/app/id1473751623) ・ [シェアルー](https://apps.apple.com/jp/app/id1475406336)

| 場面 | 比較で見つかった差と修正 | Nodeチェック |
| --- | --- | --- |
| 招待された人の初回 | 両社とも二人で記録できる点を前面に出す。こちらは招待先で支出が既に見えていても、自分の支払いを追加すると二人に共有されると分かりにくかった。書き込み可能なゲストで、自分が支払った明細がまだなければ記録ボタンの下に案内を出す。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:136` | `a writable guest sees how their first payment is shared even in a populated ledger` |
| 記録を思い出す | シェアルーは手入力の手軽さを訴求する。こちらは記録するきっかけがアプリを開くまでなかった。共有設定に、端末ごとに毎日20時の通知をオン・オフできる行を追加した。オン操作でOSの許可を求める。 `Sources/FutariKakeibo/BookSettings.swift:32`、`Sources/FutariKakeibo/BookSettings.swift:161` | `free settings offer an opt-in local recording reminder and can cancel it` |
| 相手の記録を見る | シェアルーは参加後に明細が共有されること、OsidOriは二人の分担が分かることを訴求する。こちらはホームの合計が変わっても相手の支払いを見分けにくかった。今月の相手の支払い・返金を日付順の先頭から1件表示し、タップで明細を開く。表示する人物は支払者・受取者。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:142`、`Sources/FutariKakeibo/CloudLedger.swift:234` | `home links the other member’s latest dated payment or refund to its synced expense` |
| 月をまたいで精算する | シェアルーは立替分の精算を訴求する。こちらのホームは月が変わると今月に切り替わり、前月分を確認するには月の切り替えが必要だった。先月に記録があり、まだ精算していない場合はホームから先月の明細と精算額を開ける。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:111` | `home links to the previous month while its recorded expenses are unsettled` |
| 立替が相殺された月を締める | シェアルーは送金額の自動計算を訴求する。こちらの精算確認では差額が0円でも支払い確認を求めていた。送金が不要な場合はその旨と、精算済みにすると月の記録が締まることを表示する。 `Sources/FutariKakeibo/FutariKakeiboApp.swift:382` | `zero-balance month can be closed with guidance that no transfer is needed` |

共有・同期と、今回追加した記録リマインダーは無料。明細の順序には支出日を使うため、同日の複数明細ではホームの1件が最後に入力された明細とは限らない。対象チェックは修正前41件中5件失敗、修正後41件成功、キャンセル0。iOSでの表示、通知配信、二人の端末間の反映は未確認。

## 確認範囲

追試した Node チェックは修正前に39件中6件が失敗し、修正後に39件すべてが成功した。Swift の表示と処理の接続はソース上で確認した。

- 確認は保留。初回のクラウド準備時間、アプリに渡る前に iOS が拒否するリンク、国や地域の異なるアカウントで返るエラーは、iOS と実際の iCloud アカウントが必要。CloudKit の公開エラーに地域不一致専用のコードがないため、アカウント確認や権限のエラーでは国や地域を確認項目として扱う。[CloudKit のエラーコード](https://developer.apple.com/documentation/cloudkit/ckerror/code)
- 確認は保留。画面の折り返し、操作領域、StoreKit の料金再取得は Xcode または iOS 端末での確認が必要。比較先のアプリ内操作、初回の所要時間、離脱率の評価には実際の操作と計測が必要。
