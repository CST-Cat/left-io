#ifndef C_RIME_BRIDGE_H
#define C_RIME_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OneHandRimeBridgeHandle {
    uintptr_t session_id;
} OneHandRimeBridgeHandle;

OneHandRimeBridgeHandle* OneHandRimeBridgeCreate(const char* shared_data_dir,
                                                 const char* user_data_dir,
                                                 const char* schema_id,
                                                 const char* app_name);
void OneHandRimeBridgeDestroy(OneHandRimeBridgeHandle* handle);

const char* OneHandRimeBridgeGetLastError(void);

bool OneHandRimeBridgeSetInput(OneHandRimeBridgeHandle* handle,
                               const char* input);
bool OneHandRimeBridgeCommitComposition(OneHandRimeBridgeHandle* handle);
void OneHandRimeBridgeClearComposition(OneHandRimeBridgeHandle* handle);
bool OneHandRimeBridgeSelectCandidateOnCurrentPage(
    OneHandRimeBridgeHandle* handle,
    size_t index);
bool OneHandRimeBridgeSelectCandidateAtIndex(OneHandRimeBridgeHandle* handle,
                                             size_t index);
bool OneHandRimeBridgeChangePage(OneHandRimeBridgeHandle* handle,
                                 bool backward);
bool OneHandRimeBridgeIsAsciiMode(OneHandRimeBridgeHandle* handle);
bool OneHandRimeBridgeSetAsciiMode(OneHandRimeBridgeHandle* handle,
                                   bool enabled);

char* OneHandRimeBridgeCopyCommitText(OneHandRimeBridgeHandle* handle);
char* OneHandRimeBridgeCopyCurrentSchemaId(OneHandRimeBridgeHandle* handle);
char* OneHandRimeBridgeCopyInput(OneHandRimeBridgeHandle* handle);
char* OneHandRimeBridgeCopyPreedit(OneHandRimeBridgeHandle* handle);
size_t OneHandRimeBridgeCandidateCount(OneHandRimeBridgeHandle* handle);
char* OneHandRimeBridgeCopyCandidateAtIndex(OneHandRimeBridgeHandle* handle,
                                            size_t index);
char* OneHandRimeBridgeCopyCandidateListAtIndex(
    OneHandRimeBridgeHandle* handle,
    size_t index);
void OneHandRimeBridgeFreeString(char* value);

#ifdef __cplusplus
}
#endif

#endif
