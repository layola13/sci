# SA DB 插件性能评估

日期：2026-06-12
插件：`/home/vscode/projects/sa_plugins/sa_plugin_db/sap.json`，`db` v0.1.0
SA：`sa 0.0.3.3`

## 范围

本次评估用 SA 写了一个小型会员库 benchmark，并用 SA `@extern sqlite3_*` 调系统 SQLite 做对照。

测试覆盖：

- 新建数据库/初始化 schema。
- 50,000 行会员数据批量插入。
- 通过 read handle 做 `SUM(points)` 查询、`plan = 1` 计数查询。
- 全量更新 `points += 5`。
- compact/vacuum、verify/integrity check。
- 4 worker 并发查询和 4 worker 并发插入。

SA benchmark 源码和原始输出在 `/home/vscode/projects/sa_plugins/sa_plugin_db/benchmark_test/`：

- `db_member_bench.sa`
- `sqlite_member_bench.sa`
- `db_concurrent_bench.sa`
- `sqlite_concurrent_bench.sa`
- `*_runs.txt`
- `RESULTS.md`

## 接口状态

db 插件现在公开 SA-facing 接口：

- `db.sai`：声明 `sa_db_init_schema`、`sa_db_ingest_columns`、`sa_db_update_u64_add`、`sa_db_open_read_table`、`sa_db_close_read_table` 和 `*_handle` 查询 native extern。
- `db.sal`：提供错误码、`SaDbTableInfo`/`SaDbColumnInput` 布局常量和宏 facade。
- `sap.json`：声明 `abi.symbols = "db.sai"`，并在 `interfaces` 中开放 `sai`/`sal`。

旧 direct query ABI 已删除；SA 查询只保留 read-handle 接口。`sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` 已成功刷新 `/home/vscode/.local/share/sa_plugins/installed/db/current/`。之前被 node 插件挡住的根因是 `node.sai` 和 `node_extra.sai` 同时声明 `sa_node_plugin_fs_cp`，已从 `node_extra.sai` 删除重复声明，并给插件安装器补了重复 extern 的明确诊断。

## 修复项

- db 插件新增 native SA API，用于直接从 SA benchmark 初始化 schema、列式 ingest、sum/count/update、compact/verify。
- db 查询路径改为 read-handle 快照扫描，打开句柄时复制只读列数据，后续 SUM/COUNT/MIN/MAX 不再反复解析 metadata 和读文件。
- db native 写入口增加进程内互斥，修复 4 个 SA worker 同时 ingest 时 metadata 覆盖的问题。
- SA runtime 的 pthread host shim 改为真实 pthread handle，并把 worker stack 调到 2 MB。旧 16 KB stack 会在插件内 Zig 调用触发 stack probe 崩溃。
- SA 编译器 LLVM C shim 修复整数返回/slot 编码路径，避免 vtable worker 返回值编码落到不合适的类型转换。
- `sci` 增加 pthread vtable 回归 demo/test，worker 会使用 vtable entry、写回 join slot，并分配 64 KB stack 压测。

## 单线程结果

5 轮中位数：

| 操作 | db 插件 | SQLite | 最快 |
| --- | ---: | ---: | --- |
| create/init | 6.711 ms | 0.596 ms | SQLite 约 11.3x |
| prepare columns | 1.018 ms | N/A | db 专有成本 |
| bulk insert | 19.012 ms | 41.081 ms | db 插件约 2.2x |
| sum before | 5.359 ms | 3.256 ms | SQLite 约 1.6x |
| update all | 8.897 ms | 9.838 ms | db 插件约 1.1x |
| sum after | 3.683 ms | 2.803 ms | SQLite 约 1.3x |
| count plan=1 | 1.108 ms | 2.253 ms | db 插件约 2.0x |
| compact/vacuum | 20.293 ms | 5.597 ms | SQLite 约 3.6x |
| verify/integrity | 11.624 ms | 3.518 ms | SQLite 约 3.3x |

## 并发结果

5 轮中位数：

| 操作 | db 插件 | SQLite | 最快 |
| --- | ---: | ---: | --- |
| serial query, 100x SUM | 122.111 ms | 308.089 ms | db 插件约 2.5x |
| concurrent query, 4x25 SUM | 48.385 ms | 120.165 ms | db 插件约 2.5x |
| concurrent insert, 4x12,500 rows | 55.618 ms | 90.713 ms | db 插件约 1.6x |

## 结论

- 查询速度：单次 read-handle SUM 计入打开快照成本时 SQLite 更快；复用 read handle 的串行/并发全表 SUM，db 插件更快。
- 并发插入：db 插件更快，但当前是进程内互斥串行化 writer，不是完整事务/MVCC。
- 批量插入和全量列更新：db 插件更快。
- 建表、compact/vacuum、verify/integrity：SQLite 明显更快。

如果只看本次会员库 benchmark：并发查询和并发插入最快的都是 db 插件。若需求包含 SQL、索引、ACID、崩溃恢复或长期数据可靠性，SQLite 仍是更稳的选择。
