# ふたりの家計簿 提出時の登録値と確認手順

## 署名と CloudKit

1. [Apple Developer の Identifiers](https://developer.apple.com/account/resources/identifiers/list) で、同じチームにアプリ本体とウィジェットの明示的な App ID を登録します。ウィジェットのバンドル ID はアプリの ID に `.widget` を足します。両方の App ID に同じ App Group を紐づけます。本体には iCloud（CloudKit）と Push Notifications を有効にし、登録済みの CloudKit コンテナを紐づけます。
2. ビルド設定の `PRODUCT_BUNDLE_IDENTIFIER`（本体・ウィジェット）、`LEDGER_APP_GROUP`、`LEDGER_CLOUD_CONTAINER` を登録値に合わせます。公開用は `LEDGER_PLAN=free`、Release の push は `production` です。XcodeGen で生成したプロジェクトで両ターゲットの署名チームを選び、自動署名でビルドします。登録値とチーム識別子は設定に使えます。署名鍵・証明書の秘密鍵・アカウント情報を公開リポジトリに入れないでください。[Xcode の配布手順](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
3. 開発用の署名とテスト用 iCloud アカウントで Core Data の CloudKit スキーマを初期化します。現在のモデルを使う `CloudLedger.open()` で両ストアがロードされた直後に、開発用の一時ビルドで `try stack.initializeCloudKitSchema(options: [])` を実行できます。その一時コードを外し、開発環境で共有を確認してから [CloudKit Console](https://icloud.developer.apple.com/dashboard/) の開発環境で「Deploy Schema Changes」を実行します。TestFlight は本番環境を使うので、デプロイ後に改めて同期を確認します。[Apple のスキーマ配備手順](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)

## App Store Connect への登録

- アプリを日本語で新規登録し、署名済みビルドと同じバンドル ID を選びます。初回はアプリ・ウィジェットともバージョン `1.0.0`、ビルド `1` です。同じバージョンの再アップロード時は `CURRENT_PROJECT_VERSION` を増やします。アーカイブには Apple が提出時点で指定する Xcode と SDK を使います。[App Store Connect](https://appstoreconnect.apple.com/apps) · [提出要件](https://developer.apple.com/news/upcoming-requirements/)
- 月額と年額を同一の「ふたりの家計簿 Pro」購読グループの同じレベルに設定します。年額だけに対象者向け2週間の無料体験を登録します。商品 ID は[提出チェックリスト](release-checklist.md)のとおり入力し、日本の正式価格、提供地域、日本語の表示名・説明、審査用スクリーンショットを登録します。ファミリー共有は両商品で有効化します。有効化後は無効に戻せません。[Apple のサブスクリプション設定](https://developer.apple.com/app-store/subscriptions/)
- [掲載文面](app-store/metadata.ja.json)のアプリ名・サブタイトル・キーワード・説明を転記します。「このバージョンの最新情報」は欄が表示されるバージョンで使用します。説明末尾の Apple 標準使用許諾契約へのリンクを含めます。[プライバシー回答案](app-store/app-privacy.md)と[審査メモ](app-store/review-notes.ja.md)を転記し、年齢制限、輸出コンプライアンス、審査時の連絡先を入力します。[自動更新の表示原稿](app-store/subscription-terms.ja.md)

## 公開 URL

1. 公開リポジトリの「Settings」→「Pages」で、既定ブランチの `/docs` を公開元にします。「Visit site」でこのリポジトリのサイト URL を確認します。[GitHub Pages の設定手順](https://docs.github.com/ja/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
2. サイト URL に `/legal/privacy.html` と `/legal/terms.html` を付け、サインアウトした状態で日本語本文を開けることを確認します。`LEDGER_LEGAL_BASE_URL` にはサイト URL の後ろに `/legal` を付けた HTTPS URL を設定します。リポジトリ名を含む URL なら、その部分も含めます。
3. App Store Connect のプライバシーポリシー欄に公開済みの `privacy.html` の完全な URL を入力します。「サポート URL」には、利用者が開発者へ連絡できる公開ページを登録します。サポートページと連絡先は未確定です。法務ページの問い合わせ案内は App Store の「Appサポート」を参照しているので、登録した連絡先までたどれることを確認します。

## 提出前の確認

- [アイコン制作要件](app-store/icon-brief.md)に沿って選んだアイコンを AppIcon アセットに登録し、配布アーカイブの検証を通します。アプリの掲載用スクリーンショットと、購入画面を示す商品審査用スクリーンショットを用意します。[アイコンの指針](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- Xcode Organizer でアーカイブからプライバシーレポートを生成し、アプリとウィジェットのマニフェストが入り、申告と整合することを確認します。iPhone・iPad で起動画面を確認し、設定と購入画面の両方から利用規約とプライバシーポリシーを開きます。[プライバシーレポート](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)
- TestFlight の配布ビルドで、[審査メモ](app-store/review-notes.ja.md)の手順どおり別々の Apple Account で招待・相互同期、2商品の表示とサンドボックス購入、購入の復元を確認します。ウィジェットで App Group 経由の今月分の表示を確認します。初回のアプリ審査に2商品を添付して提出します。[Sandbox でのテスト](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)
