# HubProxy

This example is a runnable OpenAI-compatible reverse proxy built on the HTTP client and HTTP server plugins.

- `sa_http_server` owns inbound request handling and response emission.
- `sa_http_client` owns outbound OpenAI API calls and streaming responses.

The implementation stays inside the example directory. It should not be turned into a new host command branch.

## Runtime Shape

1. `main.zig` loads `upstream.json`.
2. The example listens on `listen_host:listen_port`.
3. `/v1/chat/completions` and `/v1/responses` are forwarded to the configured upstream base URL.
4. Streaming responses are forwarded as SSE/body chunks instead of being buffered into a fake placeholder.

## Files

- `main.zig`: entry point for the proxy application and local smoke tests.
- `upstream.json`: sample upstream configuration.
- `routes.md`: route mapping notes for the proxy.

## Run Shape

The default config is read from `examples/hubproxy/upstream.json`.
Override the path by passing a different JSON file path as the first argument.
