#!/usr/bin/env python3
"""Loopback DNS responder stub for tests/dns_client_loopback.sla.

Binds UDP 127.0.0.1:<port argv[1], default 5399> and answers typed
queries with fixed, fully-determined responses so the SLA client can
assert decoded fields exactly. Names in answers use RFC 1035
compression pointers (to the question name at offset 12, and for the
CNAME chain to the target name inside the first answer's rdata).

Zone (fixed):
  example.test                A     93.184.216.34, 93.184.216.35 (ttl 300)
  example.test                AAAA  2606:2800:220:1:248:1893:25c8:1946
  example.test                MX    10 mail.example.test
  example.test                NS    ns1.example.test, ns2.example.test
  example.test                TXT   ("v=spf1 -all", "hello"), ("second",)
  alias.example.test          CNAME example.test (+ A record for A queries)
  _sip._udp.example.test      SRV   10 5 5060 sip.example.test
  34.216.184.93.in-addr.arpa  PTR   example.test
  missing.example.test        *     NXDOMAIN + SOA authority (raw rdata)
"""
import socket
import struct
import sys

TTL = 300


def enc_name(name: str) -> bytes:
    out = b""
    for label in name.split("."):
        out += bytes([len(label)]) + label.encode()
    return out + b"\x00"


def ptr(offset: int) -> bytes:
    return struct.pack(">H", 0xC000 | offset)


def rr(name_wire: bytes, rtype: int, ttl: int, rdata: bytes) -> bytes:
    return name_wire + struct.pack(">HHIH", rtype, 1, ttl, len(rdata)) + rdata


def build_response(query: bytes) -> bytes:
    qid, flags, qd, _an, _ns, _ar = struct.unpack(">HHHHHH", query[:12])
    # parse the single question
    off = 12
    labels = []
    while query[off] != 0:
        ln = query[off]
        labels.append(query[off + 1 : off + 1 + ln].decode())
        off += 1 + ln
    qname = ".".join(labels)
    q_end = off + 1
    qtype, _qclass = struct.unpack(">HH", query[q_end : q_end + 4])
    question = query[12 : q_end + 4]

    name_ptr = ptr(12)
    answers = []
    authorities = []
    rcode = 0

    if qname == "missing.example.test":
        rcode = 3
        soa_rdata = enc_name("ns1.example.test") + enc_name("hostmaster.example.test")
        soa_rdata += struct.pack(">IIIII", 2024010101, 7200, 3600, 1209600, 300)
        authorities.append(rr(name_ptr, 6, 300, soa_rdata))
    elif qname == "example.test" and qtype == 1:
        answers.append(rr(name_ptr, 1, TTL, socket.inet_aton("93.184.216.34")))
        answers.append(rr(name_ptr, 1, TTL, socket.inet_aton("93.184.216.35")))
    elif qname == "example.test" and qtype == 28:
        answers.append(rr(name_ptr, 28, TTL, socket.inet_pton(socket.AF_INET6, "2606:2800:220:1:248:1893:25c8:1946")))
    elif qname == "example.test" and qtype == 15:
        # "mail" label + pointer back to "example.test" labels inside the question
        rdata = struct.pack(">H", 10) + b"\x04mail" + ptr(12)
        answers.append(rr(name_ptr, 15, TTL, rdata))
    elif qname == "example.test" and qtype == 2:
        answers.append(rr(name_ptr, 2, TTL, b"\x03ns1" + ptr(12)))
        answers.append(rr(name_ptr, 2, TTL, b"\x03ns2" + ptr(12)))
    elif qname == "example.test" and qtype == 16:
        rdata = bytes([11]) + b"v=spf1 -all" + bytes([5]) + b"hello"
        answers.append(rr(name_ptr, 16, TTL, rdata))
        answers.append(rr(name_ptr, 16, TTL, bytes([6]) + b"second"))
    elif qname == "alias.example.test" and qtype == 5:
        answers.append(rr(name_ptr, 5, TTL, enc_name("example.test")))
    elif qname == "alias.example.test" and qtype == 1:
        # CNAME with uncompressed target; the A record's owner name is a
        # pointer to that target inside the CNAME rdata.
        cname = rr(name_ptr, 5, TTL, enc_name("example.test"))
        # rdata starts after this answer's name ptr (2) + type/class/ttl/rdlen (10)
        target_off = 12 + len(question) + 2 + 10
        answers.append(cname)
        answers.append(rr(ptr(target_off), 1, TTL, socket.inet_aton("93.184.216.34")))
    elif qname == "_sip._udp.example.test" and qtype == 33:
        # "example.test" labels sit at offset 22 in the question name
        # (12 + len("_sip" wire) + len("_udp" wire) = 12 + 5 + 5).
        rdata = struct.pack(">HHH", 10, 5, 5060) + b"\x03sip" + ptr(22)
        answers.append(rr(name_ptr, 33, TTL, rdata))
    elif qname == "34.216.184.93.in-addr.arpa" and qtype == 12:
        answers.append(rr(name_ptr, 12, TTL, enc_name("example.test")))
    # anything else: NOERROR with no records

    resp_flags = 0x8180 | rcode
    header = struct.pack(">HHHHHH", qid, resp_flags, 1, len(answers), len(authorities), 0)
    return header + question + b"".join(answers) + b"".join(authorities)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5399
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", port))
    print(f"dns stub on 127.0.0.1:{port}", flush=True)
    while True:
        data, addr = sock.recvfrom(4096)
        try:
            sock.sendto(build_response(data), addr)
        except Exception as exc:  # keep serving; the client test will fail loudly
            print(f"stub error: {exc}", flush=True)


if __name__ == "__main__":
    main()
