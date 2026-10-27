#!/usr/bin/env python3
"""Fixed-behaviour SMTP stub for tests/smtp_client_loopback.sla.

Usage: smtp_loopback_stub.py <port> <capture_path>

Listens on 127.0.0.1:<port> and serves sequential SMTP sessions
with canned replies:

  greeting          220 stub.example ESMTP ready
  EHLO <name>       250-stub.example greets / 250-AUTH PLAIN LOGIN /
                    250 SIZE 409600   -- except EHLO heloonly, which
                    gets 502 so the client's HELO fallback runs
  HELO <name>       250 stub.example
  AUTH PLAIN <b64>  235 when the payload is base64("\\0alice\\0secret"),
                    535 otherwise
  AUTH LOGIN        334 Username: / 334 Password: exchange; 235 for
                    alice / secret, 535 otherwise
  MAIL FROM / RCPT  250
  DATA              354, reads lines up to the lone "." terminator,
                    writes the raw DATA block (stuffed wire form,
                    terminator included) to <capture_path>, then 250
  RSET / NOOP       250
  QUIT              221, session ends (the stub keeps listening)

The stub is deliberately stateless about authentication: a session
may AUTH more than once, which the test uses to exercise a failed
attempt followed by a successful one.
"""

import base64
import socket
import sys

EXPECTED_PLAIN = base64.b64encode(b"\x00alice\x00secret").decode()
EXPECTED_USER = base64.b64encode(b"alice").decode()
EXPECTED_PASS = base64.b64encode(b"secret").decode()


def serve(conn, capture_path):
    f = conn.makefile("rb")
    out = conn.sendall
    out(b"220 stub.example ESMTP ready\r\n")
    while True:
        line = f.readline()
        if not line:
            return
        text = line.decode("utf-8", "replace").rstrip("\r\n")
        upper = text.upper()
        if upper.startswith("EHLO "):
            if text[5:].strip() == "heloonly":
                out(b"502 5.5.1 EHLO not supported here\r\n")
            else:
                out(b"250-stub.example greets\r\n"
                    b"250-AUTH PLAIN LOGIN\r\n"
                    b"250 SIZE 409600\r\n")
        elif upper.startswith("HELO "):
            out(b"250 stub.example\r\n")
        elif upper.startswith("AUTH PLAIN "):
            if text[11:].strip() == EXPECTED_PLAIN:
                out(b"235 2.7.0 Authentication successful\r\n")
            else:
                out(b"535 5.7.8 Authentication credentials invalid\r\n")
        elif upper == "AUTH LOGIN":
            out(b"334 VXNlcm5hbWU6\r\n")
            user_line = f.readline()
            if not user_line:
                return
            if user_line.decode("utf-8", "replace").strip() != EXPECTED_USER:
                out(b"535 5.7.8 Authentication credentials invalid\r\n")
                continue
            out(b"334 UGFzc3dvcmQ6\r\n")
            pass_line = f.readline()
            if not pass_line:
                return
            if pass_line.decode("utf-8", "replace").strip() == EXPECTED_PASS:
                out(b"235 2.7.0 Authentication successful\r\n")
            else:
                out(b"535 5.7.8 Authentication credentials invalid\r\n")
        elif upper.startswith("MAIL FROM:"):
            out(b"250 2.1.0 Ok\r\n")
        elif upper.startswith("RCPT TO:"):
            out(b"250 2.1.5 Ok\r\n")
        elif upper == "DATA":
            out(b"354 End data with <CR><LF>.<CR><LF>\r\n")
            block = b""
            while True:
                dline = f.readline()
                if not dline:
                    break
                block += dline
                if dline in (b".\r\n", b".\n"):
                    break
            with open(capture_path, "wb") as cap:
                cap.write(block)
            out(b"250 2.0.0 Ok queued\r\n")
        elif upper == "RSET":
            out(b"250 2.0.0 Ok\r\n")
        elif upper == "NOOP":
            out(b"250 2.0.0 Ok\r\n")
        elif upper == "QUIT":
            out(b"221 2.0.0 Bye\r\n")
            return
        else:
            out(b"502 5.5.2 Command not recognized\r\n")


def main():
    port = int(sys.argv[1])
    capture_path = sys.argv[2]
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(4)
    print("stub listening", flush=True)
    while True:
        conn, _ = srv.accept()
        try:
            serve(conn, capture_path)
        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            conn.close()


if __name__ == "__main__":
    main()
