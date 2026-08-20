# tunaneko

macOS 向けのシンプル & 高機能 **OpenConnect GUI クライアント**。Karing の OpenConnect 版。

## 機能

- **OpenConnect コア同梱** — Homebrew 不要。ダウンロードしてすぐ使えます
- **遅延測定つきサーバー一覧** — 全サーバー一括測定 (TCP:443)、遅延順ソート、「自動選択」で最速サーバーに接続
- **自動リトライ** — 失敗時に次に速いサーバーへ自動で試行 (最大5回)
- **キルスイッチ** — VPN が予期せず切れたら全通信を遮断 (pf ファイアウォール)。解除はアプリ/メニューバーからワンクリック
- **サーバーごとの認証情報** — サーバー単位でユーザー名/パスワードを上書き可能。デフォルト認証情報の共用も可
- **証明書ピン留め** — 初回接続時に自動で証明書を保存。2回目以降プロンプトなし
- **インポート / エクスポート** — JSON 形式、または `名前 ホスト [プロトコル]` のテキスト形式
- **メニューバー常駐** — ウィンドウを開かずに接続/切断
- **多言語** — 日本語 / English (システム言語に追従。`Resources/*.lproj` で追加可能)

## 動作環境

- Apple Silicon Mac、macOS 14 以降
- OpenConnect 互換の VPN (AnyConnect / GlobalProtect / Pulse など)

## インストール (ビルド済み)

1. DMG から `tunaneko.app` を `/Applications` へドラッグ
2. アドホック署名のため、一度だけ quarantine を解除:
   ```bash
   xattr -cr /Applications/tunaneko.app
   ```
3. tunaneko を起動 → 設定タブ → **セットアップ…** (sudoers 設定、管理者パスワードが1回だけ必要)
4. 設定タブ (またはホームの鉛筆アイコン) で VPN の認証情報を入力
5. ホームの接続ボタン、またはメニューバーアイコンから接続

## ソースからビルド

Xcode Command Line Tools と、コアビルド用に `pkg-config` / `gnutls` (Homebrew) が必要:

```bash
git clone <repo>
cd tunaneko
make dist    # コアのソースビルド + SwiftUI アプリ + アドホック署名
open dist/tunaneko.app
```

## キルスイッチの仕組み

有効時、同梱の `vpnc-script` が接続時に pf アンカー (`com.tunaneko`) をロードし、ループバック・トンネル (utun)・VPN ゲートウェイ・DHCP 以外を全遮断します。トンネルが不意に切れてもルールが残るため通信は遮断され続けます。解除はホームのボタン、メニューバー、または:

```bash
sudo pfctl -a com.tunaneko -F all
```

## プライバシーとセキュリティ

- パスワードは `~/Library/Application Support/tunaneko/credentials.json` に `0600` で保存 (アドホック署名では Keychain がビルドごとにプロンプトを出すためファイル方式を採用)
- セットアップで追加される sudoers ルール (`/etc/sudoers.d/tunaneko`):
  - 同梱 `openconnect` の NOPASSWD (`SETENV` 付き)
  - `/sbin/pfctl` (キルスイッチ用)
  - `/bin/kill -INT *` (root 所有コアの正常切断用)

## ライセンス

MIT (アプリ本体)。同梱物: OpenConnect (LGPLv2.1)、vpnc-script (GPLv2+) — [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 参照。
