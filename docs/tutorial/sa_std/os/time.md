# Time (时间与日期)

处理系统时间、单调时钟与休眠。

## 导入
```sa
@import "sa_std/time.sa"
```

## 核心宏与用法

### `TIME_NOW_UNIX_MS %out_u64`
获取当前的 UNIX 毫秒时间戳。

```sa
@import "sa_std/time.sa"

@main() -> i32:
L_ENTRY:
    EXPAND TIME_NOW_UNIX_MS timestamp
    // timestamp 即为当前毫秒级时间戳
    !timestamp
    return 0
```

### `TIME_SLEEP_MS %ms_u64`
使当前线程休眠指定的毫秒数。底层使用系统调用并处理信号中断。

```sa
// 休眠 1000 毫秒（1 秒）
EXPAND TIME_SLEEP_MS 1000
```