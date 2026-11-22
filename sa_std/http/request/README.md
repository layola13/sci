# http/request — HTTP request

Request-side shared surfaces: multipart/form-data parser + builder
(`multipart.sai`). The URL value layer (`url.sla`) stays at `http/`
root: it is shared by client, server, proxy and SMTP, not request-only.
