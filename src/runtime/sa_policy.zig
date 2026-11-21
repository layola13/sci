//! Runtime permission policy core (sala 16_policy, phase 1).
//!
//! Pure decision logic for the SA runtime permission system: policy
//! model, JSON configuration parsing, per-category CLI-override merge,
//! resource matchers, isolated policy contexts with narrowing-only
//! derivation, one-time authorization tokens, and audit events.
//!
//! This module performs no I/O and reads no clock: callers pass the
//! current time in, and callers emit the audit events decide() implies.
//! Interception wiring in the sa_std acquisition paths is a separate
//! step; nothing here is reachable from program code yet.

const std = @import("std");

pub const Category = enum { net, fs, env, run, time, random };

pub const Mode = enum { allow, deny, allow_list, audit, ask };

pub const CategoryPolicy = struct {
    mode: Mode = .deny,
    /// net: "host:port" / "cidr:port" entries; env: key names;
    /// run: program paths. Unused for fs/time/random.
    allow: [][]u8 = &.{},
    /// fs only.
    read: [][]u8 = &.{},
    /// fs only.
    write: [][]u8 = &.{},

    pub fn deinit(self: *CategoryPolicy, allocator: std.mem.Allocator) void {
        for (self.allow) |entry| allocator.free(entry);
        allocator.free(self.allow);
        for (self.read) |entry| allocator.free(entry);
        allocator.free(self.read);
        for (self.write) |entry| allocator.free(entry);
        allocator.free(self.write);
        self.* = undefined;
    }

    fn clone(self: *const CategoryPolicy, allocator: std.mem.Allocator) !CategoryPolicy {
        return .{
            .mode = self.mode,
            .allow = try dupeStrings(allocator, self.allow),
            .read = try dupeStrings(allocator, self.read),
            .write = try dupeStrings(allocator, self.write),
        };
    }
};

pub const Policy = struct {
    net: CategoryPolicy = .{},
    fs: CategoryPolicy = .{},
    env: CategoryPolicy = .{},
    run: CategoryPolicy = .{},
    time: CategoryPolicy = .{},
    random: CategoryPolicy = .{},
    audit_sink: ?[]u8 = null,
    audit_events: [][]u8 = &.{},

    pub fn deinit(self: *Policy, allocator: std.mem.Allocator) void {
        self.net.deinit(allocator);
        self.fs.deinit(allocator);
        self.env.deinit(allocator);
        self.run.deinit(allocator);
        self.time.deinit(allocator);
        self.random.deinit(allocator);
        if (self.audit_sink) |sink| allocator.free(sink);
        for (self.audit_events) |entry| allocator.free(entry);
        allocator.free(self.audit_events);
        self.* = undefined;
    }

    pub fn categoryPolicy(self: *Policy, category: Category) *CategoryPolicy {
        return switch (category) {
            .net => &self.net,
            .fs => &self.fs,
            .env => &self.env,
            .run => &self.run,
            .time => &self.time,
            .random => &self.random,
        };
    }

    pub fn categoryPolicyConst(self: *const Policy, category: Category) *const CategoryPolicy {
        return switch (category) {
            .net => &self.net,
            .fs => &self.fs,
            .env => &self.env,
            .run => &self.run,
            .time => &self.time,
            .random => &self.random,
        };
    }

    pub fn clone(self: *const Policy, allocator: std.mem.Allocator) !Policy {
        var out = Policy{
            .net = try self.net.clone(allocator),
            .fs = try self.fs.clone(allocator),
            .env = try self.env.clone(allocator),
            .run = try self.run.clone(allocator),
            .time = try self.time.clone(allocator),
            .random = try self.random.clone(allocator),
            .audit_sink = if (self.audit_sink) |sink| try allocator.dupe(u8, sink) else null,
            .audit_events = try dupeStrings(allocator, self.audit_events),
        };
        errdefer out.deinit(allocator);
        return out;
    }
};

