# Env 与 Process

提供了与操作系统环境变量交互及创建子进程的功能。

## 导入
```sa
@import "sa_std/env.sa"
@import "sa_std/process.sa"
```

## Env 核心宏

### `ENV_GET %out_ok, %out_str, %key_slice`
安全读取环境变量。

```sa
@import "sa_std/env.sa"
@import "sa_std/core/slice.sa"

@main() -> i32:
L_ENTRY:
    key = utf8:"PATH"
    EXPAND SLICE_NEW key_slice, &key, 4
    
    EXPAND ENV_GET ok, val_str, key_slice
    br ok -> L_FOUND, L_NOT_FOUND
    
L_FOUND:
    EXPAND STRING_FREE val_str
    !ok
    !key_slice
    return 0

L_NOT_FOUND:
    !val_str
    !ok
    !key_slice
    return 1
```

### `ENV_SET %out_ok, %key_slice, %val_slice`
设定环境变量。

## Process 核心宏

### `PROCESS_SPAWN %out_ok, %out_proc, %cmd_slice, %args_vec`
拉起一个子进程。为了避免安全注入，底层系统对于向外部系统如 `git clone` 等危险调用的命令行参数和凭证挂载具有严密的检查机制。

### `PROCESS_WAIT %out_ok, %out_exit_code, %proc_reg`
等待子进程结束并获取状态。