#!/usr/bin/env python3
"""Loopback stub servers for the sa_std http_proxy SLA tests.

All listeners are on 127.0.0.1 (the TLS CONNECT proxy also accepts the
name "localhost" via SNI-less default cert). Ports:

  18101  CONNECT proxy, no auth; validates the request head byte-exactly
         (target 127.0.0.1:18103), then relays to the echo target.
  18102  CONNECT proxy requiring Proxy-Authorization: Basic user:pass
         (dXNlcjpwYXNz); wrong/missing auth gets a 407 reply.
  18103  Plain TCP echo target.
  18104  CONNECT proxy that always replies 407.
  18105  CONNECT proxy that always replies 500.
  18106  SOCKS5 proxy, no-auth method only; IPv4 + domain targets.
  18107  SOCKS5 proxy requiring RFC 1929 user/pass ("user"/"pass").
  18108  SOCKS5 proxy that grants the request then replies rep=5.
  18109  TLS echo target (cert from argv[1]/argv[2]).
  18110  CONNECT proxy for the TLS target: validates the head
         (target localhost:18109) and relays to 127.0.0.1:18109.
  18111  TLS-wrapped CONNECT proxy (cert from argv[1]/argv[2]):
         validates the head (target 127.0.0.1:18103) inside TLS,
         then relays.

Usage: http_proxy_stub.py <server.crt> <server.key>
"""

import socket
import ssl
import sys
import threading

ECHO_PORT = 18103
TLS_ECHO_PORT = 18109

EXPECTED_PLAIN = (
    b"CONNECT 127.0.0.1:18103 HTTP/1.1\r\n"
    b"Host: 127.0.0.1:18103\r\n"
    b"\r\n"
)
EXPECTED_AUTH = (
    b"CONNECT 127.0.0.1:18103 HTTP/1.1\r\n"
    b"Host: 127.0.0.1:18103\r\n"
    b"Proxy-Authorization: Basic dXNlcjpwYXNz\r\n"
    b"\r\n"
)
EXPECTED_TLS_TARGET = (
    b"CONNECT localhost:18109 HTTP/1.1\r\n"
    b"Host: localhost:18109\r\n"
    b"\r\n"
)
EXPECTED_NAMED_HTTP = (
    b"CONNECT proxytest.local:18103 HTTP/1.1\r\n"
    b"Host: proxytest.local:18103\r\n"
    b"\r\n"
)
EXPECTED_NAMED_HTTPS = (
    b"CONNECT proxytest.local:18109 HTTP/1.1\r\n"
    b"Host: proxytest.local:18109\r\n"
    b"\r\n"
)

REPLY_200 = b"HTTP/1.1 200 Connection Established\r\n\r\n"
REPLY_400 = b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
REPLY_407 = (
    b"HTTP/1.1 407 Proxy Authentication Required\r\n"
    b"Proxy-Authenticate: Basic realm=\"stub\"\r\n"
    b"Content-Length: 0\r\n\r\n"
)
REPLY_500 = b"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n"


def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    try:
        dst.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass


def relay(client, target_host, target_port):
    try:
        upstream = socket.create_connection((target_host, target_port), timeout=10)
    except OSError:
        try:
            client.sendall(REPLY_500)
        except OSError:
            pass
        client.close()
        return
    client.sendall(REPLY_200)
    t = threading.Thread(target=pump, args=(client, upstream), daemon=True)
    t.start()
    pump(upstream, client)
    client.close()
    upstream.close()


def read_head(conn):
    buf = b""
    while b"\r\n\r\n" not in buf and len(buf) <= 16384:
        chunk = conn.recv(4096)
        if not chunk:
            break
        buf += chunk
    return buf


def handle_connect(conn, expected, target_host, target_port, auth_expected=None):
    try:
        head = read_head(conn)
        if auth_expected is not None:
            if head != auth_expected:
                conn.sendall(REPLY_407)
                conn.close()
                return
            relay(conn, target_host, target_port)
            return
        if head != expected:
            conn.sendall(REPLY_400)
            conn.close()
            return
        relay(conn, target_host, target_port)
    except OSError:
        try:
            conn.close()
        except OSError:
            pass


def handle_connect_fixed_reply(conn, reply):
    try:
        read_head(conn)
        conn.sendall(reply)
    except OSError:
        pass
    conn.close()


def handle_echo(conn):
    try:
        while True:
            data = conn.recv(65536)
            if not data:
                break
            conn.sendall(data)
    except OSError:
        pass
    conn.close()


