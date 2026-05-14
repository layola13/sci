# SA-ASM EBNF

This document mirrors design appendix C and acts as the canonical syntax
reference for the current SA-ASM contract.

```ebnf
program        = { toplevel } ;
toplevel       = def | loc | macro_def | func_def | ffi_wrapper_def | extern_decl | export_def ;
def            = "#def" IDENT "=" LITERAL ;
loc            = "#loc" STRING ":" NUMBER ":" NUMBER ;
func_def       = "@" IDENT "(" [ param_list ] ")" [ "->" [ "^" ] type [ "!" ] ] ":" { line } ;
ffi_wrapper_def= "@ffi_wrapper" IDENT "(" [ param_list ] ")" [ "->" type [ "!" ] ] ":" { line } ;
extern_decl    = "@extern" IDENT "(" [ param_list ] ")" [ "->" type ] ;
export_def     = "@export" IDENT "(" [ param_list ] ")" [ "->" type [ "!" ] ] ":" { line } ;
param          = [ "&" | "^" | "*" ] IDENT [ ":" type ] ;
type           = "i8"|...|"u64"|"f32"|"f64"|"ptr"|"v128" ;
line           = label | inst | native ;
inst           = alloc | load | store | op | jmp | br | call | return | take
               | release | move | borrow | rawcast | assume_safe | assume_borrow
               | atomic_load | atomic_store | cmpxchg | fence | try_op | panic_op ;
try_op         = IDENT "=" "?" IDENT ;
panic_op       = "panic" "(" LITERAL ")" ;
atomic_load    = IDENT "=" "atomic_load" IDENT "+" LITERAL [ AtomicOrd ] ;
atomic_store   = "atomic_store" IDENT "+" LITERAL "," operand [ AtomicOrd ] ;
cmpxchg        = IDENT "=" "cmpxchg" IDENT "+" LITERAL "," operand "," operand [ AtomicOrd ] ;
fence          = "fence" [ AtomicOrd ] ;
AtomicOrd      = "relaxed" | "acquire" | "release" | "acq_rel" | "seq_cst" ;
rawcast        = IDENT "=" "*" IDENT ;
assume_safe    = IDENT "=" "assume_safe" IDENT ;
assume_borrow  = IDENT "=" "assume_borrow" IDENT [ "," "mut" ] ;
```

---

## 12. 附录 D：Capability Mask 真值表（扩展版）

旧版真值表全部保留，新增气闸舱行（见前版）与 Fallible 行：

| 当前 mask | 操作 | 合法? | 新 mask | Trap |
|---|---|---|---|---|
| `0x80` (Fallible) | `?` 展平后 | ✅ | 提取后的 value → `0x01`；status 路径走 early return | — |
| `0x01`（非 Fallible） | `?` | ❌ | — | `FallibleContractMismatch` |
| 原子指令同地址冲突 ordering | RMW | ❌ | — | `AtomicOrderingMismatch` |
| 其余见旧版 | — | — | — | — |

---

## 13. 附录 E：关键设计决策（校准版）

| 决策 | 旧版 | 本版 | 理由 |
|---|---|---|---|
| 后端中继 | Zig 源码 | LLVM IR + WASM 直出 | 跳过 Zig 前端，白嫖 O3 |
| 编译速度叙事 | "物理极限" | MVP 默认 O1；O3 只是选项 | LLVM O3 仍是秒级瓶颈，诚实 |
| Referee LOC | ≤ 1500 | ≤ 2500 MVP / 1500 stretch | 加入气闸舱 + Phi + 原子 + 错误传播后 1500 不现实 |
| AutoBevy 1M ±30% | MVP 硬指标 | post-MVP stretch | 依赖 SIMD + 并行调度，12 周难达成 |
| LLM 零训练 80% | KPI | Pilot 实测 baseline | 无证据时不预设数字 |
| 调试信息 | 未提 | `#loc` + DWARF + `-g` | 生产语言硬需求 |
| 错误传播 | 未提 | `!` 后缀 + `?` + `panic` | 避免每个前端各造一套返回协议 |
| SIMD/浮点/原子 ISA | 未定义 | 首轮就定义 | AutoBevy 等场景必备 |
| 前端合约 | 隐含 | R20 显式合约 + `libsa_scope` helper | 避免"机械映射"误导，划清责任 |
| 名称 | SA-ASM | SA | 命名简化 |

---

**文档终态**：本设计覆盖需求文档 33 条 Requirements（R1–R24 MVP + R25–R27 v0.3 + R28–R30 v0.4 + R31–R32 v0.5 + R33 v0.6）的全部契约，含 **32+ 条形式化 Property**、5 层测试策略、完整的 LLVM IR / WASM 映射表、气闸舱隔离、前端降级合约、`libsa_scope` helper、v0.2 `#mode compact`、v0.3 VTable 签名校验 + `libsa_async` + 诊断级别、v0.4 并行开发基建、v0.5 包管理 + 布局标签校验 + `sa_std` 标准库、v0.6 Referee 形式化验证 + FPGA 硬件化。
