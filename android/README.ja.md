# tunaneko (Android)

Kotlin + Jetpack Compose 製の OpenConnect GUI クライアント。libopenconnect 9.21 を NDK ビルドして同梱 (root 不要)。

## 機能

- サーバー一覧 + 遅延測定 (TCP:443 並列) + 「自動選択」で最速接続
- 失敗時の自動リトライ (最大5回、認証失敗を除く)
- 証明書 TOFU ピン留め (不一致時は拒否)
- サーバー追加/削除 (確認付き)/インポート/エクスポート (JSON・テキスト)
- サーバーごと or 共通の認証情報 (EncryptedSharedPreferences)
- クイック設定タイル (タップ: 接続/切断、長押し: アプリを開く)
- 言語: 日本語 / English / 中文 (アプリ内即時切替)
- キルスイッチ相当: システムの「常時接続 VPN」+「VPN なしの接続をブロック」に誘導

## ビルド (Android Studio 不要)

```bash
brew install openjdk@21 autoconf automake libtool pkg-config gettext gpatch
brew install --cask android-commandlinetools
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;27.2.12479018"

scripts/build_core.sh arm64     # libopenconnect + 依存をクロスコンパイル
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
./gradlew assembleDebug         # app-debug.apk
```

- 署名付きリリース: `keystore.properties` (storeFile/storePassword/keyAlias/keyPassword) を置いて `./gradlew assembleRelease`
- x86_64 (エミュレータ) が必要なら `scripts/build_core.sh x86_64` を先に実行し、abiFilters に追加

## インストール

```bash
adb install app/build/outputs/apk/debug/app-debug.apk
```

初回: VPN 許可ダイアログ → OK。設定タブで認証情報を入力。

## ライセンス

MIT (アプリ本体)。libopenconnect は LGPLv2.1 (動的リンク、改変なし) — [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 参照。
