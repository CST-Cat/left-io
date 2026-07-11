#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
LIBRIME_DIR="$VENDOR_DIR/librime"
LIBRIME_REPOSITORY="https://github.com/rime/librime.git"
# librime 1.17.0. Keep source and submodule revisions reproducible.
LIBRIME_REVISION="${LEFTIO_LIBRIME_REVISION:-d71168e9e8c8392ed219dca011dbc76b80727d6c}"
LIBRIME_REF="${LEFTIO_LIBRIME_REF:-refs/tags/latest}"
BUILD_UNIVERSAL="${LEFTIO_BUILD_UNIVERSAL:-1}"
FORCE_CLEAN_BUILD="${LEFTIO_FORCE_CLEAN_LIBRIME:-0}"
MACOSX_DEPLOYMENT_TARGET="${LEFTIO_MIN_SYSTEM_VERSION:-13.0}"
BOOST_TARBALL="boost_1_89_0.tar.gz"
BOOST_TARBALL_SHA256="9de758db755e8330a01d995b0a24d09798048400ac25c03fc5ea9be364b13c93"

if [[ ! "$MACOSX_DEPLOYMENT_TARGET" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
  echo "LEFTIO_MIN_SYSTEM_VERSION must contain 2-3 numeric components." >&2
  exit 1
fi
if [[ "$FORCE_CLEAN_BUILD" != "0" && "$FORCE_CLEAN_BUILD" != "1" ]]; then
  echo "LEFTIO_FORCE_CLEAN_LIBRIME must be 0 or 1." >&2
  exit 1
fi

ensure_librime_checkout() {
  mkdir -p "$VENDOR_DIR"
  if [[ ! -d "$LIBRIME_DIR/.git" ]]; then
    git init "$LIBRIME_DIR"
    git -C "$LIBRIME_DIR" remote add origin "$LIBRIME_REPOSITORY"
  fi

  if [[ -n "$(git -C "$LIBRIME_DIR" status --porcelain --untracked-files=no)" ]]; then
    echo "Refusing to replace tracked changes in $LIBRIME_DIR." >&2
    exit 1
  fi

  if ! git -C "$LIBRIME_DIR" cat-file -e "$LIBRIME_REVISION^{commit}" 2>/dev/null; then
    git -C "$LIBRIME_DIR" fetch --depth 1 origin "$LIBRIME_REF"
    local fetched_revision
    fetched_revision="$(git -C "$LIBRIME_DIR" rev-parse FETCH_HEAD)"
    if [[ "$fetched_revision" != "$LIBRIME_REVISION" ]]; then
      echo "Pinned ref $LIBRIME_REF resolved to $fetched_revision, expected $LIBRIME_REVISION." >&2
      exit 1
    fi
  fi
  git -C "$LIBRIME_DIR" checkout --detach "$LIBRIME_REVISION"
  git -C "$LIBRIME_DIR" submodule sync --recursive
  git -C "$LIBRIME_DIR" submodule update --init --recursive
  if ! git -C "$LIBRIME_DIR" submodule foreach --recursive --quiet \
    'test -z "$(git status --porcelain --untracked-files=normal)"'; then
    echo "Refusing to build with tracked or unexpected untracked changes in a librime submodule." >&2
    exit 1
  fi

  local unexpected_untracked=0
  while IFS= read -r path; do
    case "$path" in
      .leftio-build-configuration|deps/boost_1_89_0.tar.gz)
        ;;
      *)
        echo "Unexpected untracked file in pinned librime checkout: $path" >&2
        unexpected_untracked=1
        ;;
    esac
  done < <(git -C "$LIBRIME_DIR" status --porcelain --untracked-files=normal | sed -n 's/^?? //p')
  if [[ "$unexpected_untracked" == "1" ]]; then
    exit 1
  fi

  local actual_revision
  actual_revision="$(git -C "$LIBRIME_DIR" rev-parse HEAD)"
  if [[ "$actual_revision" != "$LIBRIME_REVISION" ]]; then
    echo "Expected librime $LIBRIME_REVISION, got $actual_revision." >&2
    exit 1
  fi
}

