# sa_std 网络协议 binding 下沉 sci runtime — 进度与真机状态

## 目标

把 HTTP/2 (nghttp2)、HTTP/3 (nghttp3)、QUIC (ngtcp2)、DTLS、TLS-server 的真后端 binding 从 `sa_plugin_node` 下沉到 `sci` runtime,导出 `sa_std_*` ABI/宏供所有插件共用,并写严格单元测试证明。

## 分级下沉结论(基于读真代码 + 实查系统原生库)

| 协议 | 下沉文件 | 真协议机 | 系统原生库 | 单测情况 |
|---|---|---|---|---|
| HTTP/2 | `src/runtime/sa_http2.zig` | ✅ 真(libnghttp2,从 Node 迁出) | ✅ `libnghttp2.so.14` 在 | ✅ `zig build sa-http2-test` **19/19** 过:真机回环 + 严验边界(double-free、非法/越界 JSON 拒绝、ACK/非SETTINGS/非零stream_id 拒绝、ipv6 url 解析、并发 alloc/free 风暴后注册表仍可用、err 域恒负) |
| TLS-server | `src/runtime/sa_tls_server.zig` | ✅ 真(OpenSSL SSL_CTX/SSL_new/SSL_accept) | ⚠️ `libssl.so.3` dlopen-open 成功但 Zig 0.14 `DynLib.lookup` 无法解析版本化符号(`SSL_CTX_new@@OPENSSL_3.0.0`),全 lookup 返 NULL → `supported` 真实报 0 | ✅ `zig build sa-tls-server-test` **8/8** 过;真回环单测 cond-skip(plain-symbol OpenSSL 时自动真跑);严验边界(null out/path 拒绝、0-handle 读写/accept 失败、status+buffer round-trip free 干净、err 域恒负) |
| DTLS | `src/runtime/sa_dtls.zig` | ✅ 真(OpenSSL DTLS_server_method + BIO_dgram 路径) | ⚠️ 同 TLS-server,符号版本化限制 | ✅ `zig build sa-dtls-test` **6/6** 过;真回环待 plain-symbol OpenSSL;严验边界(null path/out slot、0-handle 拒绝、status round-trip、supported 诚实非伪造) |
| QUIC | `src/runtime/sa_quic.zig` | ⚠️ 骨架(cap-gated),真机待装库 | ❌ `libngtcp2`/`libnghttp3` 缺,系统未装 | ✅ `zig build sa-quic-test` **10/10** 过;诚实 capability/honest UNSUPPORTED,不伪装会话;严验不变量(supported=ngtcp2∧nghttp3∧openssl 与 capabilities JSON 交叉校验、endpoint/session create 留 handle=0、double-free、http3 supported≡quic supported) |
| HTTP/3 | `src/runtime/sa_quic.zig`(`sa_std_http3_*`) | ⚠️ 骨架(与 QUIC 同库) | ❌ 同上 | ✅ 同 QUIC 单测套件 |

## 三范式

每个 sci 侧 binding 文件配套 `sa_std` ABI/宏(对齐 sci/fs 的注册句柄惯例:返回字符串走 `u64` 句柄,`*_buffer_data/len/free` 读取释放):

- `sa_std/http2.sai`(extern 声明)/ `http2.sa`(`HTTP2_*` 宏)/ `http2.sal`(常量)
- TLS-server / DTLS / QUIC / HTTP3 的 sa_std 三范式待补(本次绑定层先就位;宏层后续轮加)

## Node facade 改造(层位归位)

`sa_plugins/sa_plugin_node/src/node_saasm_extra.zig` 原自持 libnghttp2 真后端(约 5563–5930 + 6370–6667)已整段删除,替换为薄壳 `SaStdH2 extern fn` 转发块:Node 保留对外 `sa_node_plugin_http2_*` 旧 ABI(out_ptr/out_len),内部桥接 sci 的句柄 ABI(调 `sa_std_http2_buffer_data/len/free` 拷回 Node owned 槽)。

验证:
- `zig build`(sa_plugin_node)通过。
- `nm -D libnode.so`:`sa_node_plugin_http2_client_request` 等仍为 `T`(definition,SA 层 ABI 不变);`sa_std_http2_*` 为 `U`(undefined,运行时由宿主 sci 解析)。
- `sa_node_plugin_http2_status_json`/`_config_json`(facade)原调 `loadNghttp2Api()` 改为 `http2SupportedBool()`(转 `sa_std_http2_supported`)。

运行期约定:Node .so 由 sci 宿主以 `RTLD_GLOBAL` 装载时,sci 的 `sa_std_http2_*` 符号进进程全局符号表,Node 的 `U` 自动解析。

## 关键工程发现(只看文档会误判的)

1. **Zig 0.14 `std.crypto.tls` 仅有 client,无 server**(已核实 std 源),TLS-server 必须借 OpenSSL。
2. **Zig 0.14 `std.DynLib.lookup` 不传符号版本信息**:本机 libssl 符号全为 `@@OPENSSL_3.0.0`(versioned-only),`dlopen` 成功但 `dlsym("SSL_CTX_new")` 返 NULL —— 这与 sa_plugin_node 旧版只做 `DynLib.open`(不 lookup)便误报 "openssl 可用" 不同。下沉重做后 `supported` 真实反映 lookup 可用性,不再误报。
3. **QUIC/HTTP3 真机规模**:从零写 ngtcp2/nghttp3 连接状态机(ACK/loss/cwnd)是数千行,且本机缺 `libngtcp2`/`libnghttp3`,即便写真机也无法单测回环 —— 据此做诚实 cap-gated 骨架归位,真机标 `TODO:待装库`,不把 capability stub 当"完成"。
4. **Zig 0.14 子模块的 `pub export fn` 需在 root `comptime` 强引用才进 sa_std 库**:仅 `pub const sa_http2 = @import(...)` 不够(子模块 fn 被静态 DCE);改用 `comptime { _ = &@import("sa_http2.zig").sa_std_http2_supported; }` 后所有新 export fn 进 `libsa_std.a/.so`(`nm` 验证 `T sa_std_http2_*`、`T sa_std_tls_server_*`、`T sa_std_dtls_*`、`T sa_std_quic_*` 全部 emit)。

## build 测试入口

```sh
zig build sa-http2-test      # 19/19 HTTP/2 真机(libnghttp2 settings + handshake + 边界严验)
zig build sa-tls-server-test # 8/8(真回环在装 plain-symbol OpenSSL 时自动跑 + 边界严验)
zig build sa-dtls-test       # 6/6(同 TLS-server + 边界严验)
zig build sa-quic-test       # 10/10(诚实 cap-gated + honest UNSUPPORTED + 不变量严验)
```

## 待办(后续轮)

- [ ] TLS-server / DTLS / QUIC / HTTP3 的 `sa_std` 三范式(`.sai`/`.sa`/`.sal`)补齐,对齐 http2 三范式。
- [ ] 安装 `libngtcp2`/`libnghttp3` 后写真 QUIC/HTTP3 连接状态机替换骨架的 `TODO: ...待装库`。
- [ ] 在带 plain-symbol OpenSSL 的构建环境(或链接期 `libssl.so` 直 link 而非 dlopen)真跑 TLS-server/DTLS loopback。
- [ ] 其余插件(sa_plugin_deno / sa_plugin_http_client / sa_plugin_http_server)facade 接入 `sa_std_http2_*` 的 ABI/能力 JSON,把各自 stub 改为转发 sci。
DOCEF
echo "doc written: $(wc -l < ~/projects/sci/docs/net_bindings_sink.md) lines"
