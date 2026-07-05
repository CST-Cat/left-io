#include "CRimeBridge.h"

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int RimeBool;
typedef uintptr_t RimeSessionId;

typedef struct rime_traits_t {
  int data_size;
  const char* shared_data_dir;
  const char* user_data_dir;
  const char* distribution_name;
  const char* distribution_code_name;
  const char* distribution_version;
  const char* app_name;
  const char** modules;
  int min_log_level;
  const char* log_dir;
  const char* prebuilt_data_dir;
  const char* staging_dir;
} RimeTraits;

typedef struct {
  int length;
  int cursor_pos;
  int sel_start;
  int sel_end;
  char* preedit;
} RimeComposition;

typedef struct rime_candidate_t {
  char* text;
  char* comment;
  void* reserved;
} RimeCandidate;

typedef struct {
  int page_size;
  int page_no;
  RimeBool is_last_page;
  int highlighted_candidate_index;
  int num_candidates;
  RimeCandidate* candidates;
  char* select_keys;
} RimeMenu;

typedef struct rime_commit_t {
  int data_size;
  char* text;
} RimeCommit;

typedef struct rime_context_t {
  int data_size;
  RimeComposition composition;
  RimeMenu menu;
  char* commit_text_preview;
  char** select_labels;
} RimeContext;

typedef struct rime_status_t {
  int data_size;
  char* schema_id;
  char* schema_name;
  RimeBool is_disabled;
  RimeBool is_composing;
  RimeBool is_ascii_mode;
  RimeBool is_full_shape;
  RimeBool is_simplified;
  RimeBool is_traditional;
  RimeBool is_ascii_punct;
} RimeStatus;

typedef struct rime_candidate_list_iterator_t {
  void* ptr;
  int index;
  RimeCandidate candidate;
} RimeCandidateListIterator;

typedef struct rime_config_t {
  void* ptr;
} RimeConfig;

typedef struct rime_config_iterator_t {
  void* list;
  void* map;
  int index;
  const char* key;
  const char* path;
} RimeConfigIterator;

typedef struct rime_schema_list_item_t {
  char* schema_id;
  char* name;
  void* reserved;
} RimeSchemaListItem;

typedef struct rime_schema_list_t {
  size_t size;
  RimeSchemaListItem* list;
} RimeSchemaList;

typedef struct rime_string_slice_t {
  const char* str;
  size_t length;
} RimeStringSlice;

typedef struct rime_custom_api_t {
  int data_size;
} RimeCustomApi;

typedef struct rime_module_t {
  int data_size;
  const char* module_name;
  void (*initialize)(void);
  void (*finalize)(void);
  RimeCustomApi* (*get_api)(void);
} RimeModule;

typedef void (*RimeNotificationHandler)(void* context_object,
                                        RimeSessionId session_id,
                                        const char* message_type,
                                        const char* message_value);

