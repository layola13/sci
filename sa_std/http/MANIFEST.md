# sa_std/http — module boundary manifest (Phase 1, 2026-11-22)

Domain agent E. Phase 1 only defines the module boundary; it does not
split files, fix bugs, or run builds/tests.

## Scope

HTTP: client, server, request/response shared surfaces, HTTP/2,
cookies, proxy, URL value layer, multipart. (SMTP is grouped here
only by task assignment — see below.)

## Public modules

| File | Role | Lines |
|---|---|---|
| `http.sla` | SLA HTTP constants: status codes + method codes | 136 |
| `http2.sa` / `.sai` / `.sal` | HTTP/2 macros/externs/frame+settings codes | 97/27/36 |
| `http_cookie.sai` / `.sla` | Cookie value layer + jar (RFC 6265) + SLA consts | 153/39 |
| `url.sla` | URL value layer (parse/resolve/quote/query) | 1926 |
| `smtp.sla` | SMTP (RFC 5321) client over net TCP + TLS (SLA) | 1019 |
| `client/http_client.sai` | Built-in HTTP client ABI | 104 |
| `client/http_proxy.sla` | Proxy: URL parsing, ProxyFromEnvironment, CONNECT/SOCKS5 | 2103 |
| `client/plugin_http_async.sa` | HTTP client v2 -> PollResult adapter | 46 |
| `server/http_server.sai` | HTTP server ABI | 100 |
| `server/plugin_http_server.sa` | HTTP server v2 facade | 61 |
| `server/plugin_http_server.sla` | SLA import surface for the server facade (shim-style) | 2 |
| `request/multipart.sai` | multipart/form-data parser + builder | 25 |
| `prelude.sa` / `prelude.sal` | Namespace aggregation (see below) | — |

Total: 15 files, 5,874 lines (http domain).

## Subdirectories

- `client/` — `http_client.sai`, `http_proxy.sla`, `plugin_http_async.sa`.
- `server/` — `http_server.sai`, `plugin_http_server.sa/.sla`.
- `request/` — `multipart.sai` (request-side shared surface).
- `response/` — RESERVED, empty. Response surfaces still live in
  `client/http_client.sai`, `server/http_server.sai` and `http.sla`.
  See `response/README.md`.
- Root holds the shared modules: `http.sla`, `http2.*`, `http_cookie.*`,
  `url.sla`, `smtp.sla`.

## Public face

- `http/prelude.sa` aggregates `http2.sa`, `client/plugin_http_async.sa`,
  `server/plugin_http_server.sa`.
- `http/prelude.sal` aggregates `http2.sal`, `http2.sai`,
  `client/http_client.sai`, `server/http_server.sai`,
  `request/multipart.sai`, `http_cookie.sai`.
- `http/` was NEVER in top-level `sa_std/prelude.sa` / `prelude.sal`
  (pre-existing gap, not introduced by Phase 1). Adding it is an open
  decision for the orchestrator — Phase 1 did not expand the top facade.
- `.sla` const files are imported individually by path; no `prelude.sla`
  was created (no precedent; no `.sa` file imports a `.sla` file).

## Allowed dependency directions

- `http` MAY depend on: `core`, `net` (`socket/net.sai`,
  `net/tls_client.sai`, `net/ip.sla`), `io`, `os/fd`, `fs`, `env`,
  `encoding/*`, `fmt`, `string`, `vec`, `ptr`, `status.sla`,
  `plugin_async.sa` (plugin adapters only).
- `http` MUST NOT depend on: `db`.
- Inside `http`: `client/` and `server/` both depend on root
  (`http.sla` consts via `http_client.sai`); `client/http_proxy.sla`
  depends on `net` (socket + TLS + IP); `server/` depends only on
  `plugin_async.sa` + its own `.sai`; `request/multipart.sai` is a
  leaf (no imports).
- `smtp.sla` is an SMTP mail client, NOT HTTP. It is placed at `http/`
  root only because the task's domain list assigns it to this domain.
  Candidate for a future `net/mail/` (or top-level mail) home; moving
  it again is a Phase 2+ decision, not Phase 1.

## Compatibility

- Old paths of all moved `.sa` / `.sal` / `.sla` files keep a thin shim
  (`@import` to the new location).
- Old paths of the 5 moved `.sai` files (`http_client`, `http_cookie`,
  `http_server`, `multipart`, `http2`) have NO shim (same `.sai`
  reasoning as in `../net/MANIFEST.md`). BREAKING for external `.sai`
  importers — see Phase 1 report §5.
- `plugin_async.sla` (async domain, untouched) imports
  `plugin_http_async.sa` and `plugin_http_server.sla` by old path;
  both keep working via shims.
