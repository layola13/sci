# sa2js net 适配交付文档（BP 线）

基点：sci main `14d9fbc8`，独立 worktree `/content/sci-js-net`（盒上），
本地主本 `~/workspace/jsnet-local/`。只改 `src/emit_js.zig` 与 JS 目标专属测试文件。
共享层（lowerer/referee/common）未动；撞到的共享层问题见文末登记。

BR 收尾更新（2026-10-28）：基点已随主线前进至 sci main `71c0491b`
（emit_js.zig 在 14d9fbc8..71c0491b 间逐字节未变，拼接基点有效）。
拼接后 emit_js.zig（含 REG-BR-4 的 4 行修复）sha256 =
`8e246198fcae35db62d7972c736d9c7c483d6e99f71ea893b133739b26ff77ac`；
盒上 worktree 本地提交见 §6。探针输出 sink 因 REG-BR-1 改写（见 §7），
探针文件主本在 `probes/`、改写前原件在 `probes_orig/`。

## 1. 覆盖表（方法：extern 是否在 `isKnownShim` 注册 + 体是否真实执行）

状态定义：REAL = shim 真实执行操作；MOCK = 具名 shim 但为内存模型/echo 桩；
EXPLICIT = shim 返回族内显式不支持码；MISSING = 无 shim，调用时 trap。

| 族 | 总数 | REAL | MOCK | EXPLICIT | MISSING |
|---|---|---|---|---|---|
| net.sai | 229 | 见注 1 | 0 | 见注 2 | 229−已补 |
| net_info.sai | 1 | 1 | 0 | 0 | 0 |
| netx.sai | 7 | 0 | 0 | 7（见注 3） | 0 |
| http_client.sai | 57 | 0 | 54 | 0 | 3 |
| http_server.sai | 46 | 0 | 13 | 0 | 33 |
| http_cookie.sai | 43 | 43 | 0 | 0 | 0 |
| tls_client.sai | 35 | 20 | 0 | 15 | 0 |
| tls_server.sai | 18 | 0 | 0 | 0 | 18 |
| ws_client.sai | 12 | 0 | 0 | 0 | 12 |
| dtls.sai | 11 | 0 | 0 | 0 | 11 |
| http2.sai | 14 | 0 | 0 | 0 | 14 |
| quic.sai | 29 | 0 | 0 | 0 | 29 |
| ssh.sai | 26 | 0 | 0 | 26 | 0 |

注 1：net.sai 的 REAL 面 = 本线补齐的切片（见 §2），其余仍为 MISSING，
不在本线范围内（见 §5 分类表）。
注 2：net.sai 的 EXPLICIT = recv_msg / recv_multi / unix peer cred（2 个）
+ 未映射 sockopt（按对返回 8）+ v6 组播/only_v6/nonblocking 等（见 §2）。
注 3：netx.sai（io_uring）7 个：本线未逐个加 shim，仍为 MISSING；
JS 目标上 io_uring 无对应物，归类应为 EXPLICIT（待主会话确认后补 7 个
return 8 的 shim，或维持 trap——本线不擅自改动既有 trap 语义）。

### 本线补齐名单（138 个新 shim，见 `gen_shims.py`）
- cookie 43/43 全补（REAL）。
- tls_client 35/35：REAL 20（supported/add_ca_file/connect/read/write/close/
status_json/buffer trio/peer_cert_json 镜像/config 7 件/connect_config/start_tls），
EXPLICIT 15（shaped 全族：supported 存 0，其余 -1）。
- net 切片 57 件：addr 解析/列表/反查/format、UDP 绑定/连接/收发/超时/
广播/TTL/组播 v4、TCP 连接/读写/超时/nodelay/keepalive、sockopt 四件套
（映射表内真实生效，表外返回 8）、recv_msg/recv_multi/peer_cred 显式 8、
sa_std_close、sa_std_fd_into_raw（桥接 id 模型）。
- fs 读缓冲 trio 3 件（netinfo 的出参通路必需，见 §4）。
- netinfo 1 件（REAL，broadcast 来源见 §4）。

