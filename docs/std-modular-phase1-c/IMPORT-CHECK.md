# 静态 @import 解析检查结果 — 领域 C

- **检查脚本**：`docs/std-modular-phase1-c/check_imports.py`（Python 3 标准库，无构建、无测试运行）。
- **执行环境**：盒上工作仓 `/content/kit-work/sci2-agentS1C`（`sa-optimize`，HEAD `be42fa97`，含本次未提交改动）。
- **执行时间**：2026-11-22（移动与导入更新完成后）。
- **结果：PASS**

## 检查内容

1. **全量解析**：扫描 `sa_std/` 下全部 393 个文件（含 `sa.mod`），对其中 825 处 `@import` 逐条解析——`sa_std/` 前缀按 std 根解析，相对路径按导入文件所在目录解析（含 `..` 归一化），`sa:`/`pkg:` 前缀跳过（本次为 0 处）。
2. **shim 链跟随**：解析目标若是 1 行 `@import` 的薄 shim，继续跟随直至真实文件（限深 5），确认链上每一步都存在。
3. **同胞一致性**：对 35 个 staged 重命名，核对每个 `.sa` 文件在旧位置的同 stem `.sai`/`.sal` 同胞在新位置是否齐全（flattener 会自动注入同目录同 stem 的 `.sai`/`.sal`，缺失即断 extern/布局）。
4. **删除路径引用**：全仓 grep 6 条被删除的 `collections/<name>.sa` 旧 shim 路径，必须为 0 引用。
5. **旧路径 shim 审计**：35 个被移动文件的旧路径逐一确认仍存在且为指向正确目标的 shim。

## 输出原文（关键行）

```
files scanned under sa_std: 393
@import occurrences checked (sa_std): 825 (domain scope incl. root prelude: 236; pkg:/sa: skipped: 0)
imports resolved through a shim: 78
DANGLING: 0
staged renames: 35
sibling-parity problems: 0
refs to deleted shim paths (must be 0):
  collections/hashmap.sa: 0
  collections/hashset.sa: 0
  collections/btree_map.sa: 0
  collections/btree_set.sa: 0
  collections/binary_heap.sa: 0
  collections/vec_deque.sa: 0
old-path shim audit: 35/35 still exist, each pointing at its canonical target
RESULT: PASS
```

## 说明与局限

- 本检查是**静态路径解析**，不等同于编译验证：它证明每个 `@import` 都能解析到真实存在的文件、shim 链不断、同胞 `.sai`/`.sal` 齐全；但**不能证明**编译通过（宏展开、符号冲突、重复定义、`.sai` shim 在 SLA 工具链下的行为均不在检查范围内）。按任务禁令未跑构建，首轮构建验证是 Phase 2 的第一步，需重点验证 3 个 `.sai` shim（`string.sai`、`growvec.sai`、`ts_unicode.sai`）与 3 个 `.sla` shim（`vec_grow.sla`、`vec_packed.sla`、`str.sla`）。
- 检查范围覆盖整个 `sa_std/`（825 处），不只本域：0 悬空意味着本次移动未在 `sa_std/` 内制造任何新的悬空引用。
- `tests/`、`demos/` 未纳入本脚本的解析（按禁令未动）；但已另行确认：它们引用的本域旧路径（`sa_std/` 前缀形式）对应的 shim 文件全部存在（`vec.sa` 109 个仓内引用者、`string.sa` 74 个、`vec_deque.sa` 21 个等，见 REPORT §10）。
- 复现：`cd /content/kit-work/sci2-agentS1C && python3 docs/std-modular-phase1-c/check_imports.py`，退出码 0 为通过。
