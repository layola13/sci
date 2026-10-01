# Windows ABI gap matrix

本文件是当前 Windows ABI 缺口的源码审计矩阵。它只描述当前工作区
的证据，不扩大 Windows 支持声明，也不修改 ABI manifest。

## 证据边界

- ABI 基线：[`src/runtime/sa_std.h`](../src/runtime/sa_std.h)。
- Windows 导出集合：[`src/runtime/sa_std_windows.zig`](../src/runtime/sa_std_windows.zig)。
- 缺口 allow-list：[`docs/runtime_abi_windows_unsupported.txt`](runtime_abi_windows_unsupported.txt)。
- 额外 Windows 导出：[`docs/runtime_abi_windows_extra.txt`](runtime_abi_windows_extra.txt)。
- 机器校验规则：[`tools/runtime_abi_check.zig`](../tools/runtime_abi_check.zig)。该校验要求：manifest 名称必须存在于 C 头文件、不得同时被 Windows runtime 导出，且 Windows 缺失的公共符号必须进入 manifest。
- 当前支持边界：[`docs/windows_support_level.txt`](windows_support_level.txt) 声明为 bootstrap/core + optional LLVM native codegen，并明确不宣称完整 `sa_std` runtime parity。

本次按 manifest 中以 `sa_` 开头的实际行统计：201 个条目。源码导出扫描显示其中 8 个已经出现在 Windows runtime，但仍留在 manifest；因此它们是“已实现、待清理/专项回归”，不是当前真实缺失的 ABI。其余 193 个在 Windows runtime 源码中没有对应导出，状态为“manifest unsupported”。

## 状态定义

| 状态 | 含义 |
|---|---|
| 已实现（manifest stale） | Windows runtime 源码已有对应 `pub export fn`；manifest 尚未同步，且本矩阵不替它修改 manifest。 |
| unsupported | 当前 manifest 明确列入 allow-list，且源码导出扫描未找到对应 Windows 导出。这里只记录事实，不推断永久不可实现。 |
| 待验证 | 已有 Windows 源码/构建证据，但本次没有足够的专项 native 行为回归证据；不能据此升级为已支持。 |

## 已实现、但 manifest 仍标为 gap（8）

源码依据：`src/runtime/sa_std_windows.zig` 中的 `pub export fn`；构建依据：Windows `runtime-abi-check` 与此前 Windows runtime 构建门禁。专项行为测试仍应单独确认后再清理 manifest。

| 能力域 | 已导出的符号 | 当前判定 |
|---|---|---|
| 动态库 | `sa_dl_open`, `sa_dl_sym`, `sa_dl_close`, `sa_dl_error` | 已实现；待 manifest 同步与专项回归 |
| IO 行/缓冲区 | `sa_io_read_line`, `sa_io_buffer_data`, `sa_io_buffer_len`, `sa_io_buffer_free` | 已实现；待 manifest 同步与专项回归 |

## 当前 manifest unsupported：按能力域

以下清单是 manifest 当前实际内容的完整分组。每项均为当前 Windows runtime 未导出的公共 ABI；“unsupported”是当前发布边界，不等价于已经证明永远无法实现。

### 测试辅助（4）

`sa_assert_eq_i64`, `sa_assert_eq_i64_at`, `sa_test_debug_i64`, `sa_test_fallible_i32_value`

### Deno/响应规范化（7）

`sa_deno_chat_json_to_responses`, `sa_deno_chat_sse_to_responses`, `sa_deno_jsonrpc_params_string_literal`, `sa_deno_responses_chat_fallback_request`, `sa_deno_responses_json_normalize`, `sa_deno_responses_request_normalize`, `sa_deno_responses_sse_normalize`

### 环境目录（6）

`sa_env_xdg_cache_home_dir`, `sa_env_xdg_config_dirs`, `sa_env_xdg_config_home_dir`, `sa_env_xdg_data_dirs`, `sa_env_xdg_data_home_dir`, `sa_env_xdg_state_home_dir`

### HTTP（1）

`sa_http_client_resp_body_slice`

### 正则表达式（7）

`sa_regex_compile`, `sa_regex_free`, `sa_regex_group_count`, `sa_regex_group_len`, `sa_regex_group_ptr`, `sa_regex_match`, `sa_regex_match_free`

### 原始 fd 与 pidfd（12）

`sa_std_fd_as_raw`, `sa_std_fd_close_raw`, `sa_std_fd_dup`, `sa_std_fd_dup_raw`, `sa_std_fd_from_raw`, `sa_std_fd_into_raw`, `sa_std_pidfd_kill`, `sa_std_pidfd_send_signal`, `sa_std_pidfd_try_wait`, `sa_std_pidfd_try_wait_raw`, `sa_std_pidfd_wait`, `sa_std_pidfd_wait_raw`

