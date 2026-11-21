// JS runtime chunk (moved from src/emit_js.zig).
// Pure data: the emitted JS source text for one runtime piece.
pub const policy_runtime_js =
    \\// ---- sa policy (16_policy phase 1; JS port of sa_policy.zig) ----
    \\// Same policy JSON, same SA_POLICY_* env vars, same audit JSONL shape
    \\// and decision semantics as the native runtime. Lazily initialized on
    \\// first gated call; with no policy configured the backend stays in
    \\// legacy mode (everything allowed), exactly like the native default.
    \\const __sa_policy = (() => {
    \\  let state = null;
    \\  const CATS = ['net', 'fs', 'env', 'run', 'time', 'random'];
    \\  function env(name) {
    \\    try {
    \\      const p = globalThis.process;
    \\      if (p && p.env && typeof p.env[name] === 'string') return p.env[name];
    \\    } catch (e) {}
    \\    return null;
    \\  }
    \\  function fail(msg, code) {
    \\    try { console.error('[sa-policy] ' + msg); } catch (e) {}
    \\    try { globalThis.process.exit(code); } catch (e) {}
    \\    throw new Error(msg);
    \\  }
    \\  function auditPathOf(policy) {
    \\    const f = env('SA_AUDIT_FILE');
    \\    if (f) return f;
    \\    if (policy && typeof policy.audit_sink === 'string' && policy.audit_sink.startsWith('file://')) return policy.audit_sink.slice(7);
    \\    return null;
    \\  }
    \\  function stringList(v) {
    \\    if (!Array.isArray(v)) fail('InvalidPolicy', 2);
    \\    for (const s of v) if (typeof s !== 'string') fail('InvalidPolicy', 2);
    \\    return v.slice();
    \\  }
    \\  function parseCategory(v, category) {
    \\    if (v === null || typeof v !== 'object' || Array.isArray(v)) fail('InvalidPolicy', 2);
    \\    const out = { mode: null, allow: [], read: [], write: [] };
    \\    let hasLists = false;
    \\    for (const k of Object.keys(v)) {
    \\      if (k === 'mode') {
    \\        if (['allow', 'deny', 'allow-list', 'audit', 'ask'].indexOf(v.mode) < 0) fail('InvalidPolicy', 2);
    \\        out.mode = v.mode;
    \\      } else if (k === 'allow') {
    \\        if (category === 'fs' || category === 'time' || category === 'random') fail('InvalidPolicy', 2);
    \\        out.allow = stringList(v.allow); hasLists = true;
    \\      } else if (k === 'read') {
    \\        if (category !== 'fs') fail('InvalidPolicy', 2);
    \\        out.read = stringList(v.read); hasLists = true;
    \\      } else if (k === 'write') {
    \\        if (category !== 'fs') fail('InvalidPolicy', 2);
    \\        out.write = stringList(v.write); hasLists = true;
    \\      } else fail('InvalidPolicy', 2);
    \\    }
    \\    if (out.mode === null) out.mode = hasLists ? 'allow-list' : 'deny';
    \\    return out;
    \\  }
    \\  function parsePolicy(text) {
    \\    let root;
    \\    try { root = JSON.parse(text); } catch (e) { fail('InvalidPolicy', 2); }
    \\    if (root === null || typeof root !== 'object' || Array.isArray(root)) fail('InvalidPolicy', 2);
    \\    const policy = { audit_sink: null };
    \\    for (const k of Object.keys(root)) {
    \\      if (k === 'permissions') {
    \\        const perms = root.permissions;
    \\        if (perms === null || typeof perms !== 'object' || Array.isArray(perms)) fail('InvalidPolicy', 2);
    \\        for (const name of Object.keys(perms)) {
    \\          if (CATS.indexOf(name) < 0) fail('InvalidPolicy', 2);
    \\          policy[name] = parseCategory(perms[name], name);
    \\        }
    \\      } else if (k === 'audit') {
    \\        const a = root.audit;
    \\        if (a === null || typeof a !== 'object' || Array.isArray(a)) fail('InvalidPolicy', 2);
    \\        for (const ak of Object.keys(a)) {
    \\          if (ak === 'sink') { if (typeof a.sink !== 'string') fail('InvalidPolicy', 2); policy.audit_sink = a.sink; }
    \\          else if (ak === 'events') { if (!Array.isArray(a.events)) fail('InvalidPolicy', 2); }
    \\          else fail('InvalidPolicy', 2);
    \\        }
    \\      } else fail('InvalidPolicy', 2);
    \\    }
    \\    for (const c of CATS) if (!policy[c]) policy[c] = { mode: 'deny', allow: [], read: [], write: [] };
    \\    return policy;
    \\  }
    \\  function init() {
    \\    if (state !== null) return state;
    \\    if (env('SA_POLICY_ALLOW_ALL') === '1') {
    \\      const allowAll = { audit_sink: null };
    \\      for (const c of CATS) allowAll[c] = { mode: 'allow', allow: [], read: [], write: [] };
    \\      state = { policy: allowAll, auditPath: auditPathOf(null) };
    \\      try { console.error('[sa-policy] allow-all policy engaged via SA_POLICY_ALLOW_ALL (audit trace)'); } catch (e) {}
    \\      audit('run', 'SA_POLICY_ALLOW_ALL', 'allow-all', 'env');
    \\      return state;
    \\    }
    \\    let text = env('SA_POLICY_JSON');
    \\    if (text === null) {
    \\      const f = env('SA_POLICY_FILE');
    \\      if (f !== null) {
    \\        const fs = __sa_node_builtin('node:fs');
    \\        if (fs === null) fail('SA_POLICY_FILE is set but cannot be opened', 2);
    \\        try { text = fs.readFileSync(f, 'utf8'); } catch (e) { fail('SA_POLICY_FILE is set but cannot be opened', 2); }
    \\      }
    \\    }
    \\    if (text !== null) {
    \\      const policy = parsePolicy(text);
    \\      state = { policy: policy, auditPath: auditPathOf(policy) };
    \\      return state;
    \\    }
    \\    if (env('SA_POLICY_REQUIRED') === '1') fail('SA_POLICY_REQUIRED is set but no policy was provided (set SA_POLICY_JSON, SA_POLICY_FILE, or SA_POLICY_ALLOW_ALL=1)', 1);
    \\    state = { policy: null, auditPath: null };
    \\    return state;
    \\  }
    \\  function audit(category, resource, decision, source) {
    \\    if (!state || !state.auditPath) return;
    \\    const fs = __sa_node_builtin('node:fs');
    \\    if (fs === null) return;
    \\    const ts = (BigInt(Date.now()) * 1000000n).toString();
    \\    const line = '{"ts_ns":' + ts + ',"context":1,"category":' + JSON.stringify(category) + ',"resource":' + JSON.stringify(resource) + ',"decision":' + JSON.stringify(decision) + ',"source":' + JSON.stringify(source) + '}' + String.fromCharCode(10);
    \\    try { fs.appendFileSync(state.auditPath, line); } catch (e) {}
    \\  }
    \\  function fsListAllows(list, path) {
    \\    for (let entry of list) {
    \\      let prefix = entry;
    \\      while (prefix.endsWith('/')) prefix = prefix.slice(0, -1);
    \\      if (path === prefix) return true;
    \\      if (path.length > prefix.length && path.startsWith(prefix) && path.charAt(prefix.length) === '/') return true;
    \\    }
    \\    return false;
    \\  }
    \\  function parseIpv4(t) {
    \\    const parts = t.split('.');
    \\    if (parts.length !== 4) return null;
    \\    let v = 0;
    \\    for (const part of parts) {
    \\      if (part.length === 0 || part.length > 3) return null;
    \\      const n = Number(part);
    \\      if (!Number.isInteger(n) || n < 0 || n > 255 || String(n) !== part) return null;
    \\      v = v * 256 + n;
    \\    }
    \\    return v;
    \\  }
    \\  function netEntryMatches(entry, host, port) {
    \\    const colon = entry.lastIndexOf(':');
    \\    if (colon < 0) return false;
    \\    const eHost = entry.slice(0, colon);
    \\    const ePort = entry.slice(colon + 1);
    \\    if (ePort !== '*' && Number(ePort) !== port) return false;
    \\    const slash = eHost.indexOf('/');
    \\    if (slash >= 0) {
    \\      const prefixLen = Number(eHost.slice(slash + 1));
    \\      if (!Number.isInteger(prefixLen) || prefixLen < 0 || prefixLen > 32) return false;
    \\      const network = parseIpv4(eHost.slice(0, slash));
    \\      const hostIp = parseIpv4(host);
    \\      if (network === null || hostIp === null) return false;
    \\      if (prefixLen === 0) return true;
    \\      const div = Math.pow(2, 32 - prefixLen);
    \\      return Math.floor(network / div) === Math.floor(hostIp / div);
    \\    }
    \\    return eHost.toLowerCase() === host.toLowerCase();
    \\  }
    \\  function decide(category, resource) {
    \\    const cp = state.policy[category];
    \\    if (cp.mode === 'allow') return 'allow';
    \\    if (cp.mode === 'deny') return 'deny';
    \\    if (cp.mode === 'audit') return 'allow_audit';
    \\    if (cp.mode === 'ask') return 'deny_ask_unhandled';
    \\    // allow-list
    \\    if (resource.kind === 'net') return cp.allow.some((e) => netEntryMatches(e, resource.host, resource.port)) ? 'allow' : 'deny';
    \\    if (resource.kind === 'fs') return fsListAllows(resource.write ? cp.write : cp.read, resource.path) ? 'allow' : 'deny';
    \\    if (resource.kind === 'str') return cp.allow.indexOf(resource.value) >= 0 ? 'allow' : 'deny';
    \\    return 'deny';
    \\  }
    \\  function resourceKey(category, resource) {
    \\    if (resource.kind === 'net') return resource.host + ':' + resource.port;
    \\    if (resource.kind === 'fs') return (resource.write ? 'write:' : 'read:') + resource.path;
    \\    if (resource.kind === 'str') return resource.value;
    \\    return category;
    \\  }
    \\  function check(category, resource) {
    \\    const st = init();
    \\    if (st.policy === null) return true;
    \\    const d = decide(category, resource);
    \\    if (d === 'allow') return true;
    \\    if (d === 'allow_audit') { audit(category, resourceKey(category, resource), 'allow', 'policy-audit'); return true; }
    \\    audit(category, resourceKey(category, resource), 'deny', d === 'deny_ask_unhandled' ? 'ask-unhandled' : 'policy');
    \\    return false;
    \\  }
    \\  return { check: check };
    \\})();
    \\function __sa_policy_fs(path, write) { return __sa_policy.check('fs', { kind: 'fs', path: path, write: write }); }
    \\function __sa_policy_net(host, port) { return __sa_policy.check('net', { kind: 'net', host: host, port: port }); }
    \\function __sa_policy_unit(category) { return __sa_policy.check(category, { kind: 'unit' }); }
    \\
;
