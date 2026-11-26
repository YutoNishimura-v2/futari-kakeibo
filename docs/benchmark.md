# reference app 比較 第4回

| 項目 | 判定 | 根拠 |
| --- | --- | --- |
| ホーム | 対応済み | 最上段に精算額と月選択。精算計算は既存。 `FutariKakeiboApp.swift:78`、`FutariKakeiboApp.swift:178`、`Ledger.swift:175` |
| 予算 | 対応済み | 月の予算合計を先頭に、設定済み費目の残額・割合・バー・超過額を表示。 `ProSettings.swift:86`、`ProSettings.swift:133`、`Ledger.swift:152` |
| 空の家計簿 | 対応済み | ホームと予算に案内1文と「支出を記録」。 `FutariKakeiboApp.swift:80`、`FutariKakeiboApp.swift:234`、`ProSettings.swift:68` |
| 精算済み | 対応済み | 既存の精算保存を使い、ホームに「精算済み」と記録日を表示。 `CloudLedger.swift:637`、`CloudLedger.swift:1123`、`FutariKakeiboApp.swift:191` |

超過時の負の割合は予算に対する超過分です。予算がゼロで支出がある場合は超過額と「割合なし」を表示します。旧形式から移行した精算の記録日は移行日です。
