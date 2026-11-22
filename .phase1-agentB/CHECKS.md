# 静态 @import 解析检查结果（Phase 1 Agent B）

检查脚本：`/tmp/agentB_check.py`（@import 解析 + 环检测 + 宏清单）与 `/tmp/agentB_check2.py`（字节级校验），
均已跑在盒上工作仓 `/content/kit-work/sci2-agentS1B`（sa-optimize，HEAD be42fa97）。**未跑任何构建与测试**（用户亲令）。

## 1. @import 解析：全部通过

- 扫描范围：sa_std 内全部 407 个 .sa/.sai/.sal/.sla 文件。
- 解析规则：相对路径按 import 文件所在目录解析；`sa_std/...` 前缀按仓根 sa_std/ 解析
  （与 `src/pkg/resolver.zig:resolveStandardImport` 的回退顺序一致）。
- 结果：**855 条 @import 边全部解析到真实存在的文件，0 悬空引用。**
- 检查中途曾发现 3 处我方笔误（cursor.sa 的 `../core/mem.sa` / `../string.sai` 应为 `../../` 开头；
  fmt.sal 的 `core/result.sal` 应为 `../core/result.sal`），已当场修正并复查通过。
  修正记录：修正前 3 dangling → 修正后 0。

## 2. 环检测：通过

- 对解析后的 import 图做 DFS：**0 个环**。
- 关键点：34 个 shim 只向新路径单向转发，新路径文件永不 import 回 shim；prelude 聚合只向下，不回指。

## 3. 宏清单守恒：通过

- 原 `sa_std/io.sa` 83 个宏拆分后逐个核对：print 6、stdin 7、stdout 10、handle 15、buffer/cursor 44、
  FORMAT_INT→fmt/format/format.sa 1，**每个宏恰好出现一次，无遗漏、无重复**。
- 字节级校验（与 `git show HEAD:sa_std/io.sa` 对照）：83 个宏体**逐字节相同**，拆分只动了文件归属，未改宏体。
- 整体移动的文件（28 个）与 HEAD 对照：行数不变，差异**仅限 @import 行**（fs.sa 1 行、path.sa 5 行、process.sa 3 行、
  string_format.sa 5 行、time.sa 1 行、time.sla 1 行、fmt.sal 1 行、bufio.sa/sal 各 1 行，其余 0 行）。
- 全仓宏重复定义扫描：除 3 组域外既有重复（见下）外，**无重复宏定义**（共约 2000+ 个宏名唯一）。

## 4. 域外既有重复（检查发现，非本次引入，已在 DUPLICATES.md 登记）

- `ASSERT_TRUE_MSG`：`sa_std/core/rust_patterns.sal` + `sa_std/core/sa_core.sa`
- `CSTR_LEN`：`sa_std/ffi.sa` + `sa_std/core/rust_patterns.sal`
- `FOR_RANGE`：`sa_std/control.sal` + `sa_std/core/loop.sa`
- 核实：5 个文件本次均未修改，`git show HEAD:` 已含这些定义。检查脚本因此报 FAIL 的唯一原因就是这 3 组；
  除此之外全部检查项均为 PASS。

## 5. 修改范围核对：通过

- `git status --porcelain`：110 个路径（68 个已跟踪修改 + 42 个未跟踪，含 `.phase1-agentB/` 本目录）。
- **tests/、src/、demos/ 下 0 个文件被改动。**
- sa_std 文件数 364 → 407；顶层文件数 216 → 216（移走必留 shim）。
- 未 commit、未 push、未合并 main；只动了 `sci2-agentS1B` 副本，未碰 `sci2` 主树与 `/content/sa_all/sci` 原仓。

## 6. 未验证项（诚实登记，需后续阶段补）

1. **未跑构建/测试**：以上全部是静态检查。宏拆分、shim 转发、prelude 聚合的实际编译正确性，
   须在模块化全部完成后的统一修测阶段验证（按用户亲令）。
2. **.sla shim 未验证**：见 DEFECTS.md D8（`sa_std/time.sla` → `sa_std/time/time.sla` 的转发未经 SLA 编译器验证）。
3. **Zig 侧未核对**：`src/runtime/sa_std/*.zig` 的导出表与 .sai 声明的一致性未复核（D3/D4 涉及）；src/ 未动。
4. **.zig-cache**：盒上旧的构建缓存镜像（`.zig-cache/o/.../sa_std`）未清理、未更新，属构建产物，随下次构建再生。
