#!/bin/bash
##
## build_emacs.sh
## Build a small, terminal-only emacs without the kitchen sink.
##
## usage: build_emacs.sh [version]
##
## environment:
##   PREFIX=/usr/local   install prefix
##   FORCE=1             rebuild even if the requested version is installed
##   KEEP_OLD=1          keep share/libexec dirs from previously installed versions
##
set -euo pipefail

VERSION=${1:-31.1}
PREFIX=${PREFIX:-/usr/local}
MIRROR=https://ftpmirror.gnu.org/emacs
KEYRING_URL=https://ftp.gnu.org/gnu/gnu-keyring.gpg

PATH=/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
export HOMEBREW_NO_AUTO_UPDATE=1

## only use sudo when not root (e.g. packer) and the prefix isn't user-writable
if [[ ${EUID} -eq 0 ]]; then ROOT=""; else ROOT="sudo"; fi
if [[ ${EUID} -eq 0 || -w ${PREFIX} ]]; then SUDO=""; else SUDO="sudo"; fi

OS=$(uname -s)
EXTRA_FLAGS=""
WORKDIR=""

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

ncpu() { nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2; }

on_exit() {
  local rc=$?
  if [[ -n ${WORKDIR} && -d ${WORKDIR} ]]; then
    if [[ ${rc} -eq 0 ]]; then
      rm -rf "${WORKDIR}"
    else
      printf 'build failed (exit %d); build tree kept at %s\n' "${rc}" "${WORKDIR}" >&2
    fi
  fi
}
trap on_exit EXIT

## ---------------------------------------------------------------------------
## prerequisites
## ---------------------------------------------------------------------------

debian_prep() {
  local pkgs="build-essential pkg-config curl xz-utils gpgv
              libncurses-dev libgnutls28-dev zlib1g-dev libgpm-dev"
  ${ROOT} apt-get update -y
  # libtree-sitter-dev only exists on Debian 12 / Ubuntu 23.04 and newer
  if apt-cache show libtree-sitter-dev >/dev/null 2>&1; then
    pkgs="${pkgs} libtree-sitter-dev"
    EXTRA_FLAGS="${EXTRA_FLAGS} --with-tree-sitter"
  else
    log "libtree-sitter-dev unavailable; building without tree-sitter"
  fi
  # shellcheck disable=SC2086
  ${ROOT} env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${pkgs}
  EXTRA_FLAGS="${EXTRA_FLAGS} --with-gpm --with-file-notification=inotify"
}

darwin_prep() {
  command -v brew >/dev/null || die "homebrew is required on macOS"
  brew update
  brew install gnutls pkg-config tree-sitter gnupg
  EXTRA_FLAGS="${EXTRA_FLAGS} --with-tree-sitter --with-file-notification=kqueue"
}

prep() {
  case ${OS} in
    Darwin) darwin_prep ;;
    Linux)
      [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
      local ids
      ids=$(. /etc/os-release && echo "${ID:-} ${ID_LIKE:-}")
      case " ${ids} " in
        *" debian "*|*" raspbian "*|*" ubuntu "*) debian_prep ;;
        *) die "unsupported linux distribution: ${ids}" ;;
      esac
      ;;
    *) die "unsupported OS: ${OS}" ;;
  esac
}

## ---------------------------------------------------------------------------
## fetch + verify
## ---------------------------------------------------------------------------

fetch_src() {
  local tarball=emacs-${VERSION}.tar.xz
  log "downloading ${tarball}"
  curl -fsSL -o "${WORKDIR}/${tarball}"     "${MIRROR}/${tarball}"
  curl -fsSL -o "${WORKDIR}/${tarball}.sig" "${MIRROR}/${tarball}.sig"
  curl -fsSL -o "${WORKDIR}/gnu-keyring.gpg" "${KEYRING_URL}"

  log "verifying GPG signature"
  gpgv --keyring "${WORKDIR}/gnu-keyring.gpg" \
    "${WORKDIR}/${tarball}.sig" "${WORKDIR}/${tarball}" \
    || die "signature verification failed for ${tarball}"

  tar xf "${WORKDIR}/${tarball}" -C "${WORKDIR}"
}

## ---------------------------------------------------------------------------
## build + install
## ---------------------------------------------------------------------------

build_emacs() {
  local src=${WORKDIR}/emacs-${VERSION}
  cd "${src}" || die "source directory ${src} missing"

  log "configuring emacs ${VERSION}"
  # shellcheck disable=SC2086
  ./configure --prefix="${PREFIX}" \
    --without-all \
    --without-x \
    --without-ns \
    --with-gnutls \
    --with-zlib \
    --with-threads \
    --with-modules \
    ${EXTRA_FLAGS} \
    CFLAGS="-O2"

  log "compiling with $(ncpu) jobs"
  make -j"$(ncpu)"

  log "installing to ${PREFIX}"
  ${SUDO} make install-strip
  [[ ${OS} == Darwin ]] && resign_darwin
  return 0
}

## stripping invalidates the linker's ad-hoc signature, and Apple Silicon
## SIGKILLs any arm64 binary with an invalid signature ("Killed: 9").
resign_darwin() {
  local f
  log "re-signing installed binaries (ad-hoc)"
  for f in "${PREFIX}/bin/emacs-${VERSION}" "${PREFIX}/bin/emacsclient" \
           "${PREFIX}/bin/etags" "${PREFIX}/bin/ctags" "${PREFIX}/bin/ebrowse" \
           "${PREFIX}/libexec/emacs/${VERSION}"/*/*; do
    [[ -f ${f} && ! -L ${f} ]] || continue
    file -b "${f}" | grep -q Mach-O || continue
    ${SUDO} codesign --force --sign - "${f}"
  done
  ${SUDO} codesign --verify "${PREFIX}/bin/emacs-${VERSION}" \
    || die "codesign verification failed for emacs-${VERSION}"
}

## remove share/libexec trees left behind by previously installed versions.
## only touches directories named like a version number (site-lisp is kept).
cleanup_old_versions() {
  [[ ${KEEP_OLD:-0} == 1 ]] && return 0
  local base dir name
  for base in "${PREFIX}/share/emacs" "${PREFIX}/libexec/emacs"; do
    [[ -d ${base} ]] || continue
    for dir in "${base}"/*; do
      [[ -d ${dir} ]] || continue
      name=${dir##*/}
      if [[ ${name} =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ && ${name} != "${VERSION}" ]]; then
        log "removing old version dir ${dir}"
        ${SUDO} rm -rf "${dir}"
      fi
    done
  done
  for dir in "${PREFIX}/bin"/emacs-*; do
    [[ -f ${dir} ]] || continue
    name=${dir##*/emacs-}
    if [[ ${name} =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ && ${name} != "${VERSION}" ]]; then
      log "removing old binary ${dir}"
      ${SUDO} rm -f "${dir}"
    fi
  done
}

installed_version() {
  [[ -x ${PREFIX}/bin/emacs ]] || return 0
  "${PREFIX}/bin/emacs" --version 2>/dev/null | head -n1 | awk '{print $3}'
}

## ---------------------------------------------------------------------------
## main
## ---------------------------------------------------------------------------

main() {
  if [[ ${FORCE:-0} != 1 && "$(installed_version)" == "${VERSION}" ]]; then
    log "emacs ${VERSION} already installed at ${PREFIX}/bin/emacs (FORCE=1 to rebuild)"
    exit 0
  fi

  prep
  WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/build-emacs.XXXXXX")
  fetch_src
  build_emacs
  cleanup_old_versions

  log "done: $("${PREFIX}/bin/emacs" --version | head -n1)"
}

main "$@"
