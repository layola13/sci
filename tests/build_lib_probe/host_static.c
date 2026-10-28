// Acceptance host for the static form: link the built archive directly
// and call the contract functions through their plain C declarations in
// the generated header (compiled with BLIB_STATIC so BLIB_API expands to
// nothing, per the one-header/two-forms rule).
#include <stdint.h>
#include <stdio.h>

#include "blib.h"

int main(void) {
    printf("abi=%u\n", blib_abi_version());
    int64_t sum = bl_add(19, 23);
    printf("add=%lld\n", (long long)sum);
    const uint8_t msg[5] = { 'h', 'e', 'l', 'l', 'o' };
    uint64_t checksum = bl_checksum((void *)msg, 5);
    printf("checksum=%llu\n", (unsigned long long)checksum);
    uint64_t out = 0;
    int32_t status = bl_answer(&out);
    printf("answer status=%d out=%llu\n", status, (unsigned long long)out);
    if (blib_abi_version() == BLIB_ABI_VERSION && sum == 42 && checksum == 532 && status == 0 && out == 42) {
        printf("STATIC_OK\n");
        return 0;
    }
    printf("STATIC_MISMATCH\n");
    return 1;
}