### 既有 MOCK 明细（本线不动，主会话裁定）
- http_client send 族 4 件为 echo 桩（见 REG-BP-1）：req_send、req_send_v2、
req_send_async、req_send_async_v2，全部返回固定 200 + 请求 body 原样拷贝，
全文件零真实网络调用（扫查 node:net/tls/dgram/http/createServer/
networkInterfaces/fetch = 0 命中）。
- http_client 其余 50 个具名 shim 与 http_server 13 个具名 shim 为
请求/响应/读取器/服务器的内存模型（不触网）。
- http_client 缺失 3 件：sa_http_fetch_bytes、sa_http_client_sse_turn_ex、
sa_http_client_sse_turn_free_all。

## 2. 逐家族裁定与理由

### cookie（43，REAL）
sa_cookie.zig 的逐字 JS 移植（RFC 6265）：值解析严格性（无 `=`/空名/
非 token 名/非 cookie-octet 值直接失败）、属性逐项忽略规则、日期解析
（token 算法 + 2 位年份 + IMF-fixdate 唯一序列化形）、Domain 归一化
（去一个前导 `.` + 小写）、Max-Age 优先于 Expires、jar 存储模型
（host-only/domain 匹配/默认路径/安全源/过期删除/发送排序）、Netscape
文件（严格原子加载，行号级 last_error）。字符串出参按次物化进线性内存
（比原生“句柄拥有、 mutation 后失效”更宽松的安全超集）。

### TLS 客户端（REAL 20 + EXPLICIT 15）
- 标准模式：Node `tls.connect`（rejectUnauthorized: true，SNI = server_name
或拨号 host，CA = Node 根证书 + 进程级/配置级附加 CA），握手后
`authorized` 为假 → -100。
- insecure：rejectUnauthorized: false（唯一跳过验证的开关，默认关闭）。
- verify_self_signed：rejectUnauthorized: false + 握手后三项检查
（自签名 issuer==subject 且签名自验、有效期、主机名 checkServerIdentity），
任一失败 → -100；与 CA 锚点/insecure 的互斥在 connect 时以 -22 拒绝
（insecure + server_name 同样 -22，与原生 performHandshake 一致）。
- add_ca_memory 在 set 时以 X509Certificate 逐块验证，无可用证书 → -22
（原生跳过部分不可解析类的近似差异已登记：本移植对不可解析块直接失败，
而非跳过）。
- peer_cert_json 精确镜像原生：句柄 0 → -22，其余 → -1，out 不动。
- status_json 的 backend 字段报 `node:tls`（不冒充 std.crypto.tls），
键集合与原生一致（module/supported/protocolMachine）。
- shaped 全族：Node 无法塑造 ClientHello → supported 存 0 返回 0，
其余 -1；shaped buffer trio：data → 0、len → 0n、free → -22
（shaped 缓冲在 JS 侧永远建不出来）。

### net 切片（REAL + EXPLICIT）
- 同步化手段（架构输入，REG-BP-2）：worker 线程独占真实 socket，
主线程经 SharedArrayBuffer + Atomics.wait 单次往返阻塞等待。
代价：每操作一次 SAB 往返 + worker 事件循环一转；载荷经 SAB 拷贝
（单次上限 4MB，大读由调用方 cap 分片，与原生短读一致）；阻塞读无忙轮询；
同一时刻最多一个在途请求（即 SA 同步语义本身的要求）；worker 惰性创建
（约 10–50ms）；无 Worker/SAB/Atomics 的环境下全部桥接操作返回族内
不支持码（net 族 8、TLS 族 -1），绝不虚假成功；10 分钟看门狗防死 worker
无限挂起（原生会无限等；看门狗是运行时故障边界，不是 socket 语义）。
未改 emitter 的 async lowering 语义，该裁定留主会话。
- sockopt 映射表（真实生效 + 影子读回）：
SOL_SOCKET/SO_BROADCAST、IPPROTO_IP/IP_TTL、IP_MULTICAST_TTL、
IP_MULTICAST_LOOP（v4）、TCP_NODELAY、SO_KEEPALIVE。
SO_TYPE 按句柄种类如实回答（流 1、数据报 2）。表外（含 level 9999）
一律返回 8，绝不返回 OK。未映射的 set 不留影子（读回不撒谎）。
专用面（udp_broadcast/udp_ttl）与透传面共用同一影子状态，双向交叉
检查成立。
- 显式不支持（返回 8，out 槽先清零）：recv_msg（无 pktinfo/SO_TIMESTAMP）、
recv_multi（无 recvmmsg）、unix peer cred（无对端凭证 API）、
v6 组播 loop/hops、only_v6（族在 bind 时固定）、nonblocking
（桥模型仅阻塞）、收发缓冲大小、keepalive 参数、linger/quickack/
deferaccept、流 TTL。
- udp_send_to 在 JS 侧对字面 IP 正常工作；原生同名调用在盒上有
已登记缺陷（send_to("127.0.0.1") → INVALID_ARGUMENT，残差 12①）——
JS 侧正确不等于原生正确，属已知分歧。
- addr_reverse_lookup 失败码取 7（NET，假设值，见登记）。