ensure_cmake() {
  if command -v cmake >/dev/null 2>&1; then
    return 0
  fi

  local homebrew_cmake_dir
  for homebrew_cmake_dir in \
    /opt/homebrew/opt/cmake/bin \
    /usr/local/opt/cmake/bin; do
    if [[ -x "$homebrew_cmake_dir/cmake" ]]; then
      export PATH="$homebrew_cmake_dir:$PATH"
      return 0
    fi
  done

  cat >&2 <<'MESSAGE'
cmake is required to build the pinned librime source.
Install it explicitly (for example with Homebrew) and rerun this script.
LeftIO does not run an unpinned pip installer during a build.
MESSAGE
  exit 1
}

ensure_boost() {
  local boost_archive="$LIBRIME_DIR/deps/$BOOST_TARBALL"
  if [[ -f "$boost_archive" ]]; then
    printf '%s  %s\n' "$BOOST_TARBALL_SHA256" "$boost_archive" | shasum -a 256 -c -
  fi

  if [[ "$FORCE_CLEAN_BUILD" == "1" ]]; then
    # The archive checksum says nothing about a previously extracted tree.
    # Release builds discard it so headers and generated Boost tools are
    # recreated from the verified archive instead of trusted incrementally.
    rm -rf "$LIBRIME_DIR/deps/boost-1.89.0"
  fi

  if [[ ! -x "$LIBRIME_DIR/deps/boost-1.89.0/b2" ]]; then
    # librime's pinned script verifies the Boost archive with SHA-256 before
    # extracting it.
    (
      cd "$LIBRIME_DIR"
      bash install-boost.sh
    )
  fi

  if [[ ! -f "$boost_archive" ]]; then
    echo "Boost is extracted, but its pinned source archive is missing: $boost_archive" >&2
    echo "Remove deps/boost-1.89.0 and rerun to download and verify it again." >&2
    exit 1
  fi
  printf '%s  %s\n' "$BOOST_TARBALL_SHA256" "$boost_archive" | shasum -a 256 -c -
}

reset_build_if_configuration_changed() {
  local architecture_label="native"
  if [[ "$BUILD_UNIVERSAL" == "1" ]]; then
    architecture_label="arm64+x86_64"
  fi
  local desired_configuration
  desired_configuration="revision=$LIBRIME_REVISION architectures=$architecture_label min_macos=$MACOSX_DEPLOYMENT_TARGET"
  local marker="$LIBRIME_DIR/.leftio-build-configuration"

  if [[ "$FORCE_CLEAN_BUILD" != "1" ]] &&
     [[ -f "$marker" ]] &&
     [[ "$(<"$marker")" == "$desired_configuration" ]]; then
    return 0
  fi

  (
    cd "$LIBRIME_DIR"
    make NOPARALLEL=1 clean
    make NOPARALLEL=1 -f deps.mk clean
  )
  printf '%s\n' "$desired_configuration" > "$marker"
}

detect_librime() {
  local candidate
  for candidate in \
    "$LIBRIME_DIR/build/lib/librime.1.dylib" \
    "$LIBRIME_DIR/build/lib/librime.dylib" \
    "$LIBRIME_DIR/dist/lib/librime.1.dylib" \
    "$LIBRIME_DIR/dist/lib/librime.dylib"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

build_librime() {
  export BOOST_ROOT="$LIBRIME_DIR/deps/boost-1.89.0"
  export MACOSX_DEPLOYMENT_TARGET
  export MAKEFLAGS=""
  export NOPARALLEL=1

  local make_arguments=(NOPARALLEL=1)
  if [[ "$BUILD_UNIVERSAL" == "1" ]]; then
    make_arguments+=(BUILD_UNIVERSAL=1)
  fi

  (
    cd "$LIBRIME_DIR"
    make "${make_arguments[@]}" deps
    make "${make_arguments[@]}" release
  )
}

verify_architectures() {
  local dylib="$1"
  if [[ "$BUILD_UNIVERSAL" != "1" ]]; then
    return 0
  fi

  local architectures
  architectures="$(lipo -archs "$dylib")"
  for required in arm64 x86_64; do
    if [[ " $architectures " != *" $required "* ]]; then
      echo "Pinned librime is missing required architecture $required: $architectures" >&2
      exit 1
    fi
  done
}

ensure_librime_checkout
ensure_cmake
ensure_boost
reset_build_if_configuration_changed
build_librime

LIBRIME_DYLIB="$(detect_librime)"
verify_architectures "$LIBRIME_DYLIB"
printf '%s\n' "$LIBRIME_DYLIB"
