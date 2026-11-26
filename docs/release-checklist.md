# ふたりの家計簿 1.0.0 提出チェックリスト

- [ ] **契約**　Apple Developer Program に加入し、App Store Connect で有料アプリ契約・税務・口座情報を登録する。[Apple Developer](https://developer.apple.com/account/) · [契約・税務・口座](https://appstoreconnect.apple.com/business)
- [ ] **署名・iCloud**　アプリとウィジェットの App ID、App Group、CloudKit コンテナを登録する。署名チームを選び、CloudKit のスキーマを本番へデプロイする。[識別子](https://developer.apple.com/account/resources/identifiers/list) · [CloudKit Console](https://icloud.developer.apple.com/dashboard/)
- [ ] **商品と価格**　下表の3商品を登録し、日本の正式価格を決める。年額に2週間の無料体験を設定し、各商品のファミリー共有を有効にする。[App Store Connect](https://appstoreconnect.apple.com/apps)
- [ ] **公開情報**　公開リポジトリで GitHub Pages を有効にする。法務 URL・問い合わせ先を確定し、App のプライバシー回答と掲載情報を登録する。[Pages の設定手順](https://docs.github.com/ja/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site) · [App Store Connect](https://appstoreconnect.apple.com/apps)
- [ ] **審査提出**　アイコンを選び、署名済みビルドの実機確認後に、初回ビルドと3商品をまとめて審査へ提出する。[TestFlight](https://developer.apple.com/testflight/) · [App Store Connect](https://appstoreconnect.apple.com/apps)

| 商品 | 商品 ID | 日本の価格候補 |
| --- | --- | --- |
| 月額・自動更新 | `local.futarikakeibo.pro.monthly` | 480円（仮） |
| 年額・自動更新 | `local.futarikakeibo.pro.yearly` | 4,800円（仮） |
| 買い切り・非消耗型 | `local.futarikakeibo.pro.lifetime` | 7,800円（仮） |

価格候補はローカル StoreKit 設定と同じです。正式な価格は App Store Connect で選べる価格ポイントから決めてください。

[登録値・公開 URL・提出前の確認手順](release-checklist-detail.md)
