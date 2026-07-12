#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP_PATH="${1:-$ROOT_DIR/.build/input-method/LeftIO.app}"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leftio-prebuilt-rime.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
SOURCE_SHARED_DATA_DIR="$SOURCE_APP_PATH/Contents/Resources/Rime"
SOURCE_LIBRIME_PATH="$SOURCE_APP_PATH/Contents/Frameworks/librime.1.dylib"
SHARED_DATA_DIR="$TEST_DIR/Rime"
LIBRIME_PATH="$TEST_DIR/librime.1.dylib"

[[ -d "$SOURCE_APP_PATH" ]] || {
  echo "Missing app for prebuilt Rime test: $SOURCE_APP_PATH" >&2
  exit 1
}

for required in \
  "$SOURCE_LIBRIME_PATH" \
  "$SOURCE_SHARED_DATA_DIR/build/default.yaml" \
  "$SOURCE_SHARED_DATA_DIR/build/onehand_t9.schema.yaml" \
  "$SOURCE_SHARED_DATA_DIR/build/onehand_t9.prism.bin" \
  "$SOURCE_SHARED_DATA_DIR/build/onehand_t9.table.bin"; do
  [[ -f "$required" ]] || {
    echo "Missing prebuilt Rime artifact: $required" >&2
    exit 1
  }
done

# Loading a signed dylib can cause macOS to attach protected com.apple.macl
# metadata to its containing app. Exercise exact temporary copies of the
# production engine and Rime workspace so this read-only test cannot mutate
# the distribution artifact checked afterward.
ditto "$SOURCE_LIBRIME_PATH" "$LIBRIME_PATH"
ditto "$SOURCE_SHARED_DATA_DIR" "$SHARED_DATA_DIR"

cat > "$TEST_DIR/harness.c" <<'C'
#include "CRimeBridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double elapsed_seconds(struct timespec start, struct timespec end) {
  return (double)(end.tv_sec - start.tv_sec) +
         (double)(end.tv_nsec - start.tv_nsec) / 1000000000.0;
}

int main(int argc, char** argv) {
  if (argc != 4) {
    return 64;
  }
  if (setenv("LEFTIO_LIBRIME_PATH", argv[1], 1) != 0) {
    return 65;
  }

  struct timespec start = {0};
  struct timespec end = {0};
  clock_gettime(CLOCK_MONOTONIC, &start);
  char app_name[] = "rime.leftio.prebuilt-test";
  OneHandRimeBridgeHandle* handle = OneHandRimeBridgeCreate(
      argv[2], argv[3], "onehand_t9", app_name, "0.1.0");
  clock_gettime(CLOCK_MONOTONIC, &end);
  if (!handle) {
    fprintf(stderr, "prebuilt Rime session failed: %s\n", OneHandRimeBridgeGetLastError());
    return 1;
  }

  // The bridge contract allows caller-owned strings. librime/glog retains
  // app_name after setup, so the bridge must give it process-lifetime storage
  // rather than the Swift withCString buffer used by production callers.
  memset(app_name, 'x', sizeof(app_name) - 1);
  app_name[sizeof(app_name) - 1] = '\0';

  double startup = elapsed_seconds(start, end);
  if (startup >= 2.0) {
    fprintf(stderr, "prebuilt Rime startup took %.3f seconds\n", startup);
    OneHandRimeBridgeDestroy(handle);
    return 2;
  }
  if (!OneHandRimeBridgeSetInput(handle, "64")) {
    fprintf(stderr, "failed to send test input: %s\n", OneHandRimeBridgeGetLastError());
    OneHandRimeBridgeDestroy(handle);
    return 3;
  }

  int found = 0;
  size_t count = OneHandRimeBridgeCandidateCount(handle);
  for (size_t index = 0; index < count; ++index) {
    char* candidate = OneHandRimeBridgeCopyCandidateAtIndex(handle, index);
    if (candidate && strcmp(candidate, "你") == 0) {
      found = 1;
    }
    OneHandRimeBridgeFreeString(candidate);
  }
  OneHandRimeBridgeDestroy(handle);
  if (!found) {
    fprintf(stderr, "prebuilt Rime did not return the expected candidate\n");
    return 4;
  }

  printf("Prebuilt Rime startup passed in %.3f seconds.\n", startup);
  return 0;
}
C

xcrun clang \
  -Wall -Wextra -Wpedantic -Werror \
  "$TEST_DIR/harness.c" \
  "$ROOT_DIR/Sources/CRimeBridge/CRimeBridge.c" \
  -I "$ROOT_DIR/Sources/CRimeBridge/include" \
  -o "$TEST_DIR/prebuilt-rime-harness"

mkdir -p "$TEST_DIR/user-data/build"
# Simulate a stale, partially-written workspace left by an older release. The
# packaged staging root must prevent this file from overriding the immutable
# prebuilt workspace.
printf 'invalid: [\n' > "$TEST_DIR/user-data/build/default.yaml"
"$TEST_DIR/prebuilt-rime-harness" \
  "$LIBRIME_PATH" \
  "$SHARED_DATA_DIR" \
  "$TEST_DIR/user-data"