typedef struct rime_api_t {
  int data_size;

  void (*setup)(RimeTraits* traits);
  void (*set_notification_handler)(RimeNotificationHandler handler,
                                   void* context_object);

  void (*initialize)(RimeTraits* traits);
  void (*finalize)(void);

  RimeBool (*start_maintenance)(RimeBool full_check);
  RimeBool (*is_maintenance_mode)(void);
  void (*join_maintenance_thread)(void);

  void (*deployer_initialize)(RimeTraits* traits);
  RimeBool (*prebuild)(void);
  RimeBool (*deploy)(void);
  RimeBool (*deploy_schema)(const char* schema_file);
  RimeBool (*deploy_config_file)(const char* file_name,
                                 const char* version_key);

  RimeBool (*sync_user_data)(void);

  RimeSessionId (*create_session)(void);
  RimeBool (*find_session)(RimeSessionId session_id);
  RimeBool (*destroy_session)(RimeSessionId session_id);
  void (*cleanup_stale_sessions)(void);
  void (*cleanup_all_sessions)(void);

  RimeBool (*process_key)(RimeSessionId session_id, int keycode, int mask);
  RimeBool (*commit_composition)(RimeSessionId session_id);
  void (*clear_composition)(RimeSessionId session_id);

  RimeBool (*get_commit)(RimeSessionId session_id, RimeCommit* commit);
  RimeBool (*free_commit)(RimeCommit* commit);
  RimeBool (*get_context)(RimeSessionId session_id, RimeContext* context);
  RimeBool (*free_context)(RimeContext* context);
  RimeBool (*get_status)(RimeSessionId session_id, RimeStatus* status);
  RimeBool (*free_status)(RimeStatus* status);

  void (*set_option)(RimeSessionId session_id, const char* option, RimeBool value);
  RimeBool (*get_option)(RimeSessionId session_id, const char* option);

  void (*set_property)(RimeSessionId session_id, const char* prop, const char* value);
  RimeBool (*get_property)(RimeSessionId session_id,
                           const char* prop,
                           char* value,
                           size_t buffer_size);

  RimeBool (*get_schema_list)(RimeSchemaList* schema_list);
  void (*free_schema_list)(RimeSchemaList* schema_list);

  RimeBool (*get_current_schema)(RimeSessionId session_id,
                                 char* schema_id,
                                 size_t buffer_size);
  RimeBool (*select_schema)(RimeSessionId session_id, const char* schema_id);

  RimeBool (*schema_open)(const char* schema_id, RimeConfig* config);
  RimeBool (*config_open)(const char* config_id, RimeConfig* config);
  RimeBool (*config_close)(RimeConfig* config);
  RimeBool (*config_get_bool)(RimeConfig* config, const char* key, RimeBool* value);
  RimeBool (*config_get_int)(RimeConfig* config, const char* key, int* value);
  RimeBool (*config_get_double)(RimeConfig* config, const char* key, double* value);
  RimeBool (*config_get_string)(RimeConfig* config,
                                const char* key,
                                char* value,
                                size_t buffer_size);
  const char* (*config_get_cstring)(RimeConfig* config, const char* key);
  RimeBool (*config_update_signature)(RimeConfig* config, const char* signer);
  RimeBool (*config_begin_map)(RimeConfigIterator* iterator,
                               RimeConfig* config,
                               const char* key);
  RimeBool (*config_next)(RimeConfigIterator* iterator);
  void (*config_end)(RimeConfigIterator* iterator);

  RimeBool (*simulate_key_sequence)(RimeSessionId session_id,
                                    const char* key_sequence);

  RimeBool (*register_module)(RimeModule* module);
  RimeModule* (*find_module)(const char* module_name);

  RimeBool (*run_task)(const char* task_name);

  const char* (*get_shared_data_dir)(void);
  const char* (*get_user_data_dir)(void);
  const char* (*get_sync_dir)(void);

  const char* (*get_user_id)(void);
  void (*get_user_data_sync_dir)(char* dir, size_t buffer_size);

  RimeBool (*config_init)(RimeConfig* config);
  RimeBool (*config_load_string)(RimeConfig* config, const char* yaml);

  RimeBool (*config_set_bool)(RimeConfig* config, const char* key, RimeBool value);
  RimeBool (*config_set_int)(RimeConfig* config, const char* key, int value);
  RimeBool (*config_set_double)(RimeConfig* config, const char* key, double value);
  RimeBool (*config_set_string)(RimeConfig* config,
                                const char* key,
                                const char* value);

  RimeBool (*config_get_item)(RimeConfig* config,
                              const char* key,
                              RimeConfig* value);
  RimeBool (*config_set_item)(RimeConfig* config,
                              const char* key,
                              RimeConfig* value);
  RimeBool (*config_clear)(RimeConfig* config, const char* key);
  RimeBool (*config_create_list)(RimeConfig* config, const char* key);
  RimeBool (*config_create_map)(RimeConfig* config, const char* key);
  size_t (*config_list_size)(RimeConfig* config, const char* key);
  RimeBool (*config_begin_list)(RimeConfigIterator* iterator,
                                RimeConfig* config,
                                const char* key);

  const char* (*get_input)(RimeSessionId session_id);
  size_t (*get_caret_pos)(RimeSessionId session_id);
  RimeBool (*select_candidate)(RimeSessionId session_id, size_t index);
  const char* (*get_version)(void);
  void (*set_caret_pos)(RimeSessionId session_id, size_t caret_pos);
  RimeBool (*select_candidate_on_current_page)(RimeSessionId session_id,
                                               size_t index);

  RimeBool (*candidate_list_begin)(RimeSessionId session_id,
                                   RimeCandidateListIterator* iterator);
  RimeBool (*candidate_list_next)(RimeCandidateListIterator* iterator);
  void (*candidate_list_end)(RimeCandidateListIterator* iterator);

  RimeBool (*user_config_open)(const char* config_id, RimeConfig* config);
  RimeBool (*candidate_list_from_index)(RimeSessionId session_id,
                                        RimeCandidateListIterator* iterator,
                                        int index);

  const char* (*get_prebuilt_data_dir)(void);
  const char* (*get_staging_dir)(void);

  void (*commit_proto)(RimeSessionId session_id, void* commit_builder);
  void (*context_proto)(RimeSessionId session_id, void* context_builder);
  void (*status_proto)(RimeSessionId session_id, void* status_builder);

  const char* (*get_state_label)(RimeSessionId session_id,
                                 const char* option_name,
                                 RimeBool state);

  RimeBool (*delete_candidate)(RimeSessionId session_id, size_t index);
  RimeBool (*delete_candidate_on_current_page)(RimeSessionId session_id,
                                               size_t index);

  RimeStringSlice (*get_state_label_abbreviated)(RimeSessionId session_id,
                                                 const char* option_name,
                                                 RimeBool state,
                                                 RimeBool abbreviated);

  RimeBool (*set_input)(RimeSessionId session_id, const char* input);

  void (*get_shared_data_dir_s)(char* dir, size_t buffer_size);
  void (*get_user_data_dir_s)(char* dir, size_t buffer_size);
  void (*get_prebuilt_data_dir_s)(char* dir, size_t buffer_size);
  void (*get_staging_dir_s)(char* dir, size_t buffer_size);
  void (*get_sync_dir_s)(char* dir, size_t buffer_size);

  RimeBool (*highlight_candidate)(RimeSessionId session_id, size_t index);
  RimeBool (*highlight_candidate_on_current_page)(RimeSessionId session_id,
                                                  size_t index);

  RimeBool (*change_page)(RimeSessionId session_id, RimeBool backward);
} RimeApi;