/// Per-category overrides from the higher-priority source (the command
/// line). A non-null category replaces the base category wholesale;
/// a null category inherits the base (design: merge is per category,
/// never per field).
pub const PolicyPatch = struct {
    net: ?CategoryPolicy = null,
    fs: ?CategoryPolicy = null,
    env: ?CategoryPolicy = null,
    run: ?CategoryPolicy = null,
    time: ?CategoryPolicy = null,
    random: ?CategoryPolicy = null,

    pub fn deinit(self: *PolicyPatch, allocator: std.mem.Allocator) void {
        if (self.net) |*cp| cp.deinit(allocator);
        if (self.fs) |*cp| cp.deinit(allocator);
        if (self.env) |*cp| cp.deinit(allocator);
        if (self.run) |*cp| cp.deinit(allocator);
        if (self.time) |*cp| cp.deinit(allocator);
        if (self.random) |*cp| cp.deinit(allocator);
        self.* = undefined;
    }
};

pub fn applyPatch(allocator: std.mem.Allocator, base: *const Policy, patch: *const PolicyPatch) !Policy {
    var out = try base.clone(allocator);
    errdefer out.deinit(allocator);
    if (patch.net) |*cp| {
        out.net.deinit(allocator);
        out.net = try cp.clone(allocator);
    }
    if (patch.fs) |*cp| {
        out.fs.deinit(allocator);
        out.fs = try cp.clone(allocator);
    }
    if (patch.env) |*cp| {
        out.env.deinit(allocator);
        out.env = try cp.clone(allocator);
    }
    if (patch.run) |*cp| {
        out.run.deinit(allocator);
        out.run = try cp.clone(allocator);
    }
    if (patch.time) |*cp| {
        out.time.deinit(allocator);
        out.time = try cp.clone(allocator);
    }
    if (patch.random) |*cp| {
        out.random.deinit(allocator);
        out.random = try cp.clone(allocator);
    }
    return out;
}

// ---------------------------------------------------------------------
// Resources and decisions

pub const NetResource = struct { host: []const u8, port: u16 };
pub const FsResource = struct { path: []const u8, write: bool };

pub const Resource = union(enum) {
    net: NetResource,
    fs: FsResource,
    env: []const u8,
    run: []const u8,
    time,
    random,

    pub fn category(self: Resource) Category {
        return switch (self) {
            .net => .net,
            .fs => .fs,
            .env => .env,
            .run => .run,
            .time => .time,
            .random => .random,
        };
    }
};

pub const Decision = enum {
    allow,
    deny,
    /// Allowed, and the caller must write an audit event.
    allow_audit,
    /// Category mode is ask and phase 1 has no adjudication callback:
    /// denied, with an audit event recording the unhandled ask.
    deny_ask_unhandled,
};

pub fn decide(policy: *const Policy, resource: Resource) Decision {
    const cp = policy.categoryPolicyConst(resource.category());
    return switch (cp.mode) {
        .allow => .allow,
        .deny => .deny,
        .audit => .allow_audit,
        .ask => .deny_ask_unhandled,
        .allow_list => switch (resource) {
            .net => |net| if (netListAllows(cp.allow, net)) .allow else .deny,
            .fs => |fsr| blk: {
                const list = if (fsr.write) cp.write else cp.read;
                break :blk if (fsListAllows(list, fsr.path)) .allow else .deny;
            },
            .env => |key| if (stringListHas(cp.allow, key)) .allow else .deny,
            .run => |program| if (stringListHas(cp.allow, program)) .allow else .deny,
            .time, .random => .deny,
        },
    };
}

/// Canonical identity of a resource, used for one-time token binding
/// and as the audit event's resource field. Metadata only: for env this
/// is the key NAME, never the value.
pub const resourceKey = @import("sa_policy_decide.zig").resourceKey;

// ---------------------------------------------------------------------
// Matchers

pub const stringListHas = @import("sa_policy_decide.zig").stringListHas;

pub const fsListAllows = @import("sa_policy_decide.zig").fsListAllows;

pub const parseIpv4 = @import("sa_policy_decide.zig").parseIpv4;

pub const netEntryMatches = @import("sa_policy_decide.zig").netEntryMatches;

pub const netListAllows = @import("sa_policy_decide.zig").netListAllows;

// ---------------------------------------------------------------------
// Narrowing (context derivation may only tighten)

pub const modeNarrowsTo = @import("sa_policy_decide.zig").modeNarrowsTo;

