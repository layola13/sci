#!/usr/bin/env python3
"""One-shot HTTP stub serving a fixed SSE stream for the
sse_parser_feed_http_sse composition probe.

Usage: sse_http_stub.py <port>
POST /events -> 200 text/event-stream with two events, then close.
"""
import socket
import sys

BODY = b"data: one\n\ndata: two\n\n"


def main():
    port = int(sys.argv[1])
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(4)
    print("stub listening", flush=True)
    while True:
        conn, _ = srv.accept()
        try:
            f = conn.makefile("rb")
            # Read request line + headers, then the body per
            # Content-Length, then answer.
            f.readline()
            length = 0
            while True:
                h = f.readline()
                if h in (b"\r\n", b"\n", b""):
                    break
                if h.lower().startswith(b"content-length:"):
                    length = int(h.split(b":", 1)[1].strip())
            if length:
                f.read(length)
            resp = (b"HTTP/1.1 200 OK\r\n"
                    b"Content-Type: text/event-stream\r\n"
                    b"Content-Length: " + str(len(BODY)).encode() + b"\r\n"
                    b"Connection: close\r\n\r\n" + BODY)
            conn.sendall(resp)
        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            conn.close()


if __name__ == "__main__":
    main()
