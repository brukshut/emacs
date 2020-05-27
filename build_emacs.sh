#!/bin/bash

##
## build_emacs.sh
## build a simple lightweight emacs without the kitchen sink.
##

## functions
function fetch_emacs_src {
  local name=emacs
  local version=$1
  local srcdir=/usr/local/src
  local tarball=${name}.${version}.tar.xz
  local src=${name}-${version}
  local url=http://mirrors.ocf.berkeley.edu/gnu/emacs/${name}-${version}.tar.xz
  [[ -d ${srcdir} ]] || sudo mkdir -p ${srcdir}
  [[ -d ${srcdir}/${src} ]] ||
    ( [[ -e ${srcdir}/${tarball} ]] ||
      ( wget $url --output-document=/tmp/${tarball}
        sudo mv /tmp/${tarball} $srcdir
        sudo chown root:staff ${srcdir}/${tarball}
        sudo tar xvf ${srcdir}/${tarball} -C ${srcdir}
        sudo chown -R root:staff ${srcdir}/${src} ))
}

function debian_prep {
  ## refresh apt cache
  sudo apt-get update -y
  for pkg in ncurses-dev libgnutls28-dev; do
    sudo apt-get install ${pkg} -y
  done
}

function darwin_prep {
  brew update
  brew install gnutls
}

function build_emacs {
  local version=$1
  fetch_emacs_src $version
  local emacs_src=/usr/local/src/emacs-${version}
  [[ -d ${emacs_src} ]] && 
    cd ${emacs_src}
    CC=/usr/bin/gcc
    CXX=/usr/bin/g++
    LD=/usr/bin/ld
    AS=/usr/bin/as
    AR=/usr/bin/ar
    #CFLAGS="-no-pie -I/usr/local/include"
    CFLAGS="-I/usr/local/include"
    LDFLAGS="-Wl,-L/usr/local/lib -Wl,-rpath=/usr/local/lib"
    export CC CXX LD AS AR CFLAGS LDFLAGS
    sudo ./configure --prefix=/usr/local \
    --without-all \
    --without-ns \
    --without-x \
    --without-x-toolkit \
    --without-toolkit-scroll-bars \
    --with-gnutls
    sudo /usr/bin/make 
    sudo /usr/bin/make install
    cleanup_src emacs ${version}
}

function cleanup_src {
  local name=$1
  local version=$2
  local srcdir=/usr/local/src
  [[ -e ${srcdir}/${name}.${version}.tar.xz ]] &&
    sudo rm -rf ${srcdir}/${name}.${version}.tar.xz
  [[ -d ${srcdir}/${name}-${version} ]] &&
    sudo rm -rf ${srcdir}/${name}-${version}
}

## end functions

## main
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
VERSION=26.3

## make sure prerequisties are installed
[[ $(uname) == 'Darwin' ]] && darwin_prep
[[ $(uname) == 'Linux' ]] &&
  ( [[ $(lsb_release -s -i) == "Debian" ]] && debian_prep
    [[ $(lsb_release -s -i) == "Raspbian" ]] && debian_prep )

## compile and install emacs
build_emacs ${VERSION}
## end main
