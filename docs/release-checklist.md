# ふたりの家計簿 1.0.0 提出チェックリスト

- [ ] **契約**　Apple Developer Program に加入し、App Store Connect で有料アプリ契約・税務・口座情報を登録する。[Apple Developer](https://developer.apple.com/account/) · [契約・税務・口座](https://appstoreconnect.apple.com/business)
- [ ] **署名・iCloud**　アプリとウィジェットの App ID、App Group、CloudKit コンテナを登録する。署名チームを選び、CloudKit のスキーマを本番へデプロイする。[識別子](https://developer.apple.com/account/resources/identifiers/list) · [CloudKit Console](https://icloud.developer.apple.com/dashboard/)
- [ ] **商品と価格**　下表の2商品を日本の価格で登録する。年額に2週間の無料体験を設定し、各商品のファミリー共有を有効にする。[App Store Connect](https://appstoreconnect.apple.com/apps)
- [ ] **公開情報**　公開リポジトリで GitHub Pages を有効にする。法務 URL・問い合わせ先を確定し、App のプライバシー回答と掲載情報を登録する。[Pages の設定手順](https://docs.github.com/ja/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site) · [App Store Connect](https://appstoreconnect.apple.com/apps)
- [ ] **審査提出**　アイコンを選び、署名済みビルドの実機確認後に、初回ビルドと2商品をまとめて審査へ提出する。[TestFlight](https://developer.apple.com/testflight/) · [App Store Connect](https://appstoreconnect.apple.com/apps)

| 商品 | 商品 ID | 日本の価格 |
| --- | --- | --- |
| 月額・自動更新 | `local.futarikakeibo.pro.monthly` | 480円 |
| 年額・自動更新 | `local.futarikakeibo.pro.yearly` | 3,600円 |

2026年11月27日確定。1契約で共有家計簿のふたりとも Pro を利用できます。年額は月額12か月分の5,760円に比べて約37%お得です。ローカルの価格は `FutariKakeibo.storekit` で設定します。

[登録値・公開 URL・提出前の確認手順](release-checklist-detail.md)
