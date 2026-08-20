# tunaneko

A simple & powerful **OpenConnect GUI client** — like Karing, but for OpenConnect/AnyConnect VPNs.

| Platform | Directory | Tech | License |
|----------|-----------|------|---------|
| macOS | [`macos/`](macos/) | SwiftUI, bundled openconnect core (no Homebrew needed) | GPLv2+ |
| Android | [`android/`](android/) | Kotlin + Jetpack Compose, libopenconnect via JNI | MIT |

## Features

- Bundled OpenConnect 9.21 core — no external dependencies
- Server list with parallel latency measurement and fastest-first auto select
- Auto-retry on failure
- Kill switch (macOS: pf firewall; Android: system "Always-on VPN" guidance)
- Per-server or shared credentials
- TOFU certificate pinning with mismatch detection
- Server import/export (JSON / plain text)
- macOS: menu bar tray / Android: quick settings tile
- Localization: 日本語 / English / 中文 (live switch)

## Build

- **macOS**: `cd macos && make release` → `dist/release/*.dmg` (Xcode Command Line Tools + brew deps for the core build)
- **Android**: `cd android && scripts/build_core.sh arm64 && ./gradlew assembleRelease` (JDK 21 + Android SDK/NDK; no Android Studio needed)

See each platform's README for details: [macos/README.md](macos/README.md) / [android/README.ja.md](android/README.ja.md)

## Licenses

- **macOS app**: GPLv2+ — it bundles a modified vpnc-script (GPLv2+), so the distribution as a whole is GPL.
- **Android app**: MIT — libopenconnect is dynamically linked (LGPLv2.1).
- Bundled component: OpenConnect (LGPLv2.1) — see each platform's THIRD_PARTY_NOTICES.md.