pub const listSubset = @import("sa_policy_decide.zig").listSubset;

pub const fsEntriesSubset = @import("sa_policy_decide.zig").fsEntriesSubset;

pub const categoryNarrowsTo = @import("sa_policy_decide.zig").categoryNarrowsTo;

pub const policyNarrowsTo = @import("sa_policy_decide.zig").policyNarrowsTo;

// ---------------------------------------------------------------------
// Contexts and one-time tokens

pub const Token = struct {
    category: Category,
    key: []u8,
    minted_ns: i64,
    ttl_ns: i64,

    fn deinit(self: *Token, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        self.* = undefined;
    }
};

pub const default_token_ttl_ns: i64 = 120 * std.time.ns_per_s;

pub const PolicyContext = struct {
    id: u64,
    policy: Policy,
    tokens: std.array_list.Managed(Token),

    pub fn init(allocator: std.mem.Allocator, id: u64, policy: Policy) PolicyContext {
        return .{
            .id = id,
            .policy = policy,
            .tokens = std.array_list.Managed(Token).init(allocator),
        };
    }

    pub fn deinit(self: *PolicyContext, allocator: std.mem.Allocator) void {
        self.policy.deinit(allocator);
        for (self.tokens.items) |*token| token.deinit(allocator);
        self.tokens.deinit();
        self.* = undefined;
    }

    /// Derive a child context. Fails with error.PolicyWidening unless
    /// the child policy narrows (or equals) this context's policy in
    /// every category: authority only ever flows downward.
    pub fn deriveChild(self: *const PolicyContext, allocator: std.mem.Allocator, id: u64, child_policy: Policy) !PolicyContext {
        if (!policyNarrowsTo(&child_policy, &self.policy)) return error.PolicyWidening;
        return PolicyContext.init(allocator, id, child_policy);
    }

    pub fn mintToken(self: *PolicyContext, allocator: std.mem.Allocator, category: Category, key: []const u8, now_ns: i64, ttl_ns: i64) !void {
        try self.tokens.append(.{
            .category = category,
            .key = try allocator.dupe(u8, key),
            .minted_ns = now_ns,
            .ttl_ns = ttl_ns,
        });
    }

    /// First matching call consumes the token (replay-proof). Expired
    /// tokens never match and are purged on sight.
    pub fn consumeToken(self: *PolicyContext, allocator: std.mem.Allocator, category: Category, key: []const u8, now_ns: i64) bool {
        var i: usize = 0;
        while (i < self.tokens.items.len) {
            const token = &self.tokens.items[i];
            if (now_ns > token.minted_ns + token.ttl_ns) {
                var expired = self.tokens.orderedRemove(i);
                expired.deinit(allocator);
                continue;
            }
            if (token.category == category and std.mem.eql(u8, token.key, key)) {
                var used = self.tokens.orderedRemove(i);
                used.deinit(allocator);
                return true;
            }
            i += 1;
        }
        return false;
    }

    /// Decide with the one-time-token layer: when the base policy
    /// allows (or audits) the call, the token is left untouched; when
    /// the base policy would deny it, a matching token allows exactly
    /// this one call and is consumed.
    pub fn decideWithTokens(self: *PolicyContext, allocator: std.mem.Allocator, resource: Resource, now_ns: i64) Decision {
        const base = decide(&self.policy, resource);
        if (base == .allow or base == .allow_audit) return base;
        const key = resourceKey(allocator, resource) catch return base;
        defer allocator.free(key);
        if (self.consumeToken(allocator, resource.category(), key, now_ns)) return .allow;
        return base;
    }
};

// ---------------------------------------------------------------------
// Runtime gate state
//
// The host installs at most one active context (the deployment's
// current policy context) plus an audit sink. With no context
// installed the gate allows everything: the standard library alone
// cannot refuse to run, so the "no policy, no start" rule is
// enforced by the host surface that installs contexts. Context
// switching is the host's job; the gate reads whichever context is
// active at the acquisition point.

pub var active_context: ?*PolicyContext = null;
pub var audit_sink: ?*const fn (line: []const u8) void = null;

pub fn installContext(context: *PolicyContext) void {
    active_context = context;
}

