# http/client — HTTP client

Client side: the built-in HTTP client ABI (`http_client.sai`),
the proxy surface (`http_proxy.sla`: URL parsing, ProxyFromEnvironment,
CONNECT/SOCKS5 tunnelling) and the client v2 async adapter
(`plugin_http_async.sa`). WebSocket client is NOT here: `ws_client.*`
lives in `sa_std/net/` (task domain assignment; it upgrades from HTTP
but is a transport client, and it depends on `http_client.sai`).
