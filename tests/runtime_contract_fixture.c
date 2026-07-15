#include <stdint.h>

#if defined(_WIN32)
#define SA_RUNTIME_EXPORT __declspec(dllexport)
#else
#define SA_RUNTIME_EXPORT __attribute__((visibility("default")))
#endif

SA_RUNTIME_EXPORT int32_t sa_runtime_contract_fixture(void) {
    return 0x5a17;
}
