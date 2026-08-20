# Third-Party Notices

## OpenConnect (libopenconnect)

- Version: 9.21 (pinned in `scripts/build_core.sh`)
- Project: https://www.infradead.org/openconnect/
- License: GNU Lesser General Public License v2.1 (LGPLv2.1)
- Source: https://www.infradead.org/openconnect/download/openconnect-9.21.tar.gz

libopenconnect is cross-compiled for Android as a shared library
(`libopenconnect.so`) and dynamically linked/loaded by this app via JNI.
It is not modified. The complete corresponding source code is available at
the URL above; `scripts/build_core.sh` in this repository reproduces the
bundled binary.

LGPLv2.1 full text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
