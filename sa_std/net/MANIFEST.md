# sa_std/net — module boundary manifest (Phase 1, 2026-11-22)

Domain agent E. Phase 1 only defines the module boundary; it does not
split files, fix bugs, or run builds/tests.

## Scope

Transport and name resolution: sockets (TCP/UDP/Unix), addressing,
DNS, ICMP, TLS/DTLS, QUIC, WebSocket client, io_uring engine,
network-interface information.

## Public modules

| File | Role | Lines |
|---|---|---|
| `socket/net.sa` | Socket/TCP/UDP/Unix macros (monolith, 4233 lines) | 4233 |
| `socket/net.sai` | Socket externs: TcpStream/TcpListener/UdpSocket/NetAddr handles | 329 |
| `socket/net.sal` | Socket error codes, address layouts (`#def`) | 173 |
| `socket/net.sla` | SLA address-family constants (AF_UNSPEC/AF_INET/AF_INET6) | 158 |
| `netx.sa` / `.sai` / `.sal` | io_uring network engine macros + externs + status codes | 85/11/39 |
| `net_info.sai` / `.sla` | Network-interface enumeration (SLA over fs/json externs) | 47/1200 |
| `ip.sla` | IP address / prefix value layer (SLA) | 1633 |
| `icmp.sla` | ICMP wire codec + echo/ping over raw sockets (SLA) | 465 |
| `quic.sa` / `.sai` / `.sal` / `.sla` | QUIC macros/externs/codes + SLA QuicError constants | 168/58/11/34 |
| `dtls.sa` / `.sai` / `.sal` | DTLS server-context macros/externs/codes | 60/27/4 |
| `tls.sla` | TLS cipher-suite constants (SLA) | 49 |
| `tls_client.sa` / `.sai` | TLS client one-liner macros + config externs | 103/134 |
| `tls_server.sa` / `.sai` / `.sal` / `.sla` | TLS server macros/externs/codes + SLA error constants | 96/56/5/23 |
| `ws_client.sa` / `.sai` / `.sla` | WebSocket client macros/externs + opcode/close-code consts | 51/57/48 |
| `prelude.sa` / `prelude.sal` | Namespace aggregation (see below) | — |

Total: 29 files, 10,433 lines (net domain).

## Subdirectories

- `socket/` — the socket API (`net.*` companion set). TCP and UDP live
  here as one monolith; they are NOT split in Phase 1.
- `tcp/` — RESERVED, empty. Future split target for the TCP part of
  `socket/net.sa`. See `tcp/README.md`.
- `udp/` — RESERVED, empty. Future split target for the UDP part of
  `socket/net.sa`. See `udp/README.md`.
- `dns/` — DNS (`dns.sla`, 1076 lines).

## Public face

- `net/prelude.sa` aggregates the SA face: `socket/net.sa`, `netx.sa`,
  `quic.sa`, `dtls.sa`, `tls_client.sa`, `tls_server.sa`, `ws_client.sa`.
- `net/prelude.sal` aggregates the ABI/layout face: the `.sal`/`.sai`
  companions of the same modules.
- Top-level `sa_std/prelude.sa` / `prelude.sal` now import
  `net/prelude.sa` / `net/prelude.sal` (replacing the old direct
  `net.sa`/`netx.sa` and `net.sai`/`netx.sai` lines).
- `.sla` const files (`socket/net.sla`, `quic.sla`, `tls.sla`,
  `tls_server.sla`, `ws_client.sla`) are imported individually by path;
  there is no `prelude.sla` precedent in the tree (no `.sa` file imports
  a `.sla` file anywhere), so none was created.

## Allowed dependency directions

- `net` MAY depend on: `core` (slice/result/option), `io` (`io.sal`),
  `os` (`os/fd.sa`), `alloc`/`string`/`vec`/`ptr`/`hash`/`fmt`,
  `time`, `fs`, `encoding/json` (net_info only), `status.sla`.
- `net` MUST NOT depend on: `db`, `http` — with ONE documented
  exception: `ws_client` (this domain, by task assignment) uses the
  WebSocket externs declared in `http/client/http_client.sai`
  (`sa_http_websocket_*`). That is a `net -> http` edge; if the layering
  is ever made strict, `ws_client` moves to `http/client/` or the
  WebSocket externs move to `net/`.
- Inside `net`: `dns/` and `icmp` depend on `socket/` (`net.sai`);
  `net_info` depends on `socket/net.sla` + `ip.sla`; `quic`/`dtls`/
  `tls_*`/`ws_client` are leaves over their own `.sai` files.
- TLS/DTLS/QUIC have NO `@import` edge to `crypto.sai`. The crypto
  coupling is runtime-side only: `tls_client.sai`/`ws_client.sai`
  comments cite Zig `std.crypto.tls` / `std.crypto.Bundle` in the
  sci runtime, and `quic.sai` cites ngtcp2 + GnuTLS (external C libs).
  If a future SA-level crypto dependency appears, it must be recorded
  here first.

## Compatibility

- Old paths of all moved `.sa` / `.sal` / `.sla` files keep a thin shim
  (`@import` to the new location). Precedent: `prelude.sa`/`prelude.sal`
  aggregators and `plugin_http_server.sla` (a 2-line shim).
- Old paths of the 8 moved `.sai` files have NO shim: no `.sai` file in
  the 363-file tree contains `@import`, and the `.sai` parser is a
  separate direct-parsing path, so a `.sai` shim is unverified and was
  not created. This is a BREAKING change for external `.sai` importers
  (see Phase 1 report §5; 8 references in tests/demos need Phase 2
  updates). Phase 2 must test whether `.sai` accepts `@import`; if it
  does, shims can be added back.
- Shim safety relies on the compiler de-duplicating imports by canonical
  path: the pre-move tree already reaches the same file via several
  spellings (e.g. `net.sai` via `net.sai` and `sa_std/net.sai`,
  `core/slice.sa` via 4 spellings). Phase 2 must verify by build.

## Not in this domain

- `sse.sla`, `redis.sla` (top level) import net files; their one import
  line each was updated in Phase 1 (recorded in the report).
- `http/` depends on `net/` (see `../http/MANIFEST.md`).
- `smtp.sla` is a mail client, not HTTP; it is grouped under `http/`
  only because the task's domain list puts it there (see http manifest).
