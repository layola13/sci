# sci staging — 状态

## 现状态（2026-11-02 本机重建）

- 基点：sci main `8979c4e1`，分支 `deepdrop-base`，HEAD 已核对 = 8979c4e1，工作树干净、完整（198M；src/emit_c.zig、build.zig、src/runtime/、sa_std/ 抽查在位）。
- 来源：本机本地路径克隆自 `~/workspace/sched-wake-local/sci`（其 HEAD d5c2363 仅多一份 WIP-sched-wake.md、零代码改动；克隆后 checkout 至 8979c4e1 本体）。该树即此前 bundle sha256 双确认过的完整克隆。
- 待办（本批 sci 侧唯一改动面）：按 sla 仓 `DESIGN.md` §3 实现 `src/emit_c.zig` 前导 `sa_alloc`/`sa_free` 的侵入式空闲链表复用（头 {size:u32, magic:u32}、first-fit + ≥32B 切分、复用块清零保证不变、不做合并 v1）。原生 LLVM 路线分配器本批不动（DESIGN.md §2 第 4 层）。

## 并入的原占位 STATUS（2026-11-02 悬停点，原文）

基点应为 sci main `8979c4e1`；本机可取的等价树是二盒 rig 的 `1d93041a`
（与 8979c4e1 的已知差异仅 `src/emit_c.zig` 的 task-form 机器段，
本批不动该段——设计见 sla 仓 `DESIGN.md` §3 与文首）。

**本仓尚无源码**：整树 tarball（31,428,808 B）经二盒分块取回时被
用户「Colab 即将断线、回退本机」令中断于 23,101,440 B（取回脚本只在
完成时落盘，部分数据未保留）。sci 侧代码改动为零——`emit_c.zig` 的
sa_alloc/sa_free 空闲链表复用只有 sla 仓 DESIGN.md §3 的设计，未动工。

下一步（盒恢复或主会话放行本机通道后）：重新取回 sci 树（或 bundle）
→ 在此目录建基点提交 → 按 DESIGN.md §3 实现分配器复用。
取回过程账见同仓 `sci-fetch.log`（中断点）与 `sla-fetch.log`（sla 树
已完整取回且 sha256 与盒侧一致，见 sla 仓基点提交）。

（取回日志已归档至 `~/workspace/deepdrop-local/pre-rebuild-archive/`。）
