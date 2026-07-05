#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
LIBRIME_DIR="$VENDOR_DIR/librime"
PYTHON_USER_BASE="$(python3 -m site --user-base 2>/dev/null || true)"
if [[ -z "$PYTHON_USER_BASE" ]]; then
  PYTHON_USER_BASE="$HOME/Library/Python/$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
fi
PYTHON_USER_BIN="$PYTHON_USER_BASE/bin"

ensure_librime_checkout() {
  mkdir -p "$VENDOR_DIR"
  if [[ ! -d "$LIBRIME_DIR/.git" ]]; then
    git clone --recursive https://github.com/rime/librime.git "$LIBRIME_DIR"
    return 0
  fi

  (
    cd "$LIBRIME_DIR"
    git submodule update --init --recursive
  )
}

ensure_cmake() {
  if command -v cmake >/dev/null 2>&1; then
    return 0
  fi

  python3 -m pip install --user cmake
  export PATH="$PYTHON_USER_BIN:$PATH"

  if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake installation failed." >&2
    exit 1
  fi
}

ensure_boost() {
  if [[ -x "$LIBRIME_DIR/deps/boost-1.89.0/b2" ]]; then
    return 0
  fi

  (
    cd "$LIBRIME_DIR"
    bash install-boost.sh
  )
}

build_librime() {
  export PATH="$PYTHON_USER_BIN:$PATH"
  export BOOST_ROOT="$LIBRIME_DIR/deps/boost-1.89.0"
  export MAKEFLAGS=""
  export NOPARALLEL=1

  (
    cd "$LIBRIME_DIR"
    make NOPARALLEL=1 deps
    make NOPARALLEL=1 release
  )
}

ensure_librime_checkout
ensure_cmake
ensure_boost
build_librime

find "$LIBRIME_DIR" -path '*librime*.dylib' -maxdepth 4 2>/dev/null | sort