### 进程扩展与 POSIX 进程状态（22）

`sa_std_process_abort`, `sa_std_process_exec_command_ext`, `sa_std_process_exit_status_code`, `sa_std_process_exit_status_continued`, `sa_std_process_exit_status_core_dumped`, `sa_std_process_exit_status_signal`, `sa_std_process_exit_status_stopped_signal`, `sa_std_process_group_id`, `sa_std_process_parent_id`, `sa_std_process_run_command_ext_chroot`, `sa_std_process_run_command_ext_groups`, `sa_std_process_run_command_ext_pidfd`, `sa_std_process_run_command_ext_uid_gid`, `sa_std_process_spawn_command_ext_chroot`, `sa_std_process_spawn_command_ext_groups`, `sa_std_process_spawn_command_ext_pidfd`, `sa_std_process_spawn_command_ext_uid_gid`, `sa_std_process_spawn_stream_command_ext_chroot`, `sa_std_process_spawn_stream_command_ext_groups`, `sa_std_process_spawn_stream_command_ext_pidfd`, `sa_std_process_spawn_stream_command_ext_uid_gid`, `sa_std_process_user_id`

### TCP、UDP 与地址（84）

`sa_net_tcp_stream_peek`, `sa_net_tcp_stream_set_nodelay`, `sa_net_tcp_stream_set_nonblocking`, `sa_net_tcp_stream_set_read_timeout`, `sa_net_tcp_stream_set_ttl`, `sa_net_tcp_stream_set_write_timeout`, `sa_net_udp_close`, `sa_net_udp_connect`, `sa_net_udp_join_multicast_v4`, `sa_net_udp_join_multicast_v6`, `sa_net_udp_leave_multicast_v4`, `sa_net_udp_leave_multicast_v6`, `sa_net_udp_recv`, `sa_net_udp_send`, `sa_net_udp_set_broadcast`, `sa_net_udp_set_multicast_loop_v4`, `sa_net_udp_set_multicast_ttl_v4`, `sa_net_udp_set_nonblocking`, `sa_net_udp_set_read_timeout`, `sa_net_udp_set_ttl`, `sa_net_udp_set_write_timeout`, `sa_std_net_addr_format`, `sa_std_net_tcp_accept`, `sa_std_net_tcp_connect`, `sa_std_net_tcp_listen`, `sa_std_net_tcp_listener_from_raw_fd`, `sa_std_net_tcp_listener_local_addr`, `sa_std_net_tcp_listener_set_nonblocking`, `sa_std_net_tcp_listener_set_ttl`, `sa_std_net_tcp_listener_take_error`, `sa_std_net_tcp_listener_ttl`, `sa_std_net_tcp_stream_deferaccept`, `sa_std_net_tcp_stream_from_raw_fd`, `sa_std_net_tcp_stream_local_addr`, `sa_std_net_tcp_stream_nodelay`, `sa_std_net_tcp_stream_peek`, `sa_std_net_tcp_stream_peer_addr`, `sa_std_net_tcp_stream_quickack`, `sa_std_net_tcp_stream_read`, `sa_std_net_tcp_stream_read_timeout`, `sa_std_net_tcp_stream_set_deferaccept`, `sa_std_net_tcp_stream_set_nodelay`, `sa_std_net_tcp_stream_set_nonblocking`, `sa_std_net_tcp_stream_set_quickack`, `sa_std_net_tcp_stream_set_read_timeout`, `sa_std_net_tcp_stream_set_ttl`, `sa_std_net_tcp_stream_set_write_timeout`, `sa_std_net_tcp_stream_take_error`, `sa_std_net_tcp_stream_ttl`, `sa_std_net_tcp_stream_write`, `sa_std_net_tcp_stream_write_timeout`, `sa_std_net_udp_bind`, `sa_std_net_udp_broadcast`, `sa_std_net_udp_connect`, `sa_std_net_udp_from_raw_fd`, `sa_std_net_udp_join_multicast_v4`, `sa_std_net_udp_join_multicast_v6`, `sa_std_net_udp_leave_multicast_v4`, `sa_std_net_udp_leave_multicast_v6`, `sa_std_net_udp_local_addr`, `sa_std_net_udp_multicast_loop_v4`, `sa_std_net_udp_multicast_ttl_v4`, `sa_std_net_udp_peek`, `sa_std_net_udp_peek_from`, `sa_std_net_udp_peer_addr`, `sa_std_net_udp_read_timeout`, `sa_std_net_udp_recv`, `sa_std_net_udp_recv_from`, `sa_std_net_udp_send`, `sa_std_net_udp_send_to`, `sa_std_net_udp_set_broadcast`, `sa_std_net_udp_set_multicast_loop_v4`, `sa_std_net_udp_set_multicast_ttl_v4`, `sa_std_net_udp_set_nonblocking`, `sa_std_net_udp_set_read_timeout`, `sa_std_net_udp_set_ttl`, `sa_std_net_udp_set_write_timeout`, `sa_std_net_udp_take_error`, `sa_std_net_udp_ttl`, `sa_std_net_udp_write_timeout`, `sa_std_net_to_socket_addr_first`