### netinfo（1，REAL，来源差异已登记）
Node `os.networkInterfaces()` 组装：name/family（IPv4→2、IPv6→10）/
address/netmask/prefix_len（掩码 popcount，v6 取 cidr 后缀）/
broadcast（**计算值**：IPv4 非 loopback 取 address | ~netmask；
其余 null——Node 不提供 broadcast，原生为内核上报值）/
scope_id（Node scopeid 或 0）。loopback 地址包含在内（与原生快照一致）。

### 纯 SLA 层（探针逐层验证，不假设）
dns.sla、http_proxy.sla、sse.sla、smtp.sla、icmp.sla、bitpack、ip 值层：
底层 extern 覆盖见 §5；每层以探针实测为准（见 §6 验收）。

## 3. 运行时 chunk 与句柄模型

- chunk（`jsnet_runtime_js`）在程序声明任一 BP shim 时发射一次，
无 net extern 的程序零代价。chunk 内含：cookie 引擎、TLS 配置注册表、
net 句柄注册表、worker+SAB 桥、netinfo 组装。
- SA 侧句柄 = chunk 内 Map 的小整数（BigInt 出境）；addr/addrlist/
udp/tcp/tls 各自成类，错类 → 2（INVALID_HANDLE）。
- `sa_std_close` 仅关闭 net 族句柄（cookie/jar/buffer 各有自有 free，
原生资源注册表同样不含它们）。
- `sa_std_fd_into_raw`：取 tcp 流句柄的桥接 socket id 作 i32 fd，
SA 句柄被消费（detach 表记录），`start_tls` 据此原地升级并在
成功时发新 SA 句柄、失败时关闭 socket（与原生 fd 所有权转移一致）。
该模型是 JS 内构造，**不关闭**原生 stream→fd 原语缺口（残差 15②）。

## 4. 使能 shim 说明（fs 域，但属本线文件）

netinfo 的出参契约要求经 `sa_fs_read_buffer_*` 读取，而 emit_js 此前
对该 trio 全为 trap。本线在 emit_js.zig 内补齐 trio（data 物化拷贝、
len、free 未知 → 2），与 fmt buffer trio 同款实现。这是 netinfo 的
前置条件，不是 fs 域的全面补齐。

## 5. 未补面分类（不在本线范围，分类供主会话排期）

- net.sai 剩余：TCP 监听/accept、unix 流/数据报全族、向量化读写、
句柄克隆/from_raw_fd、ja3/ja4 助手、ws 帧编解码、url_parse、
legacy sa_net_* 拼写（除本线已补的 addr 访问器外）、option 面余部
（见 §2 显式不支持清单）。
- tls_server 18、ws_client 12、dtls 11、http2 14、quic 29、netx 7：
维持 MISSING（trap）；其中 dtls/quic/netx 在 JS 目标上无 Node 对应物，
宜归 EXPLICIT（主会话定）；ws_client/http2/tls_server 需另线设计。
- http_server 缺失 33、http_client 缺失 3：维持 MISSING（trap）；
既有 13/54 个 MOCK 不动（见 §1）。

