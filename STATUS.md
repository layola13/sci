# sci staging — 状态

> **状态（2026-11-05 文档审计）**：本文为某 staging 线 2026-11-02 的工作状态快照（基点 8979c4e1），非 sci 主线现状；主线现状见 readme.md「Current status」。

## 现状态（2026-11-02，DEF 深 drop 批完工，本地提交、未推送）

- 基点：sci main `8979c4e1`，分支 `deepdrop-base`。本地路径克隆自
  `~/workspace/sched-wake-local/sci`（bundle sha256 双确认过的完整克隆），
  HEAD 与工作树完整性已核（关键文件抽查在位）。原占位提交的 STATUS 内容
  已并入（见文末归档段）。
- 本批 sci 侧落地（3 笔）：
  1. `17fc328` emit_c 前导分配器 v1：空闲链表复用（头 {size:u32@0,
     magic:u32@4}，LIVE `0x5A110C4B` / FREE `0xF2EE0B10`，切分 ≥32B，
     复用块清零，范围+magic 守卫）。
  2. `8b934a3` **根因修复**：`sa_std/alloc/vec.sa` `@sa_vec_push` 扩容
     路径与 `@sa_vec_shrink_to` L_ZERO 路径漏 free 旧缓冲——probe_a
     ≈8.24 MB/轮保留的第一阶根因（DESIGN §1/§2 的 box2 平台读数与
     alloc/@sa_mem_free 配对嫌疑均被本地隔离实验推翻，见 sla 仓
     DESIGN.md 落地附记）。
  3. 本笔 emit_c 三件：① `@sa_mem_free` extern 绑定（此前一律落
     trapping stub，C 路线任何 free 都跑不了——既存缺口）；
     ② sa_alloc 改 best-fit + sa_free 相邻合并（first-fit+切分会把
     唯一的 1 MiB 块逐轮切碎、bump 单调涨到 OOM）；
     ③ `.release` 发射加来源门（provCUpdate）：仅对可证自有堆基址
     的槽位发真 sa_free，其余发 no-op 注释——镜像 interp 语义与
     emit_js 既有门控；无门控时真 free 会把经 load/store 寄存器
     流转的活缓冲误放（probe_d/a 实证腐化）。附绑定回归测试
     `c extern binding maps sa_mem_free to the runtime sa_free`。
- 验证（本机 rig，串行）：
  - C 路线探针：probe_d（300 轮）exit 0；probe_a（300 轮）exit 0、
    峰值 RSS 38,092 kB；B/C 形缩放版 exit 3（已知 sink 常量伪影，
    S/E 完整）。运行需 harness 覆写 SA_GAS_LIMIT=4e10、
    SA_MEM_BYTES=256 MiB（默认值是 demo 级）。
  - `zig build test`：477/498 通过、20 个命名失败 + 26 个
    unit-framework 文件失败。逐项裁决：与本批无关，全部既存——
    26 个 unit 文件在 stash 掉本笔 emit_c 后同样全败、且在零改动的
    pre-batch 树（5e1e9b9）上同样失败（linked_list 为 segfault）；
    c-matrix 在 stash 态同样败于 `sa_install_sigpipe_ignore`
    未定义引用（既存 emit_c 缺口：主序言引用该符号但独立 C 链接
    时不发其定义——另行登记 DEF）；其余命名失败为环境类
    （dns/pty/keyring/tree-sitter/tls loopback/wasm 工具链）。
    失败集快照：`~/workspace/deepdrop-local/logs/sci_fail_names.txt`、
    `sci_fail_unitfiles.txt`。
  - 本笔新测试不在失败集内（通过）。

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