typedef RimeApi* (*RimeGetApiFunction)(void);

typedef struct {
  void* dylib;
  RimeApi* api;
  int ref_count;
  int initialized;
} OneHandRimeRuntime;

static OneHandRimeRuntime g_runtime = {0};
static char g_last_error[512] = {0};

#define RIME_STRUCT_INIT(Type, var) ((var).data_size = sizeof(Type) - sizeof((var).data_size))

static void set_last_error(const char* message) {
  if (!message) {
    g_last_error[0] = '\0';
    return;
  }
  snprintf(g_last_error, sizeof(g_last_error), "%s", message);
}

static void set_last_errorf(const char* format, const char* detail) {
  snprintf(g_last_error, sizeof(g_last_error), format, detail ? detail : "");
}

static int api_has_change_page(const RimeApi* api) {
  if (!api) {
    return 0;
  }
  size_t required = offsetof(RimeApi, change_page) + sizeof(api->change_page);
  return api->data_size >= (int)(required - sizeof(api->data_size)) && api->change_page != NULL;
}

static char* duplicate_string(const char* source) {
  if (!source) {
    return NULL;
  }
  size_t length = strlen(source);
  char* copy = (char*)malloc(length + 1);
  if (!copy) {
    return NULL;
  }
  memcpy(copy, source, length + 1);
  return copy;
}