pub fn clearContext() void {
    active_context = null;
}

pub fn installAuditSink(sink: ?*const fn (line: []const u8) void) void {
    audit_sink = sink;
}

fn emitAudit(allocator: std.mem.Allocator, context: *const PolicyContext, resource: Resource, decision_text: []const u8, source: []const u8, now_ns: i64) void {
    const sink = audit_sink orelse return;
    const key = resourceKey(allocator, resource) catch return;
    defer allocator.free(key);
    const event = AuditEvent{
        .context_id = context.id,
        .category = resource.category(),
        .resource = key,
        .decision = decision_text,
        .source = source,
    };
    const line = event.formatJsonLine(allocator, now_ns) catch return;
    defer allocator.free(line);
    sink(line);
}

/// The interception entry point used by sa_std acquisition paths.
/// Emits audit events for denials, audited allows, unhandled asks,
/// and token consumption; plain policy allows stay silent.
pub fn gate(allocator: std.mem.Allocator, resource: Resource, now_ns: i64) bool {
    const context = active_context orelse return true;
    const base = decide(&context.policy, resource);
    switch (base) {
        .allow => return true,
        .allow_audit => {
            emitAudit(allocator, context, resource, "allow", "policy-audit", now_ns);
            return true;
        },
        .deny, .deny_ask_unhandled => {
            const key = resourceKey(allocator, resource) catch null;
            defer if (key) |owned| allocator.free(owned);
            if (key) |key_text| {
                if (context.consumeToken(allocator, resource.category(), key_text, now_ns)) {
                    emitAudit(allocator, context, resource, "allow", "token", now_ns);
                    return true;
                }
            }
            emitAudit(allocator, context, resource, "deny", if (base == .deny_ask_unhandled) "ask-unhandled" else "policy", now_ns);
            return false;
        },
    }
}

// ---------------------------------------------------------------------
// Audit events

pub const AuditEvent = struct {
    context_id: u64,
    category: Category,
    resource: []const u8,
    decision: []const u8,
    source: []const u8,

    /// One JSON object per line (JSONL), same style as the toolchain's
    /// structured diagnostics. Metadata only, by construction of the
    /// resource keys.
    pub fn formatJsonLine(self: AuditEvent, allocator: std.mem.Allocator, ts_ns: i64) ![]u8 {
        const escaped = try escapeJson(allocator, self.resource);
        defer allocator.free(escaped);
        return try std.fmt.allocPrint(allocator, "{{\"ts_ns\":{d},\"context\":{d},\"category\":\"{s}\",\"resource\":\"{s}\",\"decision\":\"{s}\",\"source\":\"{s}\"}}\n", .{ ts_ns, self.context_id, @tagName(self.category), escaped, self.decision, self.source });
    }
};

pub const escapeJson = @import("sa_policy_json.zig").escapeJson;

// ---------------------------------------------------------------------
// JSON configuration parsing (strict: unknown keys are errors, a typo
// in a security policy must never silently change its meaning)

pub const jsonString = @import("sa_policy_json.zig").jsonString;

pub const jsonObject = @import("sa_policy_json.zig").jsonObject;

pub const collectJsonStrings = @import("sa_policy_json.zig").collectJsonStrings;

pub const parseMode = @import("sa_policy_json.zig").parseMode;

pub const parseCategoryPolicy = @import("sa_policy_json.zig").parseCategoryPolicy;

pub const parsePolicyJson = @import("sa_policy_json.zig").parsePolicyJson;

pub const TokenSpec = @import("sa_policy_json.zig").TokenSpec;

/// Strict parser for the SA_POLICY_TOKENS_JSON surface:
/// [{"category":"fs","key":"read:/abs/path","ttl_s":120}, ...]
/// ttl_s is optional (1..3600); anything unknown is InvalidPolicy.
pub const parseTokenSpecsJson = @import("sa_policy_json.zig").parseTokenSpecsJson;

pub const freeTokenSpecs = @import("sa_policy_json.zig").freeTokenSpecs;

/// Mints every spec into the context (the host-side approval already
/// happened wherever the specs came from; this is the delivery step).
pub const mintTokenSpecs = @import("sa_policy_json.zig").mintTokenSpecs;