## 6. 验收证据（盒上实测，BR 2026-10-28 回填）

环境：盒 worktree `/content/sci-js-net` @ sci main `71c0491b`（detached）+
本线 emit_js.zig；`zig build` RC=0 后用 worktree `zig-out/bin/sa` 实测；
清 `.sla-cache` 后跑探针。

- 桥原型（独立 Node 程序，盒 node v22.23.4）：28/28 全绿
（resolve、UDP 绑定/收发/超时→6、TCP 回显/拒连→6、TLS 默认验证→-100、
CA 钉住成功+回显、错 CA→-100、insecure、verifySelfSigned 及其错名→-100、
tls_start 升级+回显）。（BP 拼接前实测）
- cookie 引擎（独立 Node harness）：39/39 全绿（RFC 例、日期三形、
jar 场景、Netscape 往返+原子性、header 对、匹配原语）。（BP 拼接前实测）
- 探针（SLA 程序，build-js vs build-exe 对照，`run_probes.sh`，
HARNESS_RC=0，四家族全 MATCH）：
  - probe_cookie → **COOKIE_MATCH**（逐字节精确；含 Expires 序列化、
    jar 发送排序、Netscape 往返）。
  - probe_netinfo → **NETINFO_MATCH**（status 相等 + 逐元素逐字段相等，
    元素按 (name, family, address) 排序后比对）。
  - probe_sockopt → **SOCKOPT_MATCH**（9 个键逐值相等：set_bc=0、
    get_bc=1、set_ttl=0、ded_ttl=99、get_sotype_st=0、get_sotype_len=4、
    set_bc_bytes=0、ded_bc=1、peer_cred_pid=0；4 个设计分歧按目标分
    期望成立：set_bad_level JS 8/原生 6（REG-BR-2）、recv_msg 与
    recv_multi JS 8/原生 6、peer_cred_lone JS 8/原生 2（REG-BR-3））。
  - probe_tls → **TLS_MATCH**（归一化 backend 字段后逐字节精确；
    JS shaped_sup=0 实测；回显/钉扎/错名/错 CA/start_tls 升级全对）。
- js-matrix（`zig build js-matrix`，worktree 同法全量）：改后失败
名字集 = **∅**，与基线（BP 在 pristine `14d9fbc8` 的 detached 跑，
`/tmp/bp_jsmatrix_base.log`）逐项一致：963 个 demo 名集 diff 为空、
[js-negative]/[js-trap] 条目集 identical、Zig 测试 3/3 passed、
步级签名同为「leaked 963 allocations」（每 demo 1 个，既有签名，
非本线引入）。**零新增失败，门禁通过。**
- 纯 SLA 层探针（两路：① 原生 `sa test` 语料规范口径；② 把语料
@test 块机械转换为单 main 驱动后 build-js vs build-exe 对照；
loopback 另加 stub 实跑）：
  - **icmp.sla 编解码：JS 全绿**（原生 10/10；驱动双目标 ALL_OK）。
  - **http_proxy decide：JS 全绿**（原生 12/12；驱动双目标 ALL_OK）。
  - dns.sla：原生语料 11/11、原生 loopback 8/8；但全程序链接
    （双目标同）在 dns_build_query 撞共享层诊断（REG-BR-6），
    JS 驱动与 loopback 驱动均在构建期被挡（非 JS 特有）。
  - sse.sla：原生语料 15/15、原生 loopback 1/1；全程序链接双目标
    同撞 REG-BR-6（sse_parser_event_at），JS 驱动被挡（非 JS 特有）。
  - ip.sla：原生语料 12/12；JS 隔离复现 u32 高位分歧（REG-BR-7a）；
    原生 build-exe 与 sa test 不一致（REG-BR-8）。
  - bitpack：原生语料 13/13；JS 撞缺失 extern sa_math_floor
    （REG-BR-9）；原生序列驱动 panic 2108（REG-BR-8 注记）。
  - smtp.sla 线格式：原生语料 15/15、原生 loopback 2/2（+捕获断言）；
    JS 隔离复现 reader 状态丢失（REG-BR-7b）；smtp 客户端 loopback
    JS 被单个 legacy extern 挡住（REG-BR-10），exe ALL_OK。
  - http_proxy 解析：原生 11/11、env 4/4；JS 分别撞缺失 extern
    sa_deno_btoa / sa_env_remove_var（REG-BR-9），exe 均 ALL_OK。
  - http_proxy loopback 未跑：其 runner 会改盒上 /etc/hosts 与系统
    信任库（共享盒全局状态），本线不动；留主会话决定。

