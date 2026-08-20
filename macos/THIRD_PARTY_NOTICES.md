# Third-Party Notices

This application bundles the following third-party software:

## OpenConnect

- Version: 9.21 (pinned in `Scripts/build_core.sh`)
- Project: https://www.infradead.org/openconnect/
- License: GNU Lesser General Public License v2.1 (LGPLv2.1)
- Source: https://www.infradead.org/openconnect/download/openconnect-9.21.tar.gz

OpenConnect is bundled as a standalone executable that this application
launches as a child process. It is not linked into the application binary.
The complete corresponding source code is available at the URL above, and
`Scripts/build_core.sh` in this repository reproduces the bundled binary.

LGPLv2.1 full text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt

## vpnc-script

- Project: https://gitlab.com/openconnect/vpnc-scripts
- License: GPLv2+
- Bundled with local modifications (macOS network service detection fix,
  pf-based kill switch hooks). The modified script is included verbatim in
  `Resources/vpnc-script`.