static int ensure_runtime_initialized(const char* shared_data_dir,
                                      const char* user_data_dir,
                                      const char* app_name) {
  if (g_runtime.initialized) {
    return 1;
  }

  const char* env_path = getenv("LEFTIO_LIBRIME_PATH");
  const char* candidates[] = {
      env_path,
      "/opt/homebrew/lib/librime.1.dylib",
      "/opt/homebrew/lib/librime.dylib",
      "/usr/local/lib/librime.1.dylib",
      "/usr/local/lib/librime.dylib",
      "librime.1.dylib",
      "librime.dylib",
      NULL,
  };

  void* dylib = NULL;
  for (size_t i = 0; candidates[i]; ++i) {
    if (!candidates[i] || !candidates[i][0]) {
      continue;
    }
    dylib = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
    if (dylib) {
      break;
    }
  }

  if (!dylib) {
    set_last_error("librime not found. Set LEFTIO_LIBRIME_PATH or install librime.");
    return 0;
  }

  RimeGetApiFunction get_api = (RimeGetApiFunction)dlsym(dylib, "rime_get_api");
  if (!get_api) {
    set_last_error("loaded librime, but rime_get_api was missing.");
    dlclose(dylib);
    return 0;
  }

  RimeApi* api = get_api();
  if (!api) {
    set_last_error("rime_get_api returned NULL.");
    dlclose(dylib);
    return 0;
  }

  RimeTraits traits = {0};
  RIME_STRUCT_INIT(RimeTraits, traits);
  traits.shared_data_dir = shared_data_dir;
  traits.user_data_dir = user_data_dir;
  traits.distribution_name = "LeftIO";
  traits.distribution_code_name = "leftio";
  traits.distribution_version = "0.1.0";
  traits.app_name = app_name && app_name[0] ? app_name : "rime.leftio";
  traits.min_log_level = 1;

  api->setup(&traits);
  api->initialize(NULL);
  if (api->start_maintenance && api->start_maintenance(1) && api->join_maintenance_thread) {
    api->join_maintenance_thread();
  }

  g_runtime.dylib = dylib;
  g_runtime.api = api;
  g_runtime.initialized = 1;
  set_last_error(NULL);
  return 1;
}

static void shutdown_runtime_if_idle(void) {
  if (!g_runtime.initialized || g_runtime.ref_count > 0) {
    return;
  }

  if (g_runtime.api) {
    g_runtime.api->finalize();
  }
  if (g_runtime.dylib) {
    dlclose(g_runtime.dylib);
  }
  memset(&g_runtime, 0, sizeof(g_runtime));
}

static int validate_handle(OneHandRimeBridgeHandle* handle) {
  if (!handle || !g_runtime.api || !g_runtime.initialized) {
    set_last_error("rime session is unavailable.");
    return 0;
  }
  if (!g_runtime.api->find_session(handle->session_id)) {
    set_last_error("rime session was lost.");
    return 0;
  }
  return 1;
}

static int fetch_context(OneHandRimeBridgeHandle* handle, RimeContext* context) {
  if (!validate_handle(handle)) {
    return 0;
  }
  memset(context, 0, sizeof(*context));
  RIME_STRUCT_INIT(RimeContext, *context);
  if (!g_runtime.api->get_context(handle->session_id, context)) {
    set_last_error("failed to fetch rime context.");
    return 0;
  }
  return 1;
}

