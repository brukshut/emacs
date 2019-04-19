# emacs

- `build_emacs.sh` shell script, downloads and compiles latest version of emacs
- builds lightweight version of emacs without the kitchen sink
- provides TLS support using `gnutls` for MELPA
- produces working binaries on Darwin and Debian
- requires `sudo` or root access
- suitable for use with packer, ansible, etc.
