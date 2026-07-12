#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leftio-rime-traits.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_DIR/fake_librime.c" <<'C'
#include "rime_api.h"

#include <string.h>

static const char* retained_app_name = NULL;
static const char* expected_app_name = "rime.leftio.trait-lifetime-test";

static void fake_setup(RimeTraits* traits) {
  retained_app_name = traits ? traits->app_name : NULL;
}
static void fake_initialize(RimeTraits* traits) { (void)traits; }
static void fake_deployer_initialize(RimeTraits* traits) { (void)traits; }
static Bool fake_deploy_schema(const char* path) { return path != NULL; }
static RimeSessionId fake_create_session(void) { return 1; }
static Bool fake_find_session(RimeSessionId session_id) { return session_id == 1; }
static Bool fake_destroy_session(RimeSessionId session_id) { return session_id == 1; }
static Bool fake_commit_composition(RimeSessionId session_id) { return session_id == 1; }
static void fake_clear_composition(RimeSessionId session_id) { (void)session_id; }
static Bool fake_get_commit(RimeSessionId session_id, RimeCommit* commit) {
  (void)session_id;
  (void)commit;
  return False;
}
static Bool fake_free_commit(RimeCommit* commit) {
  (void)commit;
  return True;
}
static Bool fake_get_context(RimeSessionId session_id, RimeContext* context) {
  (void)session_id;
  (void)context;
  return False;
}
static Bool fake_free_context(RimeContext* context) {
  (void)context;
  return True;
}
static Bool fake_get_status(RimeSessionId session_id, RimeStatus* status) {
  (void)session_id;
  (void)status;
  return False;
}
static Bool fake_free_status(RimeStatus* status) {
  (void)status;
  return True;
}
static void fake_set_option(RimeSessionId session_id, const char* name, Bool value) {
  (void)session_id;
  (void)name;
  (void)value;
}
static Bool fake_get_current_schema(RimeSessionId session_id,
                                    char* schema_id,
                                    size_t buffer_size) {
  (void)session_id;
  if (!schema_id || buffer_size == 0) return False;
  strncpy(schema_id, "onehand_t9", buffer_size);
  schema_id[buffer_size - 1] = '\0';
  return True;
}
static Bool fake_select_schema(RimeSessionId session_id, const char* schema_id) {
  return session_id == 1 && schema_id && strcmp(schema_id, "onehand_t9") == 0;
}
static const char* fake_get_input(RimeSessionId session_id) {
  return session_id == 1 ? "" : NULL;
}
static Bool fake_select_candidate(RimeSessionId session_id, size_t index) {
  (void)index;
  return session_id == 1;
}
static Bool fake_select_candidate_on_current_page(RimeSessionId session_id,
                                                  size_t index) {
  (void)index;
  return session_id == 1;
}
static Bool fake_candidate_list_begin(RimeSessionId session_id,
                                      RimeCandidateListIterator* iterator) {
  (void)session_id;
  (void)iterator;
  return False;
}
static Bool fake_candidate_list_next(RimeCandidateListIterator* iterator) {
  (void)iterator;
  return False;
}
static void fake_candidate_list_end(RimeCandidateListIterator* iterator) {
  (void)iterator;
}
static Bool fake_set_input(RimeSessionId session_id, const char* input) {
  (void)input;
  return session_id == 1 && retained_app_name &&
         strcmp(retained_app_name, expected_app_name) == 0;
}
static Bool fake_change_page(RimeSessionId session_id, Bool backward) {
  (void)backward;
  return session_id == 1;
}

RimeApi* rime_get_api(void) {
  static RimeApi api = {0};
  if (api.data_size == 0) {
    RIME_STRUCT_INIT(RimeApi, api);
    api.setup = fake_setup;
    api.initialize = fake_initialize;
    api.deployer_initialize = fake_deployer_initialize;
    api.deploy_schema = fake_deploy_schema;
    api.create_session = fake_create_session;
    api.find_session = fake_find_session;
    api.destroy_session = fake_destroy_session;
    api.commit_composition = fake_commit_composition;
    api.clear_composition = fake_clear_composition;
    api.get_commit = fake_get_commit;
    api.free_commit = fake_free_commit;
    api.get_context = fake_get_context;
    api.free_context = fake_free_context;
    api.get_status = fake_get_status;
    api.free_status = fake_free_status;
    api.set_option = fake_set_option;
    api.get_current_schema = fake_get_current_schema;
    api.select_schema = fake_select_schema;
    api.get_input = fake_get_input;
    api.select_candidate = fake_select_candidate;
    api.select_candidate_on_current_page = fake_select_candidate_on_current_page;
    api.candidate_list_begin = fake_candidate_list_begin;
    api.candidate_list_next = fake_candidate_list_next;
    api.candidate_list_end = fake_candidate_list_end;
    api.set_input = fake_set_input;
    api.change_page = fake_change_page;
  }
  return &api;
}
C

cat > "$TEST_DIR/harness.c" <<'C'
#include "CRimeBridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
  if (argc != 2) return 64;
  if (setenv("LEFTIO_LIBRIME_PATH", argv[1], 1) != 0) return 65;

  char app_name[] = "rime.leftio.trait-lifetime-test";
  OneHandRimeBridgeHandle* handle = OneHandRimeBridgeCreate(
      "/tmp/leftio-trait-shared",
      "/tmp/leftio-trait-user",
      "onehand_t9",
      app_name,
      "0.1.0");
  if (!handle) {
    fprintf(stderr, "failed to create fake session: %s\n",
            OneHandRimeBridgeGetLastError());
    return 1;
  }

  memset(app_name, 'x', sizeof(app_name) - 1);
  app_name[sizeof(app_name) - 1] = '\0';
  if (!OneHandRimeBridgeSetInput(handle, "64")) {
    fprintf(stderr, "librime observed an expired caller-owned app_name\n");
    OneHandRimeBridgeDestroy(handle);
    return 2;
  }

  OneHandRimeBridgeDestroy(handle);
  return 0;
}
C

xcrun clang \
  -Wall -Wextra -Wpedantic -Werror \
  -dynamiclib "$TEST_DIR/fake_librime.c" \
  -I "$ROOT_DIR/vendor/librime/src" \
  -o "$TEST_DIR/librime-trait-lifetime.dylib"

xcrun clang \
  -Wall -Wextra -Wpedantic -Werror \
  "$TEST_DIR/harness.c" \
  "$ROOT_DIR/Sources/CRimeBridge/CRimeBridge.c" \
  -I "$ROOT_DIR/Sources/CRimeBridge/include" \
  -o "$TEST_DIR/trait-lifetime-harness"

"$TEST_DIR/trait-lifetime-harness" "$TEST_DIR/librime-trait-lifetime.dylib"
echo "Rime trait lifetime test passed."