### Unix domain sockets（50）

`sa_net_unix_addr_abstract_len`, `sa_net_unix_addr_abstract_ptr`, `sa_net_unix_addr_free`, `sa_net_unix_addr_is_unnamed`, `sa_net_unix_addr_kind`, `sa_net_unix_addr_path_len`, `sa_net_unix_addr_path_ptr`, `sa_std_net_unix_accept`, `sa_std_net_unix_accept_addr`, `sa_std_net_unix_addr_from_abstract_name`, `sa_std_net_unix_addr_from_pathname`, `sa_std_net_unix_connect`, `sa_std_net_unix_connect_addr`, `sa_std_net_unix_datagram_bind`, `sa_std_net_unix_datagram_bind_addr`, `sa_std_net_unix_datagram_connect`, `sa_std_net_unix_datagram_connect_addr`, `sa_std_net_unix_datagram_from_raw_fd`, `sa_std_net_unix_datagram_local_addr`, `sa_std_net_unix_datagram_pair`, `sa_std_net_unix_datagram_passcred`, `sa_std_net_unix_datagram_peek_from`, `sa_std_net_unix_datagram_peer_addr`, `sa_std_net_unix_datagram_recv_from`, `sa_std_net_unix_datagram_send_to`, `sa_std_net_unix_datagram_send_to_addr`, `sa_std_net_unix_datagram_set_mark`, `sa_std_net_unix_datagram_set_passcred`, `sa_std_net_unix_datagram_shutdown`, `sa_std_net_unix_datagram_try_clone`, `sa_std_net_unix_datagram_unbound`, `sa_std_net_unix_listen`, `sa_std_net_unix_listen_addr`, `sa_std_net_unix_listener_from_raw_fd`, `sa_std_net_unix_listener_local_addr`, `sa_std_net_unix_listener_try_clone`, `sa_std_net_unix_pair`, `sa_std_net_unix_stream_from_raw_fd`, `sa_std_net_unix_stream_local_addr`, `sa_std_net_unix_stream_passcred`, `sa_std_net_unix_stream_peer_addr`, `sa_std_net_unix_stream_peer_cred`, `sa_std_net_unix_stream_set_mark`, `sa_std_net_unix_stream_set_passcred`, `sa_std_net_unix_stream_try_clone`

### 终端与 epoll（8）

`sa_std_fd_is_terminal`, `sa_term_epoll_close`, `sa_term_epoll_create`, `sa_term_epoll_ctl`, `sa_term_epoll_wait`, `sa_term_raw_enter`, `sa_term_raw_leave`, `sa_term_winsize`

## 待验证项

本次没有把任何条目标记为“已支持”，因为当前任务只做审计文档。以下是基于源码/构建证据需要单独闭环的验证项：

1. 8 个已导出的动态库/IO 符号：需要 native C 行为回归，并在确认 ABI 与生命周期后同步 manifest。
2. 其余 193 个 manifest 符号：需要逐域实现或保留 unsupported 的语义证据；不能仅凭名称判断“可移植”或“Unix-only”。
3. `sa_std/net.sai` 中的 SA-facing wrapper 不完全由 `sa_std.h` 覆盖；因此只通过 `runtime_abi_check` 不能证明这些 wrapper 的导出、返回布局和行为 parity。相关接口应以 [`sa_std/net.sai`](../sa_std/net.sai) 与 Linux runtime 对照后另行验证。
4. Windows 原生 LLVM 已有独立构建/hello-world 证据，但这不等价于 `sa_std` runtime 完整 parity；支持边界仍以 [`docs/windows_support_level.txt`](windows_support_level.txt) 为准。

## 数量核对

| 项目 | 数量 | 依据 |
|---|---:|---|
| manifest 实际符号 | 201 | `docs/runtime_abi_windows_unsupported.txt` 中匹配 `^sa_` 的行 |
| 已在 Windows runtime 导出、但仍在 manifest | 8 | `sa_dl_*` 4 个 + `sa_io_*` 4 个 |
| 当前未在 Windows runtime 导出的 manifest 符号 | 193 | 201 - 8 |
| Windows extra manifest 行 | 7 | `docs/runtime_abi_windows_extra.txt` 中匹配 `^sa_` 的行 |

本文件未修改 runtime、ABI manifest、`Agents.md` 或构建配置。