static int deploy_schema(const char* shared_data_dir, const char* schema_id) {
  if (!g_runtime.api || !g_runtime.api->deploy_schema || !schema_id || !schema_id[0]) {
    return 1;
  }

  char schema_file[1024] = {0};
  if (shared_data_dir && shared_data_dir[0]) {
    snprintf(schema_file, sizeof(schema_file), "%s/%s.schema.yaml", shared_data_dir, schema_id);
  } else {
    snprintf(schema_file, sizeof(schema_file), "%s.schema.yaml", schema_id);
  }
  if (!g_runtime.api->deploy_schema(schema_file)) {
    set_last_errorf("failed to deploy rime schema: %s", schema_file);
    return 0;
  }

  return 1;
}

OneHandRimeBridgeHandle* OneHandRimeBridgeCreate(const char* shared_data_dir,
                                                 const char* user_data_dir,
                                                 const char* schema_id,
                                                 const char* app_name) {
  if (!shared_data_dir || !shared_data_dir[0]) {
    set_last_error("shared_data_dir is empty.");
    return NULL;
  }
  if (!user_data_dir || !user_data_dir[0]) {
    set_last_error("user_data_dir is empty.");
    return NULL;
  }
  if (!schema_id || !schema_id[0]) {
    set_last_error("schema_id is empty.");
    return NULL;
  }

  if (!ensure_runtime_initialized(shared_data_dir, user_data_dir, app_name)) {
    return NULL;
  }

  if (!deploy_schema(shared_data_dir, schema_id)) {
    return NULL;
  }

  RimeSessionId session_id = g_runtime.api->create_session();
  if (!session_id) {
    set_last_error("failed to create rime session.");
    return NULL;
  }

  if (!g_runtime.api->select_schema(session_id, schema_id)) {
    g_runtime.api->destroy_session(session_id);
    set_last_errorf("failed to select rime schema: %s", schema_id);
    return NULL;
  }

  OneHandRimeBridgeHandle* handle = (OneHandRimeBridgeHandle*)calloc(1, sizeof(OneHandRimeBridgeHandle));
  if (!handle) {
    g_runtime.api->destroy_session(session_id);
    set_last_error("failed to allocate rime bridge handle.");
    return NULL;
  }

  handle->session_id = session_id;
  g_runtime.ref_count += 1;
  set_last_error(NULL);
  return handle;
}

void OneHandRimeBridgeDestroy(OneHandRimeBridgeHandle* handle) {
  if (!handle) {
    return;
  }
  if (g_runtime.api && g_runtime.initialized && handle->session_id) {
    g_runtime.api->destroy_session(handle->session_id);
  }
  free(handle);
  if (g_runtime.ref_count > 0) {
    g_runtime.ref_count -= 1;
  }
  shutdown_runtime_if_idle();
}

const char* OneHandRimeBridgeGetLastError(void) {
  return g_last_error;
}

bool OneHandRimeBridgeSetInput(OneHandRimeBridgeHandle* handle, const char* input) {
  if (!validate_handle(handle)) {
    return false;
  }
  if (!g_runtime.api->set_input(handle->session_id, input ? input : "")) {
    set_last_error("failed to update rime input.");
    return false;
  }
  set_last_error(NULL);
  return true;
}

bool OneHandRimeBridgeCommitComposition(OneHandRimeBridgeHandle* handle) {
  if (!validate_handle(handle)) {
    return false;
  }
  if (!g_runtime.api->commit_composition(handle->session_id)) {
    set_last_error("failed to commit rime composition.");
    return false;
  }
  set_last_error(NULL);
  return true;
}

void OneHandRimeBridgeClearComposition(OneHandRimeBridgeHandle* handle) {
  if (!validate_handle(handle)) {
    return;
  }
  g_runtime.api->clear_composition(handle->session_id);
  set_last_error(NULL);
}

bool OneHandRimeBridgeSelectCandidateOnCurrentPage(OneHandRimeBridgeHandle* handle,
                                                   size_t index) {
  if (!validate_handle(handle)) {
    return false;
  }
  if (!g_runtime.api->select_candidate_on_current_page(handle->session_id, index)) {
    set_last_error("failed to select rime candidate.");
    return false;
  }
  set_last_error(NULL);
  return true;
}

