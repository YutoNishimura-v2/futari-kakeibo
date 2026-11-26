# App のプライバシー回答案

| App Store Connect の項目 | 回答案 |
| --- | --- |
| このアプリまたは第三者パートナーがデータを収集しますか | いいえ。公開表示は「データの収集なし」 |
| 収集データの種類・目的、ユーザーとの関連付け | 該当なし |
| トラッキング | なし。広告 ID やトラッキング用ドメインも使用しない |
| プライバシーポリシー URL | 公開した GitHub Pages の `/legal/privacy.html` の完全な HTTPS URL |
| プライバシーの選択肢 URL | 省略可。ポリシーに編集・削除、共有の終了と問い合わせ方法を記載 |

アプリは家計簿・写真・Pro の権利情報を端末に保存し、iCloud 有効時は CloudKit の利用者の非公開データベース、共有時は招待された相手がアクセスできる共有データベースに同期します。招待のメールアドレスは Apple に照会します。App Group のウィジェット表示用データは端末内のみです。決済を処理するのは Apple で、アプリには開発者へのデータ送信、解析 SDK、広告 SDK がありません。公開ビルドでも開発者や第三者パートナーが家計簿・招待・購入情報を自社サーバーなどで受け取らないことを前提とします。[Apple のデータ収集の定義](https://developer.apple.com/app-store/app-privacy-details/)

必須理由 API はアプリ自身の設定用 `CA92.1` と、アプリからウィジェットへ表示データを渡す App Group 用 `1C8F.1` です。ウィジェットは App Group 用の理由のみを宣言します。署名したアーカイブのプライバシーレポートで確認します。[必須理由 API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
