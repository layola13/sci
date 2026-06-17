# 182 - Mmap Memory Mapping

## 目标特性 (Target Feature)
展示文件描述符、映射指针和映射长度如何作为同一份资源状态被显式管理。

## 当前示例 (Current Demo Shape)
1. `main.sa` 先打开 `/dev/zero`，再通过 `mmap` 得到 4-byte 视图，读取首字节后执行 `munmap` 和 `close`。
2. SA 版本额外把原始指针包装成 `mmap_view` 的借用视图，强调裸指针到安全视图的边界。
3. 成功路径要求“首字节为 0、unmap 成功、close 成功、fd 非 0”，最后输出 `4`。

