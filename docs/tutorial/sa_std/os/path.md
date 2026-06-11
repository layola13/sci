# Path (路径处理)

提供用于处理系统文件路径的文本规则，包含解析、拼接、标准化等操作。

## 导入
```sa
@import "sa_std/path.sa"
```

## 核心宏与用法

### `PATH_JOIN %out_str, %base_slice, %append_slice`
安全拼接路径。会自动处理正反斜杠以及路径规范化。

```sa
@import "sa_std/path.sa"
@import "sa_std/core/slice.sa"

@main() -> i32:
L_ENTRY:
    base = utf8:"/var/log"
    append = utf8:"nginx/error.log"

    EXPAND SLICE_NEW base_slice, &base, 8
    EXPAND SLICE_NEW append_slice, &append, 15

    EXPAND PATH_JOIN full_path, base_slice, append_slice
    
    // full_path 就是一个合并完成的 String
    EXPAND STRING_FREE full_path
    
    !base_slice
    !append_slice
    return 0
```

### `PATH_IS_ABSOLUTE %out_bool, %path_slice`
判断路径是否是绝对路径。

### `PATH_CANONICALIZE %out_ok, %out_str, %path_slice`
解析出最准确的绝对物理路径，剔除所有的 `.` 与 `..`（常用于系统安全审查阶段）。如果解析途中遇到权限故障或非法前缀逃逸，会返回 `ok = 0`。