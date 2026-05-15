# SA-ASM Rosetta Demos - Remaining To-Do List (49/200)

经过全量自动化测试，前 100 个核心 Demo 已经实现 100% 编译与运行双重通过。
这里列出了后 100 个 Demo 中尚未通过的 49 个，并按照**修复难度和架构优先级**进行了分类。

这些失败绝大多数是 SA-ASM 编译器（Referee）**正确合法的拦截**，你需要修改对应的 `main.saasm` 脚本以符合底层的物理所有权契约。

---

## 🔴 优先级 1：核心控制流与生命周期对齐 (Hard)
*这是最核心的编译器边界。修复这些问题需要对 SA-ASM 的 O(1) 掩码理论有深刻理解，确保每个分支和返回路径的寄存器账目绝对平衡。*

### PhiStateConflict (分支汇聚掩码不一致)
最常见的错误。不同的控制流到达同一个 Label（如循环末尾或 `if-else` 出口）时，携带的存活寄存器不一致。
- [ ] `103_labeled_break`
- [ ] `104_if_let_chains`
- [ ] `105_let_else`
- [ ] `107_refcell_dynamic_borrow`
- [ ] `108_atomic_spin_lock`
- [ ] `121_rwlock_reader_writer`
- [ ] `127_hazard_pointers`
- [ ] `129_seqlock_optimistic`
- [ ] `133_select_macro_race`
- [ ] `134_join_all_futures`
- [ ] `197_profile_guided_opt`

### UseAfterMove (悬挂指针/释放后访问)
寄存器被 `!` 清理或被 `^` 消费后，代码再次尝试去读取或衍生指针。
- [ ] `101_custom_drop`
- [ ] `132_pinning_and_unpin`
- [ ] `153_box_into_raw`
- [ ] `154_box_from_raw`
- [ ] `159_mem_forget_leak`
- [ ] `175_thiserror_macro_derive`
- [ ] `188_websocket_frame_parse`
- [ ] `190_base64_encode_simd`

### MemoryLeak & EarlyReturnLeak (寄存器泄漏)
在 `return` (或 `?` 提早返回) 之前，有局部的 `Active` 寄存器或结构体没有被 `!` 物理销毁。
- [ ] `135_async_streams`
- [ ] `140_yield_now_suspend`
- [ ] `166_specialization_fallback`
- [ ] `171_anyhow_dynamic_error`
- [ ] `172_eyre_color_eyre`
- [ ] `174_backtrace_capture`
- [x] `176_result_flattening`
- [ ] `180_try_trait_v2`
- [ ] `194_cfg_conditional_compilation`
- [ ] `195_build_script_codegen`
- [ ] `199_address_sanitizer_asan`

### BorrowConflict (违反读写互斥锁)
在母体已经被借用（且为 `Locked_Mut` 等状态）时，试图越权读写母体内存。
- [ ] `102_raii_guard`
- [ ] `193_attribute_macro_rewrite`

### FallthroughForbidden (非法穿透块)
SA-ASM 强制所有块必须显式结尾，不能自然滑落到下一个块。
- [ ] `146_never_type_fallback`
- [ ] `173_catch_unwind_panic`
- [ ] `177_unwrap_unwrap_err`
- [x] `178_panic_hook_override`
- [ ] `179_assert_macro_expansion`

---

## 🟡 优先级 2：气闸舱与 FFI 契约边界 (Medium)
*这些失败证明了 `@ffi_wrapper` 的强隔离性，你需要修改调用姿势以通过安检。*

### IllegalUnsafeContext (非法不安全上下文)
试图在非 `@ffi_wrapper` 函数中使用裸指针前缀 `*` 传参或调用原生指令。
- [ ] `181_file_descriptor_raii`
- [ ] `182_mmap_memory_mapping`
- [ ] `185_dynamic_lib_dlopen`