bool OneHandRimeBridgeChangePage(OneHandRimeBridgeHandle* handle, bool backward) {
  if (!validate_handle(handle)) {
    return false;
  }
  if (!api_has_change_page(g_runtime.api) ||
      !g_runtime.api->change_page(handle->session_id, backward ? 1 : 0)) {
    set_last_error("failed to change rime candidate page.");
    return false;
  }
  set_last_error(NULL);
  return true;
}

bool OneHandRimeBridgeIsAsciiMode(OneHandRimeBridgeHandle* handle) {
  if (!validate_handle(handle)) {
    return false;
  }

  RimeStatus status = {0};
  RIME_STRUCT_INIT(RimeStatus, status);
  if (!g_runtime.api->get_status(handle->session_id, &status)) {
    set_last_error("failed to read rime status.");
    return false;
  }

  bool is_ascii_mode = status.is_ascii_mode != 0;
  g_runtime.api->free_status(&status);
  set_last_error(NULL);
  return is_ascii_mode;
}

bool OneHandRimeBridgeSetAsciiMode(OneHandRimeBridgeHandle* handle, bool enabled) {
  if (!validate_handle(handle)) {
    return false;
  }

  g_runtime.api->set_option(handle->session_id, "ascii_mode", enabled ? 1 : 0);
  set_last_error(NULL);
  return true;
}

char* OneHandRimeBridgeCopyCommitText(OneHandRimeBridgeHandle* handle) {
  if (!validate_handle(handle)) {
    return NULL;
  }

  RimeCommit commit = {0};
  RIME_STRUCT_INIT(RimeCommit, commit);
  if (!g_runtime.api->get_commit(handle->session_id, &commit)) {
    return NULL;
  }

  char* text = duplicate_string(commit.text);
  g_runtime.api->free_commit(&commit);
  return text;
}

char* OneHandRimeBridgeCopyCurrentSchemaId(OneHandRimeBridgeHandle* handle) {
  if (!validate_handle(handle)) {
    return NULL;
  }

  char schema_id[256] = {0};
  if (!g_runtime.api->get_current_schema(handle->session_id, schema_id, sizeof(schema_id))) {
    set_last_error("failed to read current rime schema.");
    return NULL;
  }

  set_last_error(NULL);
  return duplicate_string(schema_id);
}

char* OneHandRimeBridgeCopyInput(OneHandRimeBridgeHandle* handle) {
  if (!validate_handle(handle)) {
    return NULL;
  }
  const char* input = g_runtime.api->get_input(handle->session_id);
  return duplicate_string(input);
}

char* OneHandRimeBridgeCopyPreedit(OneHandRimeBridgeHandle* handle) {
  RimeContext context;
  if (!fetch_context(handle, &context)) {
    return NULL;
  }

  char* preedit = duplicate_string(context.composition.preedit);
  g_runtime.api->free_context(&context);
  return preedit;
}

size_t OneHandRimeBridgeCandidateCount(OneHandRimeBridgeHandle* handle) {
  RimeContext context;
  if (!fetch_context(handle, &context)) {
    return 0;
  }

  size_t count = 0;
  if (context.menu.num_candidates > 0) {
    count = (size_t)context.menu.num_candidates;
  }
  g_runtime.api->free_context(&context);
  return count;
}

char* OneHandRimeBridgeCopyCandidateAtIndex(OneHandRimeBridgeHandle* handle,
                                            size_t index) {
  RimeContext context;
  if (!fetch_context(handle, &context)) {
    return NULL;
  }

  char* text = NULL;
  if ((int)index < context.menu.num_candidates) {
    text = duplicate_string(context.menu.candidates[index].text);
  }
  g_runtime.api->free_context(&context);
  return text;
}

void OneHandRimeBridgeFreeString(char* value) {
  free(value);
}
