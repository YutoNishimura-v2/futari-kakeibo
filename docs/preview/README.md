# 画面プレビュー（推測・HTML 近似）

このディレクトリの画像は、Windows 上の静的 HTML（`tools/preview/*.html`）をローカルのヘッドレス Chromium で幅 390px（390x844 ビューポート）に描画した **推測**（近似プレビュー）です。iOS シミュレータや実機での SwiftUI レンダリングではありません。

- `home-390.png`: ホーム画面（デモデータ: はる／あおい、2026年6月）
- `budget-390.png`: 費目別予算画面（デモデータ: 食料品 18,000円、外食 4,000円）
- `paywall-390.png`: Pro 購入画面（月額480円・年額3,600円、ふたりで1契約）

## 再生成コマンド

追加のパッケージインストールや外部通信なしで、PC 上の Chrome / Edge を使って再生成できます。

```powershell
node tools/preview/render.mjs
```