### CapabilityMismatch (调用签名掩码不符)
`call` 指令传入的参数前缀（`&`, `^`, `*`）与函数的 `@func(&ptr, ^ptr)` 定义签名不匹配。
- [ ] `183_signal_handling_setup`
- [ ] `184_pthread_spawn_join`

### FfiOwnershipViolation (FFI 越权)
试图让 C 语言环境 `!` 销毁或 `^` 霸占属于 SA-ASM 追踪状态的借用视图。
- [ ] `186_sqlite_c_api_binding`

---

## 🟢 优先级 3：语法细则与环境配置 (Easy)
*拼写错误或由于测试沙盒缺少对应模拟符号导致的失败。*

### RegisterRedefinition (寄存器重复定义)
SA-ASM 使用 SSA 单赋值模式，寄存器一旦定义不允许二次赋值（需分配新名字）。
- [ ] `189_protobuf_varint_decode`
- [ ] `191_macro_rules_ast_emit`

### UnknownRegister / Undefined Symbol (找不到符号)
拼写错误或 `sa_std` 尚未暴露出对应的方法桩。
- [ ] `115_opaque_pointers`
- [ ] `187_opengl_context_swap`
- [ ] `196_lto_link_time_opt`
- [ ] `198_control_flow_guard_cfi`

### 杂项
- [ ] `117_inline_assembly` (ForbiddenSyntax: 必须使用扁平宏，不能在块内带花括号 `{}`)
- [ ] `136_executor_task_queue` (RunFailed: 能够编译通过，但执行业务逻辑报错退出)

---

## 🟦 下一阶段：200~300 已手写完成 Demo 的能力路标

> 这部分不计入上面的 51/200 backlog。这里把 200~300 目录对应的能力簇整理成后续支持清单，方便按模块、契约、构建链和平台门禁推进。

### Bootstrap 与前端材料化
- [ ] `200_sa_asm_quine`：quine / bootstrapping、宏与属性重写、cfg 选择、构建链外移。

### 包系统与工作区
- [ ] `201~204`：package manifest、local/git/registry 依赖解析。
- [ ] `205~209`：循环依赖拒绝、版本决议、多个版本冲突、dev/build dependencies。
- [ ] `210~220`：workspace root / inheritance、feature flags、default features、target-specific deps、patch override、profile、metadata、multiple bins、dynamic lib package。

### 模块系统与导入解析
- [ ] `221~240`：relative/absolute import、visibility/private、reexport、namespace prefix、cyclic import detect、shadowing prevention、iface/layout separation、layout injection、stdlib prelude、directory module、conditional import、alias import、unused import lint、transitive dependency、extern grouping、inline submodule、path resolution order、version suffix isolation、entry point override。

### Contract 与 ABI
- [ ] `241~260`：layout stability、opaque struct、signature mismatch、vtable export、generic monomorph share、semver minor/major、FFI boundary trust、macro export、const export、resource ownership、error code mapping、callback registration、plugin system、allocator swap、panic handler propagate、log facade、TLS isolation、static init order、deprecated warning。

### Build 链与工具化
- [ ] `261~280`：build.rs codegen、bindgen header、asset bundling、env injection、custom linker script、pre/post compile hook、cross compile wasm/windows、custom sysroot、optimization passes、sanitizer flags、test harness、benchmark runner、doc generator、incremental caching、parallel compilation、reproducible builds、remote artifact caching、CI/CD integration。

### FFI 与外部链接
- [ ] `281~290`：system libc、static/dynamic C library、pkg-config、Objective-C framework、Rust staticlib integration、Zig export integration、C++ name mangling、opaque handle passing、callback thunk。

### 生态与目标平台
- [ ] `291~300`：WASM host imports / memory export、embedded no-OS、kernel module、eBPF bytecode、GPU PTX shader、game engine ECS、cryptography SIMD、LSP、registry publish。

### 平台门禁备注
- `285` 依赖 macOS 链路能力。
- `293~296` 属于平台/后端门禁项，优先级应低于通用包、模块、contract、build、FFI 基础能力。
- `297~300` 依赖前面几层打稳后再做生态级集成。