pub const categoryFromName = @import("sa_policy_json.zig").categoryFromName;

pub const dupeStrings = @import("sa_policy_json.zig").dupeStrings;

// ---------------------------------------------------------------------
// Tests

test "policy tokens json: parse, mint, consume once" {
    const allocator = std.testing.allocator;
    const specs = try parseTokenSpecsJson(allocator, "[{\"category\":\"fs\",\"key\":\"read:/tmp/x\",\"ttl_s\":60}]");
    defer freeTokenSpecs(allocator, specs);
    try std.testing.expectEqual(@as(usize, 1), specs.len);
    try std.testing.expectEqual(Category.fs, specs[0].category);
    try std.testing.expectEqual(@as(i64, 60 * std.time.ns_per_s), specs[0].ttl_ns);

    var policy = try parsePolicyJson(allocator, "{\"permissions\":{\"fs\":{\"mode\":\"ask\"}}}");
    defer policy.deinit(allocator);
    var context = PolicyContext.init(allocator, 7, policy);
    defer context.deinit(allocator);
    try mintTokenSpecs(&context, allocator, specs, 1000);
    // ask -> deny without a token for other resources
    try std.testing.expectEqual(Decision.deny_ask_unhandled, context.decideWithTokens(allocator, .{ .fs = .{ .path = "/tmp/y", .write = false } }, 2000));
    // token allows exactly once
    try std.testing.expectEqual(Decision.allow, context.decideWithTokens(allocator, .{ .fs = .{ .path = "/tmp/x", .write = false } }, 2000));
    try std.testing.expectEqual(Decision.deny_ask_unhandled, context.decideWithTokens(allocator, .{ .fs = .{ .path = "/tmp/x", .write = false } }, 2000));
}

test "policy tokens json: strict shape" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidPolicy, parseTokenSpecsJson(allocator, "{}"));
    try std.testing.expectError(error.InvalidPolicy, parseTokenSpecsJson(allocator, "[{\"category\":\"bogus\",\"key\":\"x\"}]"));
    try std.testing.expectError(error.InvalidPolicy, parseTokenSpecsJson(allocator, "[{\"category\":\"fs\"}]"));
    try std.testing.expectError(error.InvalidPolicy, parseTokenSpecsJson(allocator, "[{\"category\":\"fs\",\"key\":\"x\",\"ttl_s\":0}]"));
    try std.testing.expectError(error.InvalidPolicy, parseTokenSpecsJson(allocator, "[{\"category\":\"fs\",\"key\":\"x\",\"extra\":1}]"));
}

test "policy: absent categories default to deny" {
    const allocator = std.testing.allocator;
    var policy = try parsePolicyJson(allocator, "{}");
    defer policy.deinit(allocator);
    try std.testing.expectEqual(Decision.deny, decide(&policy, .{ .env = "HOME" }));
    try std.testing.expectEqual(Decision.deny, decide(&policy, .time));
}

