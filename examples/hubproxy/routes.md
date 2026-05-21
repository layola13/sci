# HubProxy Routes

- `/v1/chat/completions` -> proxy to upstream chat completions
- `/v1/responses` -> proxy to upstream responses API

Both routes are forwarded with the original request body and preserve streaming upstream responses.

The route table is owned by the example, not by `src/cli.zig`.