def recvn(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("short read")
        buf += chunk
    return buf


def socks_reply(rep, atyp_addr=b"\x01\x00\x00\x00\x00", port=b"\x00\x00"):
    return b"\x05" + bytes([rep]) + b"\x00" + atyp_addr + port


def handle_socks(conn, require_auth, force_rep=None):
    try:
        greeting = recvn(conn, 2)
        nmethods = greeting[1]
        methods = recvn(conn, nmethods)
        if require_auth:
            if 0x02 not in methods:
                conn.sendall(b"\x05\xff")
                conn.close()
                return
            conn.sendall(b"\x05\x02")
            auth_head = recvn(conn, 2)
            ulen = auth_head[1]
            uname = recvn(conn, ulen)
            plen = recvn(conn, 1)[0]
            passwd = recvn(conn, plen)
            if uname == b"user" and passwd == b"pass":
                conn.sendall(b"\x01\x00")
            else:
                conn.sendall(b"\x01\x01")
                conn.close()
                return
        else:
            conn.sendall(b"\x05\x00")
        req = recvn(conn, 4)
        atyp = req[3]
        if atyp == 1:
            addr = socket.inet_ntoa(recvn(conn, 4))
        elif atyp == 3:
            dlen = recvn(conn, 1)[0]
            addr = recvn(conn, dlen).decode("ascii")
        elif atyp == 4:
            raw = recvn(conn, 16)
            addr = socket.inet_ntop(socket.AF_INET6, raw)
        else:
            conn.sendall(socks_reply(8))
            conn.close()
            return
        port = int.from_bytes(recvn(conn, 2), "big")
        if force_rep is not None:
            conn.sendall(socks_reply(force_rep))
            conn.close()
            return
        try:
            upstream = socket.create_connection((addr, port), timeout=10)
        except OSError:
            conn.sendall(socks_reply(5))
            conn.close()
            return
        conn.sendall(socks_reply(0))
        t = threading.Thread(target=pump, args=(conn, upstream), daemon=True)
        t.start()
        pump(upstream, conn)
        conn.close()
        upstream.close()
    except (OSError, ConnectionError):
        try:
            conn.close()
        except OSError:
            pass


def serve(port, handler, tls_context=None):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(64)

    def loop():
        while True:
            try:
                conn, _ = srv.accept()
            except OSError:
                return
            if tls_context is not None:
                try:
                    conn = tls_context.wrap_socket(conn, server_side=True)
                except (ssl.SSLError, OSError):
                    conn.close()
                    continue

            def run(c=conn):
                handler(c)

            threading.Thread(target=run, daemon=True).start()

    threading.Thread(target=loop, daemon=True).start()
    return srv


def main():
    cert, key = sys.argv[1], sys.argv[2]
    tls_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls_ctx.load_cert_chain(cert, key)

    serve(18101, lambda c: handle_connect(c, EXPECTED_PLAIN, "127.0.0.1", ECHO_PORT))
    serve(18102, lambda c: handle_connect(c, None, "127.0.0.1", ECHO_PORT, auth_expected=EXPECTED_AUTH))
    serve(ECHO_PORT, handle_echo)
    serve(18104, lambda c: handle_connect_fixed_reply(c, REPLY_407))
    serve(18105, lambda c: handle_connect_fixed_reply(c, REPLY_500))
    serve(18106, lambda c: handle_socks(c, require_auth=False))
    serve(18107, lambda c: handle_socks(c, require_auth=True))
    serve(18108, lambda c: handle_socks(c, require_auth=False, force_rep=5))
    serve(TLS_ECHO_PORT, handle_echo, tls_context=tls_ctx)
    serve(18110, lambda c: handle_connect(c, EXPECTED_TLS_TARGET, "127.0.0.1", TLS_ECHO_PORT))
    serve(18111, lambda c: handle_connect(c, EXPECTED_PLAIN, "127.0.0.1", ECHO_PORT), tls_context=tls_ctx)
    serve(18112, lambda c: handle_connect(c, EXPECTED_NAMED_HTTP, "127.0.0.1", ECHO_PORT))
    serve(18113, lambda c: handle_connect(c, EXPECTED_NAMED_HTTPS, "127.0.0.1", TLS_ECHO_PORT))
    print("stub ready", flush=True)
    threading.Event().wait()


if __name__ == "__main__":
    main()