test "policy: design-draft config parses and decides per category" {
    const allocator = std.testing.allocator;
    const text =
        \\{ "permissions": {
        \\  "net":    { "mode": "allow-list", "allow": ["api.bank.com:443", "10.0.0.0/8:*"] },
        \\  "fs":     { "read": ["/data/inbox"], "write": ["/data/outbox"] },
        \\  "env":    { "allow": ["APP_ENV", "TZ"] },
        \\  "run":    { "mode": "deny" },
        \\  "time":   { "mode": "allow" },
        \\  "random": { "mode": "audit" }
        \\}, "audit": { "sink": "file:///var/log/sa-audit.jsonl", "events": ["deny", "ask"] } }
    ;
    var policy = try parsePolicyJson(allocator, text);
    defer policy.deinit(allocator);
    try std.testing.expectEqual(Decision.allow, decide(&policy, .{ .net = .{ .host = "api.bank.com", .port = 443 } }));
    try std.testing.expectEqual(Decision.deny, decide(&policy, .{ .net = .{ .host = "api.bank.com", .port = 80 } }));
    try std.testing.expectEqual(Decision.allow, decide(&policy, .{ .net = .{ .host = "10.3.4.5", .port = 9999 } }));
    try std.testing.expectEqual(Decision.deny, decide(&policy, .{ .net = .{ .host = "11.0.0.1", .port = 80 } }));
    try std.testing.expectEqual(Decision.allow, decide(&policy, .{ .fs = .{ .path = "/data/inbox/a.txt", .write = false } }));
    try std.testing.expectEqual(Decision.deny, decide(&policy, .{ .fs = .{ .path = "/data/inbox2/a.txt", .write = false } }));
    try std.testing.expectEqual(Decision.deny, decide(&policy, .{ .fs = .{ .path = "/data/inbox/a.txt", .write = true } }));
    try std.testing.expectEqual(Decision.allow, decide(&policy, .{ .env = "TZ" }));
    try std.testing.expectEqual(Decision.deny, decide(&policy, .{ .env = "SECRET_KEY" }));
    try std.testing.expectEqual(Decision.deny, decide(&policy, .{ .run = "/bin/sh" }));
    try std.testing.expectEqual(Decision.allow, decide(&policy, .time));
    try std.testing.expectEqual(Decision.allow_audit, decide(&policy, .random));
    try std.testing.expectEqualStrings("file:///var/log/sa-audit.jsonl", policy.audit_sink.?);
}

test "policy: unknown category, mode, or field is an error, never a silent default" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidPolicy, parsePolicyJson(allocator, "{\"permissions\":{\"netx\":{\"mode\":\"allow\"}}}"));
    try std.testing.expectError(error.InvalidPolicy, parsePolicyJson(allocator, "{\"permissions\":{\"net\":{\"mode\":\"permit\"}}}"));
    try std.testing.expectError(error.InvalidPolicy, parsePolicyJson(allocator, "{\"permissions\":{\"env\":{\"reads\":[\"X\"]}}}"));
    try std.testing.expectError(error.InvalidPolicy, parsePolicyJson(allocator, "{\"permissionz\":{}}"));
}

test "policy: CLI patch replaces whole categories only" {
    const allocator = std.testing.allocator;
    var base = try parsePolicyJson(allocator, "{\"permissions\":{\"env\":{\"allow\":[\"A\"]},\"net\":{\"mode\":\"deny\"}}}");
    defer base.deinit(allocator);
    var patch = PolicyPatch{};
    defer patch.deinit(allocator);
    patch.env = .{ .mode = .allow_list, .allow = try dupeStrings(allocator, &.{"B"}) };
    var merged = try applyPatch(allocator, &base, &patch);
    defer merged.deinit(allocator);
    try std.testing.expectEqual(Decision.deny, decide(&merged, .{ .env = "A" }));
    try std.testing.expectEqual(Decision.allow, decide(&merged, .{ .env = "B" }));
    try std.testing.expectEqual(Decision.deny, decide(&merged, .{ .net = .{ .host = "x", .port = 1 } }));
}

test "policy: one-time token allows exactly one matching call" {
    const allocator = std.testing.allocator;
    const policy = try parsePolicyJson(allocator, "{}");
    var ctx = PolicyContext.init(allocator, 7, policy);
    defer ctx.deinit(allocator);
    try ctx.mintToken(allocator, .env, "OPENAI_API_KEY", 1_000, default_token_ttl_ns);
    try std.testing.expectEqual(Decision.allow, ctx.decideWithTokens(allocator, .{ .env = "OPENAI_API_KEY" }, 2_000));
    try std.testing.expectEqual(Decision.deny, ctx.decideWithTokens(allocator, .{ .env = "OPENAI_API_KEY" }, 3_000));
    // A token minted for one resource never covers another.
    try ctx.mintToken(allocator, .env, "OTHER", 1_000, default_token_ttl_ns);
    try std.testing.expectEqual(Decision.deny, ctx.decideWithTokens(allocator, .{ .env = "OPENAI_API_KEY" }, 2_000));
    // Expired tokens do not match.
    try ctx.mintToken(allocator, .env, "LATE", 1_000, 500);
    try std.testing.expectEqual(Decision.deny, ctx.decideWithTokens(allocator, .{ .env = "LATE" }, 2_000));
}

