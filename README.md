# tunaneko

A simple & powerful **OpenConnect GUI client for macOS** — like Karing, but for OpenConnect/AnyConnect VPNs.

[日本語 README](README.ja.md)

## Features

- **Bundled OpenConnect core** — no Homebrew required at runtime. Download and run.
- **Server list with latency measurement** — measure all servers (TCP:443), sort by latency, "Auto" connects to the fastest.
- **Auto-retry** — on failure, automatically tries the next-fastest server (up to 5).
- **Kill switch** — blocks all traffic (pf firewall) if the VPN drops unexpectedly. One-click release from the app or the menu bar.
- **Per-server credentials** — each server can have its own username/password, or share the default credentials.
- **Certificate pinning** — server certificates are pinned automatically on first connect (no repeated prompts).
- **Import / Export** — server list as JSON, or plain-text `name host [protocol]` format.
- **Menu bar tray** — connect/disconnect without opening the window.
- **Multi-language** — English / 日本語 (follows system language; add more via `Resources/*.lproj`).

## Requirements

- Apple Silicon Mac, macOS 14 or newer
- An OpenConnect-compatible VPN (AnyConnect / GlobalProtect / Pulse / …)

## Install (prebuilt)

1. Open `tunaneko.app` from the DMG and drag it to `/Applications`.
2. The app is ad-hoc signed, so remove the quarantine flag once:
   ```bash
   xattr -cr /Applications/tunaneko.app
   ```
3. Launch tunaneko → Settings tab → **Set up…** (one-time sudoers rule, admin password required).
4. Enter your VPN credentials in Settings (or the pencil icon on Home).
5. Connect from the Home tab or the menu bar icon.

## Build from source

Requires Xcode Command Line Tools, plus `pkg-config` and `gnutls` (Homebrew) for the core build only:

```bash
git clone <repo>
cd tunaneko
make dist    # builds the core from source + the SwiftUI app + ad-hoc signs
open dist/tunaneko.app
```

- `make core` — build only the bundled openconnect core (downloads + verifies the pinned release tarball)
- `make build` — build only the Swift app
- `make release` — package `dist/release/tunaneko-<version>-macOS-arm64.dmg`

## How the kill switch works

When enabled, the bundled `vpnc-script` loads a `pf` anchor (`com.tunaneko`) at connect time that blocks everything except loopback, tunnel interfaces (utun), the VPN gateway itself, and DHCP. If the tunnel dies unexpectedly, the rules stay and traffic stays blocked. Release it from the Home tab button, the menu bar, or:

```bash
sudo pfctl -a com.tunaneko -F all
```

## Privacy & security notes

- Passwords are stored in `~/Library/Application Support/tunaneko/credentials.json` with `0600` permissions (file-based instead of Keychain, because ad-hoc-signed builds trigger a Keychain prompt on every rebuild).
- `sudoers` rules added by setup (see `/etc/sudoers.d/tunaneko`):
  - NOPASSWD for the bundled `openconnect` binary (with `SETENV`)
  - NOPASSWD for `/sbin/pfctl` (kill switch)
  - NOPASSWD for `/bin/kill -INT *` (graceful disconnect of the root-owned core)

## License

MIT (app). Bundled components: OpenConnect (LGPLv2.1), vpnc-script (GPLv2+) — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
