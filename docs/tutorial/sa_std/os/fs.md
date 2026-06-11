# Fs (文件系统)

SA 的文件系统模块提供了安全的文件和目录操作原语。最新版本在底层引入了严格的安全沙箱机制：无论是文件读取还是目录拷贝，都会自动校验是否存在跨目录（如 `../` 逃逸）或不安全的符号链接跟随（Symbolic Link Escape）。

## 导入
```sa
@import "sa_std/fs.sa"
```

## 核心宏与用法

### `FS_READ_TO_STRING %out_ok, %out_str, %path_ptr`
一次性将整个文件读取为动态字符串。内部包含防超大文件导致 OOM 的容错机制。

```sa
@import "sa_std/fs.sa"

@main() -> i32:
L_ENTRY:
    file_path = utf8:"/etc/hosts"
    EXPAND FS_READ_TO_STRING ok, content_str, &file_path
    br ok -> L_READ_OK, L_READ_FAIL

L_READ_OK:
    // 读取成功，content_str 为 String 容器
    EXPAND STRING_LEN len, content_str
    !len
    EXPAND STRING_FREE content_str
    !ok
    return 0

L_READ_FAIL:
    !ok
    !content_str
    return 1
```

### `FS_WRITE %out_ok, %path_ptr, %data_slice`
将字节切片安全写入文件。

### `FS_OPEN_DIR %out_ok, %out_dir, %path_ptr`
打开一个目录句柄，可用于后续的遍历 (`FS_ITER_DIR`) 等操作。在底层实现中，这会使用 `NO_FOLLOW` 模式以防止恶意软链接导致的文件系统越狱。