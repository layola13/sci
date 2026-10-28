#!/usr/bin/env python3
"""STARTTLS-capable SMTP stub for tests/smtp_starttls_loopback.sla.

Usage: smtp_starttls_stub.py <port> <cert_path> <key_path>

Serves one plain SMTP session shape on 127.0.0.1:<port> (looping
for further connections):

  greeting        220 stub.example ESMTP ready
  EHLO <name>     250-stub.example greets / 250-STARTTLS / 250 SIZE
  STARTTLS        220 2.0.0 Ready to start TLS, then the socket is
                  wrapped server-side with the given certificate
  (over TLS)
  EHLO <name>     250 stub.example greets (no STARTTLS any more)
  NOOP            250 2.0.0 OK
  QUIT            221 2.0.0 Bye, session ends

Anything else gets 502. The point of the stub is the upgrade: if
the client does not really complete a TLS handshake after the
220, the post-upgrade reads fail and the test cannot pass.
"""

import socket
import ssl
import sys


def serve(conn, ctx):
    f = conn.makefile("rb")
    out = conn.sendall
    out(b"220 stub.example ESMTP ready\r\n")
    upgraded = False
    while True:
        line = f.readline()
        if not line:
            return
        text = line.decode("utf-8", "replace").rstrip("\r\n")
        upper = text.upper()
        if upper.startswith("EHLO "):
            if upgraded:
                out(b"250 stub.example greets\r\n")
            else:
                out(b"250-stub.example greets\r\n"
                    b"250-STARTTLS\r\n"
                    b"250 SIZE 409600\r\n")
        elif upper == "STARTTLS" and not upgraded:
            out(b"220 2.0.0 Ready to start TLS\r\n")
            conn = ctx.wrap_socket(conn, server_side=True)
            f = conn.makefile("rb")
            out = conn.sendall
            upgraded = True
        elif upper == "NOOP":
            out(b"250 2.0.0 OK\r\n")
        elif upper == "QUIT":
            out(b"221 2.0.0 Bye\r\n")
            return
        else:
            out(b"502 5.5.2 Command not recognized\r\n")


def main():
    port = int(sys.argv[1])
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(sys.argv[2], sys.argv[3])
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    listener.listen(4)
    while True:
        conn, _ = listener.accept()
        try:
            serve(conn, ctx)
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()
