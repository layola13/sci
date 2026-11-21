// JS runtime chunk (moved from src/emit_js.zig).
// Pure data: the emitted JS source text for one runtime piece.
// Part of jsnet_runtime_js; concatenated with the other part in emit_js.zig.
pub const jsnet_runtime_js_b =
    \\  // returns cookie, the string "bad" (indexed pair malformed -> last_error),
    \\  // or null (index out of range -> no error)
    \\  function headerPairAt(raw, index) {
    \\    let idx = 0, pos = 0;
    \\    while (pos <= raw.length) {
    \\      const semi = bIndexOf(raw, 59, pos);
    \\      const end = (semi < 0) ? raw.length : semi;
    \\      const seg = bTrimOws(raw.subarray(pos, end));
    \\      if (seg.length > 0) {
    \\        if (idx === index) {
    \\          const c = parseHeaderPair(seg);
    \\          return c === null ? "bad" : c;
    \\        }
    \\        idx++;
    \\      }
    \\      if (semi < 0) break;
    \\      pos = semi + 1;
    \\    }
    \\    return null;
    \\  }
    \\
    \\  // ---------- synchronous socket bridge (worker + SAB + Atomics.wait) ----------
    \\  // SA calls are synchronous; Node net/tls/dgram are async. One worker thread
    \\  // owns every real socket; the main thread issues one request at a time and
    \\  // blocks in Atomics.wait. No emitter async-lowering change is involved:
    \\  // the asynchrony is confined to the worker, and SA programs observe plain
    \\  // synchronous call/return semantics. If Worker/SAB/Atomics are unavailable
    \\  // (browser builds), every bridge op answers the family's UNSUPPORTED code.
    \\  function __sa_jsnet_worker() {
    \\    "use strict";
    \\    const { parentPort, workerData } = require("node:worker_threads");
    \\    const net = require("node:net");
    \\    const tls = require("node:tls");
    \\    const dgram = require("node:dgram");
    \\    const dns = require("node:dns");
    \\    const crypto = require("node:crypto");
    \\    const sab = workerData.sab;
    \\    const hdr = new Int32Array(sab, 0, 4);
    \\    const data = new Uint8Array(sab, 256);
    \\    const enc = new TextEncoder();
    \\    const dec = new TextDecoder();
    \\    const socks = new Map();
    \\    let nextId = 1;
    \\    function respond(status, json, payload) {
    \\      const jb = enc.encode(JSON.stringify(Object.assign({ __status: status }, json || {})));
    \\      data.set(jb, 0);
    \\      let plen = 0;
    \\      if (payload && payload.length) { data.set(payload, jb.length); plen = payload.length; }
    \\      hdr[2] = jb.length;
    \\      hdr[3] = plen;
    \\      Atomics.store(hdr, 0, 2);
    \\      Atomics.notify(hdr, 0);
    \\    }
    \\    function fail(status, msg) { respond(status, { error: String(msg || "error") }, null); }
    \\    function getSock(id) { return socks.get(id) || null; }
    \\    function udpEntry(sock) {
    \\      const e = { kind: "udp", sock: sock, queue: [], waiter: null, readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
    \\      sock.on("message", (msg, rinfo) => {
    \\        const item = { buf: Buffer.from(msg), src: { host: rinfo.address, port: rinfo.port, family: rinfo.family } };
    \\        if (e.waiter) { const w = e.waiter; e.waiter = null; w(item); }
    \\        else e.queue.push(item);
    \\      });
    \\      sock.on("error", () => {});
    \\      return e;
    \\    }
    \\    function streamEntry(kind, sock) {
    \\      const e = { kind: kind, sock: sock, chunks: [], buffered: 0, waiter: null, eof: false, readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
    \\      sock.on("data", (chunk) => {
    \\        e.chunks.push(chunk); e.buffered += chunk.length;
    \\        if (e.waiter) { const w = e.waiter; e.waiter = null; w(); }
    \\      });
    \\      const done = () => { e.eof = true; if (e.waiter) { const w = e.waiter; e.waiter = null; w(); } };
    \\      sock.on("end", done);
    \\      sock.on("close", done);
    \\      sock.on("error", done);
    \\      return e;
    \\    }
    \\    function waitReadable(e, timeoutMs) {
    \\      return new Promise((resolve) => {
    \\        let settled = false;
    \\        const finish = (v) => { if (!settled) { settled = true; resolve(v); } };
    \\        e.waiter = () => finish("data");
    \\        if (e.eof) finish("eof");
    \\        if (timeoutMs > 0) setTimeout(() => finish("timeout"), timeoutMs);
    \\      });
    \\    }
    \\    const CERT_ERR = /CERT|certificate|self.signed|unable to verify|altname|ALPN/i;
    \\    function tlsErrStatus(err) {
    \\      if (!err) return -5;
    \\      const code = String(err.code || "");
    \\      const msg = String(err.message || err);
    \\      if (CERT_ERR.test(code) || CERT_ERR.test(msg)) return -100;
    \\      return -5;
    \\    }
    \\    async function tlsUpgrade(existingSock, p) {
    \\      const serverName = (p.serverName === undefined) ? null : p.serverName;
    \\      const caPems = p.caPems || [];
    \\      let opts = { servername: undefined };
    \\      if (existingSock) opts.socket = existingSock;
    \\      else { opts.host = p.host; opts.port = p.port; }
    \\      if (p.insecure) {
    \\        opts.rejectUnauthorized = false;
    \\        opts.servername = serverName === null ? undefined : serverName;
    \\      } else if (p.verifySelfSigned) {
    \\        opts.rejectUnauthorized = false;
    \\        opts.servername = serverName === null ? p.host : serverName;
    \\      } else {
    \\        opts.rejectUnauthorized = true;
    \\        opts.ca = tls.rootCertificates.concat(caPems);
    \\        opts.servername = serverName === null ? p.host : serverName;
    \\      }
    \\      const sock = tls.connect(opts);
    \\      await new Promise((resolve, reject) => {
    \\        let done = false;
    \\        const ok = () => { if (!done) { done = true; resolve(); } };
    \\        const bad = (e) => { if (!done) { done = true; reject(e); } };
    \\        sock.once("secureConnect", ok);
    \\        sock.once("error", bad);
    \\        if (p.timeoutMs > 0) setTimeout(() => bad(new Error("tls handshake timeout")), p.timeoutMs);
    \\      }).catch((err) => { try { sock.destroy(); } catch (e2) {} throw err; });
    \\      if (p.insecure) return sock;
    \\      if (p.verifySelfSigned) {
    \\        const cert = sock.getPeerCertificate(true);
    \\        if (!cert || !cert.raw) { sock.destroy(); const e = new Error("no peer certificate"); e.code = "CERT"; throw e; }
    \\        let x;
    \\        try { x = new crypto.X509Certificate(cert.raw); } catch (e2) { sock.destroy(); const e = new Error("peer certificate unparsable"); e.code = "CERT"; throw e; }
    \\        const now = Date.now();
    \\        const selfSigned = (x.issuer === x.subject) && x.verify(x.publicKey);
    \\        const inDate = (Date.parse(x.validFrom) <= now) && (now <= Date.parse(x.validTo));
    \\        const idErr = tls.checkServerIdentity(serverName === null ? p.host : serverName, cert);
    \\        if (!selfSigned || !inDate || idErr) { sock.destroy(); const e = new Error("self-signed verification failed: " + (idErr ? idErr.message : (!selfSigned ? "not self-signed" : "out of date"))); e.code = "CERT"; throw e; }
    \\        return sock;
    \\      }
    \\      if (!sock.authorized) {
    \\        const e = new Error("peer verification failed: " + String(sock.authorizationError || "unauthorized"));
    \\        e.code = "CERT";
    \\        sock.destroy();
    \\        throw e;
    \\      }
    \\      return sock;
    \\    }
    \\    async function handle(req, payload) {
    \\      const op = req.op;
    \\      try {
    \\        switch (op) {
    \\          case "resolve": {
    \\            const addrs = await dns.promises.lookup(req.host, { all: true, verbatim: true }).catch((e) => { throw Object.assign(new Error("resolve failed"), { saStatus: 7 }); });
    \\            respond(0, { addrs: addrs.map((a) => ({ host: a.address, family: a.family })) }, null);
    \\            return;
    \\          }
    \\          case "udp_bind": {
    \\            const fam = (req.host && req.host.indexOf(":") >= 0) ? "udp6" : "udp4";
    \\            const sock = dgram.createSocket(fam);
    \\            const e = udpEntry(sock);
    \\            await new Promise((resolve, reject) => {
    \\              sock.once("error", reject);
    \\              sock.bind(req.port, req.host, () => resolve());
    \\            }).catch((err) => { try { sock.close(); } catch (e2) {} throw Object.assign(err, { saStatus: 6 }); });
    \\            const id = nextId++;
    \\            socks.set(id, e);
    \\            const addr = sock.address();
    \\            respond(0, { id: id, port: addr.port, host: addr.address, family: addr.family }, null);
    \\            return;
    \\          }
    \\          case "udp_connect": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            await new Promise((resolve, reject) => { e.sock.connect(req.port, req.host, (err) => err ? reject(err) : resolve()); })
    \\              .catch((err) => { throw Object.assign(err, { saStatus: 6 }); });
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "udp_send": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            const buf = Buffer.from(payload || []);
    \\            const sendP = req.dest
    \\              ? new Promise((res, rej) => { e.sock.send(buf, req.dest.port, req.dest.host, (err, bytes) => err ? rej(err) : res(bytes)); })
    \\              : new Promise((res, rej) => { e.sock.send(buf, (err, bytes) => err ? rej(err) : res(bytes)); });
    \\            const n = await sendP.catch((err) => { throw Object.assign(err, { saStatus: 6 }); });
    \\            respond(0, { written: n }, null);
    \\            return;
    \\          }
    \\          case "udp_recv": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            let item = e.queue.shift() || null;
    \\            if (!item) {
    \\              const what = await new Promise((resolve) => {
    \\                let settled = false;
    \\                const fin = (v) => { if (!settled) { settled = true; resolve(v); } };
    \\                e.waiter = (it) => fin(it);
    \\                if (e.readTimeoutMs > 0) setTimeout(() => { if (e.waiter) e.waiter = null; fin(null); }, e.readTimeoutMs);
    \\              });
    \\              item = what;
    \\              if (!item) return fail(6, "recv timeout");
    \\            }
    \\            const cap = req.cap || item.buf.length;
    \\            const out = item.buf.subarray(0, cap);
    \\            respond(0, { read: out.length, src: item.src }, out);
    \\            return;
    \\          }
    \\          case "udp_set_read_timeout": {
    \\            const e = getSock(req.id); if (!e) return fail(2, "bad handle");
    \\            e.readTimeoutMs = req.timeoutMs || 0;
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "sock_close": {
    \\            const e = getSock(req.id); if (!e) return fail(2, "bad handle");
    \\            socks.delete(req.id);
    \\            try { if (e.kind === "udp") e.sock.close(); else e.sock.destroy(); } catch (err) {}
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "tcp_connect": {
    \\            const sock = net.connect({ host: req.host, port: req.port });
    \\            const e = streamEntry("tcp", sock);
    \\            await new Promise((resolve, reject) => {
    \\              let done = false;
    \\              const ok = () => { if (!done) { done = true; resolve(); } };
    \\              const bad = (err) => { if (!done) { done = true; reject(err); } };
    \\              sock.once("connect", ok);
    \\              sock.once("error", bad);
    \\              if (req.timeoutMs > 0) setTimeout(() => bad(new Error("connect timeout")), req.timeoutMs);
    \\            }).catch((err) => { try { sock.destroy(); } catch (e2) {} throw Object.assign(err, { saStatus: 6 }); });
    \\            const id = nextId++;
    \\            socks.set(id, e);
    \\            respond(0, { id: id, local: { host: sock.localAddress, port: sock.localPort }, peer: { host: sock.remoteAddress, port: sock.remotePort } }, null);
    \\            return;
    \\          }
    \\          case "stream_read": {
    \\            const e = getSock(req.id); if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return fail(2, "bad handle");
    \\            const cap = req.cap;
    \\            while (e.buffered === 0 && !e.eof) {
    \\              const what = await waitReadable(e, e.readTimeoutMs);
    \\              if (what === "timeout") return fail(req.tlsSpace ? -5 : 6, "read timeout");
    \\            }
    \\            if (e.buffered === 0 && e.eof) { respond(0, { read: 0, eof: true }, null); return; }
    \\            const parts = [];
    \\            let need = cap;
    \\            while (need > 0 && e.chunks.length) {
    \\              const c = e.chunks[0];
    \\              if (c.length <= need) { parts.push(c); e.chunks.shift(); e.buffered -= c.length; need -= c.length; }
    \\              else { parts.push(c.subarray(0, need)); e.chunks[0] = c.subarray(need); e.buffered -= need; need = 0; }
    \\            }
    \\            const out = Buffer.concat(parts);
    \\            respond(0, { read: out.length, eof: false }, out);
    \\            return;
    \\          }
    \\          case "stream_write": {
    \\            const e = getSock(req.id); if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return fail(2, "bad handle");
    \\            const buf = Buffer.from(payload || []);
    \\            const wp = new Promise((resolve, reject) => { e.sock.write(buf, (err) => err ? reject(err) : resolve()); });
    \\            if (e.writeTimeoutMs > 0) {
    \\              await Promise.race([wp, new Promise((_, rej) => setTimeout(() => rej(new Error("write timeout")), e.writeTimeoutMs))])
    \\                .catch((err) => { try { e.sock.destroy(); } catch (e2) {} throw Object.assign(err, { saStatus: req.tlsSpace ? -5 : 6 }); });
    \\            } else {
    \\              await wp.catch((err) => { throw Object.assign(err, { saStatus: req.tlsSpace ? -5 : 6 }); });
    \\            }
    \\            respond(0, { written: buf.length }, null);
    \\            return;
    \\          }
    \\          case "stream_set_read_timeout": {
    \\            const e = getSock(req.id); if (!e) return fail(2, "bad handle");
    \\            e.readTimeoutMs = req.timeoutMs || 0;
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "stream_set_write_timeout": {
    \\            const e = getSock(req.id); if (!e) return fail(2, "bad handle");
    \\            e.writeTimeoutMs = req.timeoutMs || 0;
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "reverse": {
    \\            const names = await dns.promises.reverse(req.host).catch(() => null);
    \\            if (!names || names.length === 0) return fail(7, "reverse lookup failed");
    \\            respond(0, { name: names[0] }, null);
    \\            return;
    \\          }
    \\          case "udp_set_broadcast": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            try { e.sock.setBroadcast(req.enabled !== 0); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "udp_set_ttl": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            try { e.sock.setTTL(req.ttl); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "udp_set_multicast_ttl": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            try { e.sock.setMulticastTTL(req.ttl); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "udp_set_multicast_loop": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            try { e.sock.setMulticastLoop(req.enabled !== 0); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "tcp_set_nodelay": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "tcp") return fail(2, "bad handle");
    \\            try { e.sock.setNoDelay(req.enabled !== 0); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "tcp_set_keepalive": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "tcp") return fail(2, "bad handle");
    \\            try { e.sock.setKeepAlive(req.enabled !== 0); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "tls_connect": {
    \\            let sock;
    \\            try { sock = await tlsUpgrade(null, req); }
    \\            catch (err) { return fail(tlsErrStatus(err), err.message); }
    \\            const e = streamEntry("tls", sock);
    \\            const id = nextId++;
    \\            socks.set(id, e);
    \\            respond(0, { id: id }, null);
    \\            return;
    \\          }
    \\          case "tls_start": {
    \\            const e0 = getSock(req.id); if (!e0 || e0.kind !== "tcp") return fail(-22, "bad plain handle");
    \\            e0.sock.removeAllListeners("data");
    \\            e0.chunks = []; e0.buffered = 0; e0.waiter = null;
    \\            let sock;
    \\            try { sock = await tlsUpgrade(e0.sock, req); }
    \\            catch (err) { return fail(tlsErrStatus(err), err.message); }
    \\            e0.kind = "tls";
    \\            e0.sock = sock;
    \\            sock.on("data", (chunk) => { e0.chunks.push(chunk); e0.buffered += chunk.length; if (e0.waiter) { const w = e0.waiter; e0.waiter = null; w(); } });
    \\            const done = () => { e0.eof = true; if (e0.waiter) { const w = e0.waiter; e0.waiter = null; w(); } };
    \\            sock.on("end", done); sock.on("close", done); sock.on("error", done);
    \\            respond(0, { id: req.id }, null);
    \\            return;
    \\          }
    \\          default:
    \\            return fail(8, "unknown op " + op);
    \\        }
    \\      } catch (err) {
    \\        const st = err && err.saStatus !== undefined ? err.saStatus : 6;
    \\        fail(st, err && err.message ? err.message : err);
    \\      }
    \\    }
    \\    parentPort.on("message", () => {
    \\      const jlen = hdr[1];
    \\      const jsonText = dec.decode(data.subarray(0, jlen));
    \\      let req;
    \\      try { req = JSON.parse(jsonText); } catch (e) { fail(1, "bad request json"); return; }
    \\      const plen = req.plen || 0;
    \\      const payload = plen > 0 ? Buffer.from(data.subarray(jlen, jlen + plen)) : null;
    \\      handle(req, payload);
    \\    });
    \\  }
    \\  let BR = null, BRbad = false;
    \\  function bridgeInit() {
    \\    if (BR) return true;
    \\    if (BRbad) return false;
    \\    try {
    \\      const wt = __sa_node_builtin("node:worker_threads");
    \\      if (!wt || !wt.Worker) throw new Error("no worker_threads");
    \\      if (typeof SharedArrayBuffer === "undefined" || typeof Atomics === "undefined" || typeof Atomics.wait !== "function") throw new Error("no SAB/Atomics");
    \\      const sab = new SharedArrayBuffer(4 * 1024 * 1024);
    \\      const worker = new wt.Worker("(" + __sa_jsnet_worker.toString() + ")()", { eval: true, workerData: { sab: sab } });
    \\      worker.unref();
    \\      BR = { sab: sab, hdr: new Int32Array(sab, 0, 4), data: new Uint8Array(sab, 256), enc: new TextEncoder(), dec: new TextDecoder(), worker: worker };
    \\      return true;
    \\    } catch (e) { BRbad = true; return false; }
    \\  }
    \\  // One synchronous bridge round-trip. tlsSpace selects the error-code space
    \\  // for the unavailable-bridge failure (-1 vs 8). A 10-minute watchdog bounds
    \\  // a dead worker; a legitimately blocked socket call returns through the
    \\  // worker long before that in every realistic probe.
    \\  function bridgeCall(op, params, payload, tlsSpace) {
    \\    if (!bridgeInit()) return { status: tlsSpace ? -1 : 8, json: { error: "bridge unavailable" }, bytes: null };
    \\    const req = Object.assign({ op: op, plen: payload ? payload.length : 0 }, params || {});
    \\    const jb = BR.enc.encode(JSON.stringify(req));
    \\    if (jb.length + (payload ? payload.length : 0) > BR.data.length) return { status: tlsSpace ? -1 : 8, json: { error: "bridge payload too large" }, bytes: null };
    \\    BR.data.set(jb, 0);
    \\    if (payload) BR.data.set(payload, jb.length);
    \\    BR.hdr[1] = jb.length;
    \\    Atomics.store(BR.hdr, 0, 1);
    \\    BR.worker.postMessage({});
    \\    const deadline = Date.now() + 600000;
    \\    for (;;) {
    \\      Atomics.wait(BR.hdr, 0, 1, 1000);
    \\      if (Atomics.load(BR.hdr, 0) === 2) break;
    \\      if (Date.now() > deadline) return { status: tlsSpace ? -5 : 6, json: { error: "bridge watchdog timeout" }, bytes: null };
    \\    }
    \\    const jlen = BR.hdr[2];
    \\    const plen = BR.hdr[3];
    \\    const json = JSON.parse(BR.dec.decode(BR.data.subarray(0, jlen)));
    \\    const bytes = plen > 0 ? Buffer.from(BR.data.subarray(jlen, jlen + plen)) : null;
    \\    Atomics.store(BR.hdr, 0, 0);
    \\    return { status: json.__status, json: json, bytes: bytes };
    \\  }
    \\  // ---------- net handle registry (SA-side) ----------
    \\  // byBridge: live bridge id -> SA handle. detached: bridge ids whose SA
    \\  // handle was consumed by fd_into_raw (start_tls upgrades them in place
    \\  // and mints a fresh SA handle, mirroring native fd ownership transfer).
    \\  const NET = { h: new Map(), next: 1, byBridge: new Map(), detached: new Map() };
    \\  function netReg(entry) { const h = NET.next++; NET.h.set(h, entry); if (entry.bridgeId !== undefined && entry.bridgeId !== null) NET.byBridge.set(entry.bridgeId, h); return h; }
    \\  function netGet(h) { return NET.h.get(h) || null; }
    \\  function netDel(h) { const e = NET.h.get(h); if (e) { NET.h.delete(h); if (e.bridgeId !== undefined && e.bridgeId !== null) NET.byBridge.delete(e.bridgeId); } return e || null; }
    \\  // ---------- TLS config registry ----------
    \\  const TLS = { configs: new Map(), next: 1, processCas: [] };
    \\  function tlsCfgNew() { const c = { serverName: null, caFiles: [], caPems: [], insecure: false, verifySelfSigned: false }; const h = TLS.next++; TLS.configs.set(h, c); return h; }
    \\  function tlsCfgGet(h) { return TLS.configs.get(h) || null; }
    \\  function tlsCfgFree(h) { return TLS.configs.delete(h); }
    \\  // Resolve the effective CA PEM list for a connect: process-wide CAs +
    \\  // config ca_files (read eagerly; a missing file fails the connect with -5)
    \\  // + config ca_pems. Returns { pems } or { err }.
    \\  function tlsResolveCas(cfg) {
    \\    const pems = TLS.processCas.slice();
    \\    if (cfg) {
    \\      for (const f of cfg.caFiles) {
    \\        try {
    \\          const fs = __sa_node_builtin("node:fs");
    \\          pems.push(fs.readFileSync(bToStr(f), "utf8"));
    \\        } catch (e) { return { err: -5 }; }
    \\      }
    \\      for (const p of cfg.caPems) pems.push(p);
    \\    }
    \\    return { pems: pems };
    \\  }
    \\  // Count usable certificates in a PEM string (-1 on any decode failure).
    \\  // Native skips some unparseable classes; this port fails loudly instead
    \\  // (documented approximation; probes use valid certificates).
    \\  function pemUsableCount(pemStr) {
    \\    try {
    \\      const crypto = __sa_node_builtin("node:crypto");
    \\      if (!crypto || !crypto.X509Certificate) return -1;
    \\      let count = 0;
    \\      const begin = "-----BEGIN CERTIFICATE-----";
    \\      const end = "-----END CERTIFICATE-----";
    \\      let pos = 0;
    \\      while (true) {
    \\        const b = pemStr.indexOf(begin, pos);
    \\        if (b < 0) break;
    \\        const e = pemStr.indexOf(end, b + begin.length);
    \\        if (e < 0) return -1;
    \\        const b64 = pemStr.slice(b + begin.length, e).replace(/\s/g, "");
    \\        let der;
    \\        try { der = Buffer.from(b64, "base64"); } catch (err) { return -1; }
    \\        try { new crypto.X509Certificate(der); count++; } catch (err) { return -1; }
    \\        pos = e + end.length;
    \\      }
    \\      return count;
    \\    } catch (err) { return -1; }
    \\  }
    \\  // Full TLS connect path shared by connect / connect_config / start_tls.
    \\  // cfg: null (default) or a config object. upgradeBridgeId: null (fresh
    \\  // dial) or a bridge socket id to upgrade in place. Returns
    \\  // { status, saHandle } ; on upgrade failure the plain entry is consumed
    \\  // (closed), mirroring the native fd-ownership rule.
    \\  function tlsConnectFull(hostStr, portNum, cfg, upgradeBridgeId) {
    \\    if (!hostStr || hostStr.length === 0) return { status: -22 };
    \\    // Fresh dials need a valid port; upgrades reuse the existing socket.
    \\    if ((upgradeBridgeId === null || upgradeBridgeId === undefined) &&
    \\        (portNum === 0 || portNum > 65535)) return { status: -22 };
    \\    let serverName = null, insecure = false, verifySelfSigned = false;
    \\    if (cfg) {
    \\      serverName = (cfg.serverName === null) ? null : bToStr(cfg.serverName);
    \\      insecure = cfg.insecure; verifySelfSigned = cfg.verifySelfSigned;
    \\      if (insecure && (verifySelfSigned || serverName !== null)) return { status: -22 };
    \\      if (verifySelfSigned && (cfg.caFiles.length > 0 || cfg.caPems.length > 0)) return { status: -22 };
    \\    }
    \\    const cas = tlsResolveCas(cfg);
    \\    if (cas.err) return { status: cas.err };
    \\    const params = { host: hostStr, port: portNum, timeoutMs: 0,
    \\      serverName: serverName, caPems: cas.pems,
    \\      insecure: insecure, verifySelfSigned: verifySelfSigned };
    \\    if (upgradeBridgeId === null || upgradeBridgeId === undefined) {
    \\      const r = bridgeCall("tls_connect", params, null, true);
    \\      if (r.status !== 0) return { status: r.status };
    \\      const h = netReg({ kind: "tls", bridgeId: r.json.id, readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() });
    \\      return { status: 0, saHandle: h };
    \\    }
    \\    const saH = NET.byBridge.get(upgradeBridgeId);
    \\    const entry = (saH !== undefined) ? NET.h.get(saH) : null;
    \\    const detached = NET.detached.get(upgradeBridgeId) === true;
    \\    if (!detached && (!entry || entry.kind !== "tcp")) return { status: -22 };
    \\    if (detached && entry) return { status: -22 };
    \\    const r = bridgeCall("tls_start", Object.assign({ id: upgradeBridgeId }, params), null, true);
    \\    if (r.status !== 0) {
    \\      if (entry) { NET.h.delete(saH); NET.byBridge.delete(upgradeBridgeId); }
    \\      NET.detached.delete(upgradeBridgeId);
    \\      bridgeCall("sock_close", { id: upgradeBridgeId }, null, true);
    \\      return { status: r.status };
    \\    }
    \\    if (detached) {
    \\      NET.detached.delete(upgradeBridgeId);
    \\      const h = netReg({ kind: "tls", bridgeId: upgradeBridgeId, readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() });
    \\      return { status: 0, saHandle: h };
    \\    }
    \\    entry.kind = "tls";
    \\    return { status: 0, saHandle: saH };
    \\  }
    \\  // ---------- netinfo ----------
    \\  function netinfoJson() {
    \\    const os = __sa_node_builtin("node:os");
    \\    const ifs = os.networkInterfaces();
    \\    const out = [];
    \\    for (const name of Object.keys(ifs)) {
    \\      for (const a of ifs[name]) {
    \\        if (!a.address) continue;
    \\        const fam = (a.family === "IPv4" || a.family === 4) ? 2 : 10;
    \\        let netmask = a.netmask || "";
    \\        let prefix = 0;
    \\        if (fam === 2 && netmask) {
    \\          const parts = netmask.split(".");
    \\          for (const p of parts) {
    \\            let v = parseInt(p, 10);
    \\            while (v) { prefix += (v & 1); v >>= 1; }
    \\          }
    \\        } else if (fam === 10 && a.cidr) {
    \\          const slash = a.cidr.indexOf("/");
    \\          if (slash >= 0) prefix = parseInt(a.cidr.slice(slash + 1), 10);
    \\        }
    \\        let broadcast = null;
    \\        if (fam === 2 && !a.internal && netmask) {
    \\          const ap = a.address.split(".").map((x) => parseInt(x, 10));
    \\          const mp = netmask.split(".").map((x) => parseInt(x, 10));
    \\          if (ap.length === 4 && mp.length === 4) {
    \\            broadcast = ap.map((v, i) => (v | (~mp[i] & 255))).join(".");
    \\          }
    \\        }
    \\        out.push({ name: name, family: fam, address: a.address, netmask: netmask,
    \\          prefix_len: prefix, broadcast: broadcast, scope_id: (a.scopeid !== undefined && a.scopeid !== null) ? a.scopeid : 0 });
    \\      }
    \\    }
    \\    return bFromStr(JSON.stringify(out));
    \\  }
    \\  // String out-pair helper (mirrors sa_cookie.zig outString): null value ->
    \\  // NOT_FOUND with ptr 0 / len 0; otherwise a fresh linear-memory copy.
    \\  // Uses the generated module's own memory helpers (defined in the header,
    \\  // which precedes this chunk in every emitted program).
    \\  function outStr(out_ptr, out_len, bytesOrNull) {
    \\    if (bytesOrNull === null) { __sa_store_ptr(out_ptr, 0); __sa_store_i64(out_len, 0n); return 3; }
    \\    const p = __sa_alloc(bytesOrNull.length);
    \\    __sa_u8.set(bytesOrNull, p);
    \\    __sa_store_ptr(out_ptr, p);
    \\    __sa_store_i64(out_len, BigInt(bytesOrNull.length));
    \\    return 0;
    \\  }
    \\  return {
    \\    outStr: outStr,
    \\    validCookieName: validCookieName, validCookieValue: validCookieValue,
    \\    validDomainAttr: validDomainAttr,
    \\    bFromStr: bFromStr, bToStr: bToStr, bEq: bEq, bEqFold: bEqFold, bLower: bLower,
    \\    bTrimOws: bTrimOws, bConcat: bConcat,
    \\    parseCookieDate: parseCookieDate, formatImfFixdate: formatImfFixdate,
    \\    parseSetCookie: parseSetCookie, serializeCookie: serializeCookie,
    \\    cloneCookie: cloneCookie, mkCookie: mkCookie,
    \\    domainMatch: domainMatch, pathMatch: pathMatch, defaultPath: defaultPath,
    \\    splitUrl: splitUrl, originTrustworthy: originTrustworthy,
    \\    ckErrSet: ckErrSet, ckErrClear: ckErrClear, ckErrGet: ckErrGet,
    \\    ckReg: ckReg, ckGet: ckGet, ckFree: ckFree,
    \\    jarReg: jarReg, jarGet: jarGet, jarFree: jarFree, mkJar: mkJar,
    \\    jarStore: jarStore, jarHeader: jarHeader, jarSaveText: jarSaveText,
    \\    jarLoad: jarLoad, jarEvict: jarEvict,
    \\    parseHeaderPair: parseHeaderPair, headerPairCount: headerPairCount, headerPairAt: headerPairAt,
    \\    bridgeCall: bridgeCall, netReg: netReg, netGet: netGet, netDel: netDel, NET: NET,
    \\    tlsCfgNew: tlsCfgNew, tlsCfgGet: tlsCfgGet, tlsCfgFree: tlsCfgFree,
    \\    tlsResolveCas: tlsResolveCas, pemUsableCount: pemUsableCount,
    \\    tlsConnectFull: tlsConnectFull, TLS: TLS, netinfoJson: netinfoJson
    \\  };
    \\})();
;