test "policy: context derivation may only narrow" {
    const allocator = std.testing.allocator;
    const parent_policy = try parsePolicyJson(allocator, "{\"permissions\":{\"fs\":{\"read\":[\"/data\"],\"write\":[]},\"net\":{\"mode\":\"deny\"}}}");
    var parent = PolicyContext.init(allocator, 1, parent_policy);
    defer parent.deinit(allocator);

    const child_policy = try parsePolicyJson(allocator, "{\"permissions\":{\"fs\":{\"read\":[\"/data/inbox\"],\"write\":[]},\"net\":{\"mode\":\"deny\"}}}");
    var child = try parent.deriveChild(allocator, 2, child_policy);
    defer child.deinit(allocator);
    try std.testing.expectEqual(Decision.allow, decide(&child.policy, .{ .fs = .{ .path = "/data/inbox/x", .write = false } }));
    try std.testing.expectEqual(Decision.deny, decide(&child.policy, .{ .fs = .{ .path = "/data/other", .write = false } }));

    var widening = try parsePolicyJson(allocator, "{\"permissions\":{\"net\":{\"mode\":\"allow\"}}}");
    defer widening.deinit(allocator);
    try std.testing.expectError(error.PolicyWidening, parent.deriveChild(allocator, 3, widening));
}

test "policy: audit event renders as one JSON line with escaped resource" {
    const allocator = std.testing.allocator;
    const event = AuditEvent{ .context_id = 3, .category = .env, .resource = "WEIRD\"KEY", .decision = "deny", .source = "policy" };
    const line = try event.formatJsonLine(allocator, 42);
    defer allocator.free(line);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"resource\":\"WEIRD\\\"KEY\"") != null);
    try std.testing.expect(std.mem.endsWith(u8, line, "\n"));
}

var captured_audit: std.array_list.Managed([]u8) = undefined;
var captured_allocator: std.mem.Allocator = undefined;

fn captureAuditLine(line: []const u8) void {
    captured_audit.append(captured_allocator.dupe(u8, line) catch return) catch {};
}

test "policy gate: no context installed allows everything" {
    clearContext();
    installAuditSink(null);
    try std.testing.expect(gate(std.testing.allocator, .{ .env = "ANYTHING" }, 0));
}

test "policy gate: denial is audited, token allows exactly once, base allow keeps token" {
    const allocator = std.testing.allocator;
    captured_audit = std.array_list.Managed([]u8).init(allocator);
    captured_allocator = allocator;
    defer {
        for (captured_audit.items) |line| allocator.free(line);
        captured_audit.deinit();
    }
    installAuditSink(captureAuditLine);
    defer installAuditSink(null);

    const policy = try parsePolicyJson(allocator, "{\"permissions\":{\"env\":{\"allow\":[\"PUBLIC\"]}}}");
    var ctx = PolicyContext.init(allocator, 9, policy);
    defer ctx.deinit(allocator);
    installContext(&ctx);
    defer clearContext();

    // Denied by policy, audited once.
    try std.testing.expect(!gate(allocator, .{ .env = "SECRET" }, 100));
    try std.testing.expectEqual(@as(usize, 1), captured_audit.items.len);
    try std.testing.expect(std.mem.indexOf(u8, captured_audit.items[0], "\"decision\":\"deny\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, captured_audit.items[0], "\"resource\":\"SECRET\"") != null);

    // Base-policy allow does not consume the token.
    try ctx.mintToken(allocator, .env, "PUBLIC", 100, default_token_ttl_ns);
    try std.testing.expect(gate(allocator, .{ .env = "PUBLIC" }, 200));
    try std.testing.expectEqual(@as(usize, 1), ctx.tokens.items.len);

    // Token covers one otherwise-denied call, then it is gone.
    try ctx.mintToken(allocator, .env, "SECRET", 100, default_token_ttl_ns);
    try std.testing.expect(gate(allocator, .{ .env = "SECRET" }, 300));
    try std.testing.expect(!gate(allocator, .{ .env = "SECRET" }, 400));
    try std.testing.expectEqual(@as(usize, 3), captured_audit.items.len);
    try std.testing.expect(std.mem.indexOf(u8, captured_audit.items[1], "\"source\":\"token\"") != null);
}
