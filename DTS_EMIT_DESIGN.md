# DESIGN — `sa build-js --emit-dts`：JS 目标的 .d.ts 声明发射

定位：JS 目标的「出方向」——SA/SLA 编译出的 JS 库被 TS 项目带类型
消费。与 `sla convert`（.d.ts→.sai，入方向）互为镜像。普查事实见
`SURFACE.md`（同批交付）；本文件只做映射裁定与实现形态。

## 1. CLI 形态

跟随 build-js 既有惯例（`--format` 同级的可选开关）：

```
sa build-js <file> --emit-dts [-o <out.js>] [--format esm|cjs]
```

- 默认关：不带 `--emit-dts` 时 JS 产物与行为逐字节不变。
- 开启时：在写出 JS 产物之后，同目录写出声明产物，命名 = JS 产物
  去掉末尾扩展名 + `.d.ts`（`foo.js`→`foo.d.ts`、`foo.mjs`→`foo.d.ts`、
  `foo.cjs`→`foo.d.ts`）。
- 实现落点：发射器在 `src/emit_js.zig` 内新增
  `emitDtsToString` / `dtsPathForJsPath`，由 `emitJsToFile` 在
  `JsEmitOptions.emit_dts` 为真时调用——它需要复用的导出面收集器
  （collectFuncTasks / collectNpmImports / jsIdent / jsFuncName /
  npmStrOut）全部是 emit_js.zig 的文件私有函数，新模块反而要扩大
  公开面。CLI 接线只在 build-js 的参数解析与 executeBuildJs 透传
  一个 bool，不动任何共享层。

## 2. 类型映射表（SA PrimType → TS）

依据 SURFACE.md 的实测列裁定。参数与返回同表（差异处单注）。

| SA 类型 | TS 类型 | 依据 / 备注 |
|---|---|---|
| i1 | `number` | 实测 0/1 |
| i8, i16, i32 | `number` | 实测 |
| u8, u16, u32 | `number` | 实测 |
| f32, f64 | `number` | 实测 |
| i64 | `SaI64` = `number \| bigint` | 表示随路径流动：直通/加法保入参表示，内存往返回 bigint；单写 number 或 bigint 都是谎报 |
| u64 | `SaU64` = `number \| bigint` | 同上 |
| ptr | `SaPtr` = `number \| bigint` | 地址为 number，装箱函数指针为 bigint，`__sa_addr` 两收 |
| blob_handle | `SaHandle` = `number \| bigint` | 产生值恒为 bigint（代次打包）；解码两收，故入参亦用此别名 |
| void（用户函数 S1） | `number` | 实测 `noop()` 返回 0；注释与本表注明「SA void 在 JS 后端回 0，不要依赖该值」 |
| void（npm wrapper S2） | `void` | wrapper 函数体无 return，实为 undefined |
| fallible `T!`（仅 S1） | `SaFallible<T>` = `{ s: number; v: T }`（产物注释标明 v 仅在 s===0 时有意义） | 成功对象实测 `{s:0, v}`；失败对象由 callee 传播、v 缺席。曾试判别联合 `{s:0,v:T} \| {s:number, v?:undefined}`，tsc 5.9.3 实测否决：s 是非字面量数值判别式，`r.s === 0` 检查后两分支都保留、v 仍为 `T \| undefined`，自然写法过不了检；故用结构式，与 SA 侧 fallible 值（s、v 双槽）的表示一致 |
| fallible `void!`（仅 S1） | `{ s: number }` | 实测 `{s:0}` |
| 运行时助手 S3 | 逐个固定声明（ArrayBuffer / DataView / Uint8Array / 三个 alloc 系函数 / mem_used） | SURFACE §4 |

别名（SaI64/SaU64/SaPtr/SaHandle/SaFallible）只在产物实际用到时才
在 .d.ts 头部发射，避免空声明。别名是普通 `export type`，消费者可
直接引用。

## 3. 未映射清单（发射器报错指名，禁止静默 `any`）

| 形状 | 处置 |
|---|---|
| v128 出现在导出面函数的参数或返回 | 发射失败：`error.UnsupportedDtsType`，错误上下文指名函数与 `v128`（SURFACE §2：JS 后端无 v128 表示，恒等透传任意 JS 值，无从声明） |

除 v128 外，PrimType 全集均有映射，故不存在第二个未映射项。本设计
**不发射任何 `any`**：映射表逐项裁定后没有需要 `any` 的形状，产物
含 `any` 即视为缺陷（验收以 grep 断言）。

## 4. 逐格式镜像规则

- ESM：S1 全部函数 + S2 全部 wrapper + S3 助手，逐个
  `export declare function` / `export declare const`。
- CJS：S1 全部函数 + S3 助手（S2 wrapper 按产物实情不导出，
  SURFACE §1 已登记该不对称）。声明语法与 ESM 同形
  （`export declare`）——TS 以 commonjs 模块消费 CJS 产物时经
  属性访问解构 `module.exports`，该形态是 CJS 类型的通行写法且
  验收双向（对/错调用）均按此验证。
- 声明顺序 = 产物中函数的发射顺序（任务序），助手按产物尾部
  export 列表的固定序置于末尾；净化后重名的函数只发最后一个
  签名（镜像 JS 函数提升的覆盖语义）。
- 产物确定性：.d.ts 是已验证模块的纯函数，无时间戳/随机成分；
  头部注释只含来源文件名（与 JS 产物 `// source:` 同源）。

## 5. 验收口径（执行记录见终报）

1. demos/rosetta 965（句柄 ctor/method/get）、966（string-out）、
   968（回调）+ demos/support/dts_probe_types.sa（标量/i64/fallible/
   ptr 全形）生成 .d.ts。
2. typescript 5.9.3 写 TS 消费片段 `tsc --noEmit`：正确调用全过；
   人为写错（参数个数、把 SaHandle 传给 number 形参、把 fall_ok
   结果当 number 用等）必须报错——双向证据。
3. 开/关 `--emit-dts` 两档 JS 产物 `diff` 逐字节一致。
4. js-matrix 与 sci 单测失败名字集与基线（fc638db5）比对。
5. 发射器单测进 emit_js.zig 底部（映射函数 + 路径推导 + 迷你
   模块端到端形状由 js_matrix_smoke 新增用例覆盖）。
