#include <stdint.h>
#include <stdio.h>

static int32_t g_handle = 41;

extern int32_t ffi_handle_roundtrip(void);

int32_t handle_new(void) {
    return g_handle;
}

int32_t handle_get(int32_t handle) {
    return handle + 1;
}

void handle_drop(int32_t handle) {
    (void)handle;
}

int main(void) {
    int32_t value = ffi_handle_roundtrip();
    printf("%d\n", value);
    return value == 42 ? 0 : 1;
}
