#ifndef TimeBombCoreBridge_h
#define TimeBombCoreBridge_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct RustBuffer {
  uint8_t *ptr;
  uintptr_t len;
  uintptr_t cap;
} RustBuffer;

typedef void (*DartEventCallback)(uint8_t event_type, const char *json_payload);

bool tb_init_session(const char *user_id);
bool tb_register_event_callback(DartEventCallback callback);
bool tb_process_incoming_message(const uint8_t *data, size_t len);
RustBuffer tb_build_message(uint8_t instruction, uint8_t transport, const char *payload_json);
char *tb_get_session_state(void);
bool tb_reset_session(void);
char *tb_last_error_message(void);
void tb_free_rust_buffer(RustBuffer buffer);
void tb_free_c_string(char *ptr);

#endif
