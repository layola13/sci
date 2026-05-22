# SA-ASM 热插拔插件系统 (Hot-Pluggable Plugin System)

> **重要说明**：早期 SA-ASM 采用的是编译期静态注册机制。现已全面进化为基于 C-ABI 和 `.so`/`.dll` 的**动态热插拔运行时加载机制**。本指南将指导你如何开发、注册和调用一个 SA 插件。

## 1. 架构目标与优势

SA-ASM 主体只保留核心的所有权编译器 (Referee) 和指令执行引擎，而所有的扩展功能（例如数据库访问、HTTP 网络、大模型转换 `llvm2sa` 等）全部通过动态库挂载。

- **极速热重载 (Hot Reload)**：你可以在不重启 SA 解释器进程的情况下，直接替换后端的 `.so` 文件。下一个请求将自动使用新版本的插件。
- **内存安全隔离**：插件代码即便是用 C/Zig 写的产生段错误 (Segfault) 崩溃，通过隔离机制（针对不同平台可选的子进程隔离或严格气闸舱）也不会轻易带崩主节点。
- **多语言开发**：只要能导出标准 C-ABI (`stdcall` / `cdecl`) 函数的语言（C, Rust, Zig, Go 等），都能为 SA 编写插件。

## 2. 插件发现与生命周期

### 2.1 目录结构与挂载点
SA-ASM 在启动时，会扫描当前工作区下的 `plugins/` 目录以及 `sa.mod` 中声明的依赖路径。
一个合法的插件必须包含：
1. **`.so` / `.dll` / `.dylib` 文件**：编译后的动态库。
2. **`.sai` 文件**：插件向 SA 导出的函数签名接口。

### 2.2 生命周期 (Lifecycle)
当插件被第一次调用时：
1. **Load**: SA 调用系统 `dlopen` 加载库。
2. **Handshake**: SA 查找动态库中必须导出的符号 `plugin_descriptor`，以验证 ABI 版本号是否匹配当前 SA 引擎（防止崩溃）。
3. **Bind**: SA 读取 `.sai` 文件，将你在其中声明的 `@extern` 函数与动态库中 `dlsym` 查找到的函数指针对接。
4. **Execute**: 执行业务代码。
5. **Unload**: 达到闲置 TTL 或被显式卸载时，调用 `dlclose`。

## 3. 开发实战：编写一个 "Math Plugin"

我们将用 Zig 编写一个简单的插件，并将其挂载到 SA 中。

### 3.1 编写后端动态库 (Zig 示例)

```zig
// math_plugin.zig
const std = @import("std");

// 1. 导出插件描述符 (必须有，用于 ABI 握手)
export const plugin_descriptor = struct {
    abi_version: u32 = 1,
    name: [*c]const u8 = "math_plugin",
    author: [*c]const u8 = "MyCompany",
}{};

// 2. 导出业务函数 (必须使用 C-ABI)
// 假设这是个提供极速矩阵乘法的函数
export fn sa_math_matrix_multiply(a_ptr: [*]f32, b_ptr: [*]f32, out_ptr: [*]f32, size: u32) i32 {
    // ... 高性能 SIMD 矩阵乘法 ...
    
    // 返回 0 表示成功，非 0 表示状态码 (用于 SA 的 ? 操作符)
    return 0;
}
```

编译为动态库：
```bash
zig build-lib math_plugin.zig -dynamic -O ReleaseFast
# 将生成 libmath_plugin.so (Linux) 或 math_plugin.dll (Windows)
```

### 3.2 编写接口文件 (`math_plugin.sai`)
在同级目录下创建一个接口声明文件，告诉 SA 编译器这个库里有什么。

```sa
// 注意：参数必须与 C ABI 严格匹配，所有指针对应 SA 的 ptr 类型
@extern sa_math_matrix_multiply(*a: ptr, *b: ptr, *out: ptr, size: u32) -> i32!
```

### 3.3 在 SA-ASM 中调用
现在，你可以在业务代码中安全地调用它了（必须在 `@ffi_wrapper` 中）：

```sa
@ffi_wrapper do_math() -> i32! {
    // ... 假设已分配内存并初始化了矩阵 a, b, out ...
    raw_a = *a
    raw_b = *b
    raw_out = *out
    
    // 调用插件！SA 引擎会自动按需懒加载 (Lazy Load) 该动态库
    res = call @sa_math_matrix_multiply(raw_a, raw_b, raw_out, 1024)
    _ = ? res
    
    return 0
}
```

## 4. 插件的 Zero-Trust 权限管控
在 SA 的世界里，你安装了一个第三方的 `libimage_parser.so` 插件，SA 是如何防止它偷偷窃取数据的呢？

SA 通过 FFI 气闸舱限制：
1. SA 引擎会拦截所有的 Syscall 请求。如果该插件未在 `sa.mod` 的 `grants` 列表中申请 `fs_read` 或 `net_tx`，当插件试图在底层调用 `open` 或 `connect` 系统调用时，主进程的沙箱机制（Linux 下为 seccomp-bpf，或通过 ptrace）会直接拦截并截杀该插件。
2. 开发者明确知道：插件只能访问你通过指针 (`raw_a` / `raw_b`) 传给它的一小块隔离内存，它无法窃取主引擎的堆数据。

---
**设计结论**：这种基于 C-ABI + 接口文件映射的热插拔模型，彻底将 SA-ASM 从一个单体编译器解放为一个灵活的**微内核计算引擎**。
