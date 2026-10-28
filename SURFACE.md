# SURFACE — `sa build-js` 导出面普查（.d.ts 发射的输入事实）

普查基点：sci main `fc638db5`。依据：`src/emit_js.zig` 源码逐行核对 +
探针实测（`probes/probe_types.sa` / `probes/probe_edge.sa`，用主树已构建
`sa` 以 build-js 生成产物后 node 实跑，2026-10-28）。没有实测或源码依据的
形状不列入。

## 1. 导出面全集（按格式分列——两格式不对称，必须逐格式镜像）

`emitJsToString`（emit_js.zig）的发射顺序与导出方式决定以下全集：

| # | 形状 | ESM | CJS | 运行时表示 |
|---|---|---|---|---|
| S1 | 用户函数（非 extern 任务：`@fn` 定义、`@export`、`@ffi_wrapper`、`@test`） | `export function` 逐个声明 | 函数声明 + 列入 `module.exports` | 见 §2 类型表 |
| S2 | `#npm_bind` extern 的编组 wrapper（call/ctor/method/get） | `export function` | **不导出**（wrapper 存在于模块内，但 exports 循环跳过 extern 任务） | SA 签名原样（参数为 SA 侧值：数字/句柄/地址），见 §3 |
| S3 | 运行时助手（固定 8 个） | 尾部 `export { … }` | 列入 `module.exports` | 见 §4 |
| S4 | extern 宿主 shim（sa_print_bytes、net shims、`sa_js_*` 内建等） | 不导出（模块内 `function`） | 不导出 | — |
| S5 | extern trap 存根（未绑定 extern） | 不导出（模块内 `function`，调用即 trap） | 不导出 | — |
| S6 | 模块级 const 声明（数据/vtable 槽位地址） | 不导出（`const __sa_const_*`，模块内） | 不导出 | — |

实测佐证：
- probe_types（20 个 @export 函数）ESM 与 CJS 的导出键集合完全一致：
  20 个函数名 + 8 个助手。
- demos/rosetta/965（npm 句柄）ESM 导出 = { main, ee_new, ee_max_listeners }
  + 8 助手；CJS 导出 = { main } + 8 助手（ee_new / ee_max_listeners 缺席）
  —— S2 的不对称属实。**这是既有产物行为，本线只镜像、已在终报登记，
  不在本线修改 exports 语义。**
- `@test` 函数同样被发射并导出（probe_edge：`@test "sample test fn"`
  → `export function sample_test_fn()`），与 S1 同列处理。

命名：JS 名由 `jsFuncName`/`jsIdent` 生成（非法字符→`_`、保留字与
发射器保留名（`__sa*`/`__SA*`/`r<digits>`）→尾加 `$`）。.d.ts 发射器
复用同一对函数，保证声明名与产物名逐字一致。同名冲突（净化后重名）
在 JS 里由后声明者覆盖（函数提升语义），.d.ts 只发最后一个签名。

## 2. 用户函数（S1）的边界表示——探针实测表

探针：`probe_types.sa`（恒等/回环/字面量/内存往返各类 @export），
build-js（ESM）后 node 调用，记录 `typeof` 与值。

