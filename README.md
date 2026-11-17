# emacs

- `build_emacs.sh` shell script, downloads, verifies and compiles emacs
- builds a lightweight, terminal-only emacs without the kitchen sink
- provides TLS support using `gnutls` for MELPA
- enables zlib, threads, dynamic modules (for `vterm`), file notification
  (inotify/kqueue) and tree-sitter (where available); gpm on Linux
- verifies the release tarball's GPG signature against the GNU keyring
- produces working binaries on macOS (Intel and Apple Silicon) and
  Debian / Ubuntu / Raspberry Pi OS
- compiles as the invoking user; only the install step uses `sudo`
  (not needed when run as root)
- idempotent: skips the build if the requested version is already installed
- suitable for use with packer, ansible, etc.

## usage

```sh
./build_emacs.sh            # default version (31.1)
./build_emacs.sh 31.2       # specific version
FORCE=1 ./build_emacs.sh    # rebuild even if already installed
KEEP_OLD=1 ./build_emacs.sh # keep share/libexec dirs from older versions
PREFIX=$HOME/.local ./build_emacs.sh
```
