#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leftio-rime-abi.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_DIR/fake_librime.c" <<'C'
#include <stddef.h>

typedef struct {
  int data_size;
  void (*setup)(void* traits);
} TruncatedRimeApi;

static void fake_setup(void* traits) {
  (void)traits;
}

void* rime_get_api(void) {
  static TruncatedRimeApi api = {
      (int)(sizeof(TruncatedRimeApi) - sizeof(int)),
      fake_setup,
  };
  return &api;
}
C

cat > "$TEST_DIR/harness.c" <<'C'
#include "CRimeBridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
  if (argc != 2) {
    return 64;
  }
  if (setenv("LEFTIO_LIBRIME_PATH", argv[1], 1) != 0) {
    return 65;
  }

  OneHandRimeBridgeHandle* handle = OneHandRimeBridgeCreate(
      "/tmp/leftio-shared",
      "/tmp/leftio-user",
      "onehand_t9",
      "rime.leftio.abi-test",
      "0.1.0");
  if (handle) {
    OneHandRimeBridgeDestroy(handle);
    fprintf(stderr, "truncated API unexpectedly created a session\n");
    return 1;
  }

  const char* error = OneHandRimeBridgeGetLastError();
  if (!error || !strstr(error, "required API member: initialize")) {
    fprintf(stderr, "unexpected ABI error: %s\n", error ? error : "(null)");
    return 2;
  }
  return 0;
}
C

xcrun clang \
  -Wall -Wextra -Wpedantic -Werror \
  -dynamiclib "$TEST_DIR/fake_librime.c" \
  -o "$TEST_DIR/librime-truncated.dylib"
xcrun clang \
  -Wall -Wextra -Wpedantic -Werror \
  "$TEST_DIR/harness.c" \
  "$ROOT_DIR/Sources/CRimeBridge/CRimeBridge.c" \
  -I "$ROOT_DIR/Sources/CRimeBridge/include" \
  -o "$TEST_DIR/abi-harness"

"$TEST_DIR/abi-harness" "$TEST_DIR/librime-truncated.dylib"
echo "Rime ABI guard test passed."