| SA 类型 | 实测输入 | 实测输出 | 结论 |
|---|---|---|---|
| i1 | number | number（0/1） | number |
| i8/i16/i32 | number | number | number |
| u8/u16/u32 | number | number | number |
| f32/f64 | number | number | number |
| i64 | number 或 bigint 均可 | **随表示流动**：恒等返回 number 入→number 出、bigint 入→bigint 出；i64 加法同理；宽字面量 5000000000 返回 number；**经线性内存往返（store/load i64）恒返回 bigint** | `number \| bigint` 是唯一健全类型 |
| u64 | number 或 bigint 均可 | 同上（pair_len 实测双入双出） | `number \| bigint` |
| ptr | number 或 bigint 均可 | 恒等回传传入表示；内部产生的地址（alloc/常量）为 number；装箱函数指针为 bigint（`__sa_fnptr` 返回 `__SA_FN_BASE + BigInt(i)`）；`__sa_addr` 对两类入参都归一 | `number \| bigint` |
| void | — | **number 0**（emitReturnStmt 对无操作数 return 发射 `return 0;`，probe `noop()` 实测 `number 0`） | 见映射表裁定 |
| fallible `T!` | — | 普通对象 `{s: 0, v: <T>}`（成功）；`void!` 为 `{s: 0}`。失败对象 `{s: ≠0}` 由被调用方的 fallible 对象经 `?` 传播原样返回（emitLinearInstruction 的 try_/early_return 发射 `return __t;`） | 运行时形状 = `{s, v}` 双槽对象；TS 映射裁定见 DTS_EMIT_DESIGN.md（判别联合被 tsc 窄化实测否决，用结构式） |
| v128 | **无表示**：恒等函数对 number/bigint/数组等任意 JS 值原样透传（probe_edge 实测），发射器无 v128 运行时表示（emit_js.zig 内无 v128 编组代码，仅宽度跟踪表提及） | 同左 | **未映射**：.d.ts 发射器对导出面含 v128 参/返回的函数报错指名（见映射表） |
| blob_handle（用户函数参/返回） | 句柄整数 | 产生方恒为运行时 `__sa_jsh_new` → **bigint**（`gen * 2^32 + (idx+1)`）；解码 `__sa_jsh_decode` 接受 number 与 bigint | `number \| bigint`（产生值恒 bigint，注释标明） |

参数传递通则：JS 函数形参即 SA 形参名（jsIdent 净化），按声明顺序
一一对应；`(ptr, len)` 字符串形在**用户函数**边界上不存在特殊编组
——就是两个普通参数（ptr + 整数），逐个按类型映射。字符串编组只发生
在 S2 wrapper 内部（SA→JS 方向），不改变 wrapper 自身的边界签名。

## 3. npm wrapper（S2）的边界表示

wrapper 的 JS 签名 = 对应 extern 的 SA 签名（形参名与顺序一致，
含 string-out 尾参组 `(out_ptr, out_cap, &out_len)` 原样在内）。
返回编组（emitNpmWrapper 源码核对）：

| wrapper 形态 | SA 返回 | JS 实际返回 |
|---|---|---|
| ctor | blob_handle | bigint 句柄（`__sa_jsh_new`） |
| call/method/get + string-out 签名 | i32 状态 | number 状态码（0 或 SA_JS_STR_TOO_LONG=1） |
| call/method/get | blob_handle | bigint 句柄 |
| call/method/get | void | **undefined**（函数体无 return 语句）——与 S1 的 void→0 不同 |
| call/method/get | ptr | number（`__sa_num` 归一） |
| call/method/get | 数值 | number（`__sa_num` 归一；thenable/非数值 → trap） |

注：emitNpmWrapper 不处理 `return_fallible`（返回裸值）；若某 npm extern
声明为 fallible，其 wrapper 边界仍是裸值——.d.ts 按 wrapper 实际行为
映射、不套 fallible 形状（映射表裁定，属既有发射器行为）。

回调（DESIGN §5 的 queue-drain）：`sa_js_make_callback` /
`sa_js_callback_poll` / `sa_js_value_release` 是 extern 内建（S4，
不导出），回调在导出面上只以 blob_handle 参数出现，无独立形状。

## 4. 运行时助手（S3）的表示

| 名称 | 运行时定义（writeRuntimeHeader） | 表示 |
|---|---|---|
| `__sa_memory` | `new ArrayBuffer(__SA_MEM_BYTES)` | ArrayBuffer |
| `__sa_view` | `new DataView(__sa_memory)` | DataView |
| `__sa_u8` | `new Uint8Array(__sa_memory)` | Uint8Array |
| `__sa_alloc(size)` | 返回 `ptr \| 0` | (number) => number |
| `__sa_free(ptr)` | 返回 0 | (ptr) => number |
| `__sa_salloc(size)` | 返回地址 | (number) => number |
| `__sa_sfree(ptr)` | 返回 0 | (ptr) => number |
| `__sa_mem_used()` | 返回已用字节数 | () => number |

## 5. 明确不在导出面的东西（不发明）

- SLA 结构体/枚举等复合类型：FunctionSig 只含 PrimType，边界上只有
  ptr（地址）+ 布局由调用方自理，无可声明的复合形状。
- Promise：同步形态下 thenable 一律 trap（wrapper 与句柄路径均然），
  导出面无 Promise 形状。
- 字符串：无独立 string 原语类型；见 §2 通则。
