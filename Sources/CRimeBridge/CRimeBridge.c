#include "CRimeBridge.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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
  char* shared_data_dir;
  char* user_data_dir;
  char* app_name;
  char* distribution_version;
  char* deployed_schema_file;
} OneHandRimeRuntime;

static OneHandRimeRuntime g_runtime = {0};
static pthread_mutex_t g_runtime_mutex = PTHREAD_MUTEX_INITIALIZER;
static char g_last_error[512] = {0};

#define RIME_STRUCT_INIT(Type, var) ((var).data_size = sizeof(Type) - sizeof((var).data_size))
#define RIME_API_HAS(api, member)                                             \
  ((api) != NULL &&                                                          \
   (api)->data_size >=                                                       \
       (int)(offsetof(RimeApi, member) + sizeof((api)->member) -             \
             sizeof((api)->data_size)) &&                                    \
   (api)->member != NULL)

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

static int require_api_member(const RimeApi* api,
                              int available,
                              const char* member_name) {
  (void)api;
  if (available) {
    return 1;
  }
  set_last_errorf("loaded librime does not provide required API member: %s",
                  member_name);
  return 0;
}

static int validate_required_api(const RimeApi* api) {
#define REQUIRE_RIME_API(member)                                              \
  do {                                                                        \
    if (!require_api_member(api, RIME_API_HAS(api, member), #member)) {       \
      return 0;                                                               \
    }                                                                         \
  } while (0)

  REQUIRE_RIME_API(setup);
  REQUIRE_RIME_API(initialize);
  REQUIRE_RIME_API(deployer_initialize);
  REQUIRE_RIME_API(deploy_schema);
  REQUIRE_RIME_API(create_session);
  REQUIRE_RIME_API(find_session);
  REQUIRE_RIME_API(destroy_session);
  REQUIRE_RIME_API(commit_composition);
  REQUIRE_RIME_API(clear_composition);
  REQUIRE_RIME_API(get_commit);
  REQUIRE_RIME_API(free_commit);
  REQUIRE_RIME_API(get_context);
  REQUIRE_RIME_API(free_context);
  REQUIRE_RIME_API(get_status);
  REQUIRE_RIME_API(free_status);
  REQUIRE_RIME_API(set_option);
  REQUIRE_RIME_API(get_current_schema);
  REQUIRE_RIME_API(select_schema);
  REQUIRE_RIME_API(get_input);
  REQUIRE_RIME_API(select_candidate);
  REQUIRE_RIME_API(select_candidate_on_current_page);
  REQUIRE_RIME_API(candidate_list_begin);
  REQUIRE_RIME_API(candidate_list_next);
  REQUIRE_RIME_API(candidate_list_end);
  REQUIRE_RIME_API(set_input);
  REQUIRE_RIME_API(change_page);

#undef REQUIRE_RIME_API
  return 1;
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

static int strings_equal(const char* lhs, const char* rhs) {
  if (!lhs || !rhs) {
    return lhs == rhs;
  }
  return strcmp(lhs, rhs) == 0;
}

static void shutdown_runtime(void) {
  if (g_runtime.initialized && RIME_API_HAS(g_runtime.api, finalize)) {
    g_runtime.api->finalize();
  }
  if (g_runtime.dylib) {
    dlclose(g_runtime.dylib);
  }
  free(g_runtime.shared_data_dir);
  free(g_runtime.user_data_dir);
  free(g_runtime.app_name);
  free(g_runtime.distribution_version);
  free(g_runtime.deployed_schema_file);
  memset(&g_runtime, 0, sizeof(g_runtime));
}

static void shutdown_runtime_at_exit(void) {
  pthread_mutex_lock(&g_runtime_mutex);
  shutdown_runtime();
  pthread_mutex_unlock(&g_runtime_mutex);
}

static int ensure_runtime_initialized(const char* shared_data_dir,
                                      const char* user_data_dir,
                                      const char* app_name,
                                      const char* distribution_version) {
  const char* resolved_app_name =
      app_name && app_name[0] ? app_name : "rime.leftio";
  const char* resolved_distribution_version =
      distribution_version && distribution_version[0]
          ? distribution_version
          : "0.1.0";
  if (g_runtime.initialized) {
    if (strings_equal(g_runtime.shared_data_dir, shared_data_dir) &&
        strings_equal(g_runtime.user_data_dir, user_data_dir) &&
        strings_equal(g_runtime.app_name, resolved_app_name) &&
        strings_equal(g_runtime.distribution_version,
                      resolved_distribution_version)) {
      return 1;
    }
    if (g_runtime.ref_count > 0) {
      set_last_error(
          "cannot switch rime data directories while sessions are active.");
      return 0;
    }
    shutdown_runtime();
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
  if (!validate_required_api(api)) {
    dlclose(dylib);
    return 0;
  }

  char* shared_data_dir_copy = duplicate_string(shared_data_dir);
  char* user_data_dir_copy = duplicate_string(user_data_dir);
  char* app_name_copy = duplicate_string(resolved_app_name);
  char* distribution_version_copy =
      duplicate_string(resolved_distribution_version);
  if (!shared_data_dir_copy || !user_data_dir_copy || !app_name_copy ||
      !distribution_version_copy) {
    free(shared_data_dir_copy);
    free(user_data_dir_copy);
    free(app_name_copy);
    free(distribution_version_copy);
    set_last_error("failed to retain rime runtime paths.");
    dlclose(dylib);
    return 0;
  }

  RimeTraits traits = {0};
  RIME_STRUCT_INIT(RimeTraits, traits);
  // librime copies most trait values into its deployer, but glog retains the
  // app_name pointer passed to InitGoogleLogging(). Swift callers provide
  // these arguments through withCString, so every trait pointer must refer to
  // storage owned by the process-wide runtime before setup() is called.
  traits.shared_data_dir = shared_data_dir_copy;
  traits.user_data_dir = user_data_dir_copy;
  traits.distribution_name = "LeftIO";
  traits.distribution_code_name = "leftio";
  traits.distribution_version = distribution_version_copy;
  traits.app_name = app_name_copy;
  traits.min_log_level = 1;

  char prebuilt_data_dir[1024] = {0};
  char prebuilt_default[1024] = {0};
  int prebuilt_data_dir_length = snprintf(prebuilt_data_dir,
                                          sizeof(prebuilt_data_dir),
                                          "%s/build",
                                          shared_data_dir);
  int prebuilt_default_length = snprintf(prebuilt_default,
                                         sizeof(prebuilt_default),
                                         "%s/default.yaml",
                                         prebuilt_data_dir);
  int has_prebuilt_workspace =
      prebuilt_data_dir_length >= 0 &&
      (size_t)prebuilt_data_dir_length < sizeof(prebuilt_data_dir) &&
      prebuilt_default_length >= 0 &&
      (size_t)prebuilt_default_length < sizeof(prebuilt_default) &&
      access(prebuilt_default, R_OK) == 0;
  if (has_prebuilt_workspace) {
    // Old releases deployed into user_data_dir/build. Resolve both the primary
    // and fallback compiled resources directly from the immutable packaged
    // workspace so stale or partially-written user build files can never
    // override it. User dictionaries remain in user_data_dir and are
    // unaffected.
    traits.prebuilt_data_dir = prebuilt_data_dir;
    traits.staging_dir = prebuilt_data_dir;
  }

  api->setup(&traits);
  api->initialize(&traits);
  // deploy_schema() depends on the deployer module set. Loading those modules
  // is cheap and does not run maintenance or write the staging directory.
  api->deployer_initialize(&traits);

  g_runtime.dylib = dylib;
  g_runtime.api = api;
  g_runtime.initialized = 1;
  g_runtime.shared_data_dir = shared_data_dir_copy;
  g_runtime.user_data_dir = user_data_dir_copy;
  g_runtime.app_name = app_name_copy;
  g_runtime.distribution_version = distribution_version_copy;
  static int registered_exit_cleanup = 0;
  if (!registered_exit_cleanup) {
    atexit(shutdown_runtime_at_exit);
    registered_exit_cleanup = 1;
  }
  set_last_error(NULL);
  return 1;
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
  if (!g_runtime.api || !schema_id || !schema_id[0]) {
    set_last_error("rime schema deployment arguments are invalid.");
    return 0;
  }

  char schema_file[1024] = {0};
  int length = 0;
  if (shared_data_dir && shared_data_dir[0]) {
    length = snprintf(schema_file,
                      sizeof(schema_file),
                      "%s/%s.schema.yaml",
                      shared_data_dir,
                      schema_id);
  } else {
    length = snprintf(schema_file, sizeof(schema_file), "%s.schema.yaml", schema_id);
  }
  if (length < 0 || (size_t)length >= sizeof(schema_file)) {
    set_last_error("rime schema path is too long.");
    return 0;
  }
  if (strings_equal(g_runtime.deployed_schema_file, schema_file)) {
    return 1;
  }

  char prebuilt_schema[1024] = {0};
  char prebuilt_prism[1024] = {0};
  char prebuilt_table[1024] = {0};
  int schema_length = snprintf(prebuilt_schema,
                               sizeof(prebuilt_schema),
                               "%s/build/%s.schema.yaml",
                               shared_data_dir,
                               schema_id);
  int prism_length = snprintf(prebuilt_prism,
                              sizeof(prebuilt_prism),
                              "%s/build/%s.prism.bin",
                              shared_data_dir,
                              schema_id);
  int table_length = snprintf(prebuilt_table,
                              sizeof(prebuilt_table),
                              "%s/build/%s.table.bin",
                              shared_data_dir,
                              schema_id);
  int prebuilt_paths_fit =
      schema_length >= 0 && (size_t)schema_length < sizeof(prebuilt_schema) &&
      prism_length >= 0 && (size_t)prism_length < sizeof(prebuilt_prism) &&
      table_length >= 0 && (size_t)table_length < sizeof(prebuilt_table);
  int has_prebuilt_schema =
      prebuilt_paths_fit && access(prebuilt_schema, R_OK) == 0 &&
      access(prebuilt_prism, R_OK) == 0 && access(prebuilt_table, R_OK) == 0;

  if (has_prebuilt_schema) {
    // The immutable application bundle already contains a complete compiled
    // workspace. Starting Rime maintenance here would write user_data/build
    // while create_session() reads it, so a cold first session could observe a
    // partially-written YAML file. Keep this path read-only and let Rime use
    // shared_data_dir/build as the resolver's fallback root.
    char* deployed_schema_file = duplicate_string(schema_file);
    if (!deployed_schema_file) {
      set_last_error("failed to retain prebuilt rime schema path.");
      return 0;
    }
    free(g_runtime.deployed_schema_file);
    g_runtime.deployed_schema_file = deployed_schema_file;
    return 1;
  }

  if (!RIME_API_HAS(g_runtime.api, deploy_schema)) {
    set_last_error("loaded librime cannot deploy schemas.");
    return 0;
  }
  if (!g_runtime.api->deploy_schema(schema_file)) {
    set_last_errorf("failed to deploy rime schema: %s", schema_file);
    return 0;
  }

  char* deployed_schema_file = duplicate_string(schema_file);
  if (!deployed_schema_file) {
    set_last_error("failed to retain deployed rime schema path.");
    return 0;
  }
  free(g_runtime.deployed_schema_file);
  g_runtime.deployed_schema_file = deployed_schema_file;

  return 1;
}

OneHandRimeBridgeHandle* OneHandRimeBridgeCreate(const char* shared_data_dir,
                                                 const char* user_data_dir,
                                                 const char* schema_id,
                                                 const char* app_name,
                                                 const char* distribution_version) {
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

  pthread_mutex_lock(&g_runtime_mutex);
  if (!ensure_runtime_initialized(shared_data_dir,
                                  user_data_dir,
                                  app_name,
                                  distribution_version)) {
    pthread_mutex_unlock(&g_runtime_mutex);
    return NULL;
  }

  if (!deploy_schema(shared_data_dir, schema_id)) {
    pthread_mutex_unlock(&g_runtime_mutex);
    return NULL;
  }

  RimeSessionId session_id = g_runtime.api->create_session();
  if (!session_id) {
    set_last_error("failed to create rime session.");
    pthread_mutex_unlock(&g_runtime_mutex);
    return NULL;
  }

  if (!g_runtime.api->select_schema(session_id, schema_id)) {
    g_runtime.api->destroy_session(session_id);
    set_last_errorf("failed to select rime schema: %s", schema_id);
    pthread_mutex_unlock(&g_runtime_mutex);
    return NULL;
  }

  OneHandRimeBridgeHandle* handle = (OneHandRimeBridgeHandle*)calloc(1, sizeof(OneHandRimeBridgeHandle));
  if (!handle) {
    g_runtime.api->destroy_session(session_id);
    set_last_error("failed to allocate rime bridge handle.");
    pthread_mutex_unlock(&g_runtime_mutex);
    return NULL;
  }

  handle->session_id = session_id;
  g_runtime.ref_count += 1;
  set_last_error(NULL);
  pthread_mutex_unlock(&g_runtime_mutex);
  return handle;
}

void OneHandRimeBridgeDestroy(OneHandRimeBridgeHandle* handle) {
  if (!handle) {
    return;
  }
  pthread_mutex_lock(&g_runtime_mutex);
  if (g_runtime.api && g_runtime.initialized && handle->session_id) {
    g_runtime.api->destroy_session(handle->session_id);
  }
  free(handle);
  if (g_runtime.ref_count > 0) {
    g_runtime.ref_count -= 1;
  }
  // Keep librime initialized while the input-method process lives. A new
  // controller can now create a session without repeating deployment.
  pthread_mutex_unlock(&g_runtime_mutex);
}

const char* OneHandRimeBridgeGetLastError(void) {
  return g_last_error;
}

bool OneHandRimeBridgeSetInput(OneHandRimeBridgeHandle* handle, const char* input) {
  if (!validate_handle(handle)) {
    return false;
  }
  if (!RIME_API_HAS(g_runtime.api, set_input)) {
    set_last_error("loaded librime cannot replace session input.");
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
  if (!RIME_API_HAS(g_runtime.api, select_candidate_on_current_page)) {
    set_last_error("loaded librime cannot select a page-relative candidate.");
    return false;
  }
  if (!g_runtime.api->select_candidate_on_current_page(handle->session_id, index)) {
    set_last_error("failed to select rime candidate.");
    return false;
  }
  set_last_error(NULL);
  return true;
}

bool OneHandRimeBridgeSelectCandidateAtIndex(OneHandRimeBridgeHandle* handle,
                                             size_t index) {
  if (!validate_handle(handle)) {
    return false;
  }
  if (!RIME_API_HAS(g_runtime.api, select_candidate)) {
    set_last_error("loaded librime cannot select an absolute candidate index.");
    return false;
  }
  if (!g_runtime.api->select_candidate(handle->session_id, index)) {
    set_last_error("failed to select rime candidate by absolute index.");
    return false;
  }
  set_last_error(NULL);
  return true;
}

bool OneHandRimeBridgeChangePage(OneHandRimeBridgeHandle* handle, bool backward) {
  if (!validate_handle(handle)) {
    return false;
  }
  if (!RIME_API_HAS(g_runtime.api, change_page) ||
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
  if (!RIME_API_HAS(g_runtime.api, get_input)) {
    set_last_error("loaded librime cannot read session input.");
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
  if (context.menu.num_candidates > 0 &&
      index < (size_t)context.menu.num_candidates) {
    text = duplicate_string(context.menu.candidates[index].text);
  }
  g_runtime.api->free_context(&context);
  return text;
}

char* OneHandRimeBridgeCopyCandidateListAtIndex(OneHandRimeBridgeHandle* handle,
                                                size_t index) {
  if (!validate_handle(handle)) {
    return NULL;
  }

  RimeCandidateListIterator iterator = {0};
  if (!RIME_API_HAS(g_runtime.api, candidate_list_begin) ||
      !RIME_API_HAS(g_runtime.api, candidate_list_next) ||
      !RIME_API_HAS(g_runtime.api, candidate_list_end) ||
      !g_runtime.api->candidate_list_begin(handle->session_id, &iterator)) {
    return NULL;
  }

  char* text = NULL;
  for (size_t current_index = 0; current_index <= index; ++current_index) {
    if (!g_runtime.api->candidate_list_next(&iterator)) {
      break;
    }

    if (current_index == index) {
      text = duplicate_string(iterator.candidate.text);
      break;
    }
  }

  g_runtime.api->candidate_list_end(&iterator);
  return text;
}

void OneHandRimeBridgeFreeString(char* value) {
  free(value);
}