## 7. 登记项

- REG-BP-1：既有 JS http_client 传输面为 echo 桩（已实证，见 §1）；
本线不重写，真实传输模型归主会话裁定。
- REG-BP-2：Node 同步/异步模型与本线同步化手段及代价（见 §2）；
emitter async lowering 语义不动，留主会话裁定。
- REG-BP-3：fd_into_raw/start_tls 的 JS 桥接 id 模型（见 §3）；
不替代原生 stream→fd 原语缺口。
- REG-BP-4：netinfo broadcast 为计算值（见 §2）。
- REG-BP-5：sockopt 表外一律 8；recv_msg/recv_multi/peer_cred 显式 8。
- REG-BP-6：shaped TLS 在 JS 侧 supported=0、其余 -1。
- REG-BP-7：status_json backend 字段报 node:tls（不冒充）。
- REG-BP-8：addr_reverse_lookup 失败码取 7 为假设值（原生未实测）。
- REG-BP-9：add_ca_memory 对不可解析证书块直接失败（原生为跳过类），
探针用合法证书，不影响验收。
- REG-BP-10：bridge 看门狗 10 分钟（死 worker 边界，非 socket 语义）。
- REG-BP-11：netx 7 个 extern 在 JS 侧的归类（EXPLICIT vs 维持 trap）
待主会话定，本线未动。
- REG-BP-12：udp_send_to 在 JS 侧对字面 IP 正常（原生同名调用有
残差 12① 缺陷），属已知分歧。
- REG-BR-1（共享层，只登记不改）：SLA 程序以自然形式直接调用
`sa_print_bytes(p, n)`（p 为 ptr 局部量）在 **build-exe 与 build-js
两目标上都在检查期 trap `error[CapabilityMismatch]`**；主树未改
emit_js.zig 的二进制同样复现，属既有共享层缺陷（BM D3 家族）。
`sa_print_bytes(&p, n)` 形式可过检查但读的是指针槽字节（垃圾输出，
语义错误），不可用。故 SLA 程序当前没有正确的 sa_print_bytes
直呼形式，唯一可用的 stdout 通路是 println。本线探针的输出 sink
已改写为「值物化成 String（数字走 sa_fmt_i64/u64 缓冲格式化）+
println」——被测 shim 调用与输出字节与原探针完全一致。根因在
print.sai 能力签名（`&msg: ptr`）与调用点能力发射的匹配，归
主会话指派（sci/sa_std io 面或 SLA 前端）。
- REG-BR-2（设计分歧，harness 已按目标分期望）：sockopt 未映射
(level, optname) 对：JS 返回显式 8（无 OS 可问）；原生透传问 OS，
level 9999 被拒后映射为通用错误 6。JS 侧若对表外对一律回 6 会对
OS 本可接受的对（如 SO_RCVBUF）撒谎，故维持 8（与 REG-BP-5 同旨）。
- REG-BR-3（探针前提订正）：probe_sockopt 的 lone 套接字是 inet
UDP 句柄，原生 peer_cred 对非 unix 句柄返回 2（INVALID_HANDLE）；
BC 登记的「成功 + pid 0 哨兵」只适用于 unix 数据报句柄。JS 侧
peer_cred 显式 8 不变；harness 期望已订正为原生 2。
- REG-BR-4（本线已修）：gen_shims.py 的 4 个 sockopt shim 函数体
漏写 `const J = globalThis.__sa_jsnet;` 前缀，JS 运行期
`ReferenceError: J is not defined`（probe_sockopt 首呼即崩）。
已在 gen_shims.py 4 处补 `[J] +` 并重新拼接；新旧 emit_js.zig
diff 恰为 4 行新增，别无变动。
- REG-BR-5（共享层观察，只登记）：SLA `println`/`format` 的 `{}`
把有符号整数按 u64 回绕渲染：i64 −100 → 18446744073709551516、
i32 −22 → 18446744073709551594，**原生与 JS 两后端一致**（exp_v7
双目标对拍）；`sa_fmt_i64` 缓冲格式化则正确输出 −100。是缺陷还是
「{} 仅 u64 契约」请主会话/BG 裁定；探针一律走 sa_fmt 路径，
不受影响。
- REG-BR-6（共享层，只登记）：纯 SLA 层在 **全程序链接**
（build-exe / build-js）时撞 lowerer/referee 诊断，而 `sa test`
逐测试编译形状下全绿：① dns.sla 的 `@sla__dns_build_query`
报 "moved value is no longer usable"（Consumed 掩码自洽仍判死），
dns 线编解码驱动与 dns loopback 驱动双目标同败；② sse.sla 的
`@sla__sse_parser_event_at` 报 "register is already live"，
sse 驱动双目标同败。两条都**与 JS 目标无关**（原生 exe 同败），
但实际效果是这两层目前只能经 sa test 使用、不能链接进真实
程序（含 JS 程序）。复现：jsnet-local 同法转换的 spot 驱动
（盒 /tmp/br_spot/spot_dns_wire_codec.sla、spot_sse_parser.sla）。
归主会话/BG（与 SAB referee 家族一并看）。
- REG-BR-7（JS 目标语义分歧，隔离复现，只登记）：① ip.sla
`ipv4_parse("255.255.255.255")` 在 JS 上 ≠ 4294967295（panic
1007 隔离复现，exe ALL_OK）——u32 高位：解析累加值在 JS 呈
有符号 32 位形态，与 u32 字面量比较未掩码。② smtp.sla 回复
读取器：JS 上第一次 next 后返回的 reader 丢失已缓冲的第二条
回复（panic 433 隔离复现，exe ALL_OK）——结构体含 Vec 字段
跨函数返回的状态携带在 JS 发射下丢失。两条都在 emit_js 的
通用语义域（非本线 net shim），归主会话/BG。
- REG-BR-8（原生构建路径分歧，只登记）：ip.sla "summarize
range" 在 build-exe 下隔离复现 panic 1903，而 sa test 12/12
全过——原生全程序构建与 test-backend 对 IpPrefixList 返回的
处理不一致；bitpack 序列驱动 exe 侧 panic 2108（f64 量化
容差，expect_micro_in 999998/1000000）同为全程序原生构建下
出现、sa test 未现（未做单测隔离）。共享层。
- REG-BR-9（JS 缺失 extern 族，既有、零 shim，只登记）：
纯 SLA 层实测撞到的三族：sa_math_*（bitpack 量化用
sa_math_floor 首撞）、sa_deno_btoa（http_proxy Basic 认证
编码用；注意 sa_deno_plugin_btoa 是另一 extern、已 shim）、
sa_env_remove_var（http_proxy_env 用）。JS 运行期均以
"extern not linked" trap。三族均不在 BP 138 范围，补齐归
主会话排期（多为 Node 一行映射，属机械补齐类）。
- REG-BR-10（单名缺口，裁定留主会话）：smtp.sla 客户端只用
一个 legacy 拼写 extern：`sa_net_tcp_stream_close`——无 JS
shim，smtp loopback 驱动 JS 在会话收尾 trap（exe ALL_OK、
原生 loopback 2/2）。补它即把 std 流 close shim 加一个
legacy 别名，但 BP 已把 legacy sa_net_* 拼写整体分类为
线外（§5），本线不擅自扩围，登记供主会话一句话裁定。
dns.sla 客户端另用 legacy 的 sa_net_addr_free /
sa_net_udp_close 两名（当前被 REG-BR-6 挡在前面，未实测）。
