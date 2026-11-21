//! SAB fragment container: the host-side encode path for compiler
//! surface fragments (for example one std macro expansion wrapped in a
//! synthetic function, as produced by the SLA SAB codegen for Vec method
//! calls).
//!
//! A fragment is NOT a program. Its wrapper function body references
//! placeholder registers owned by the assembling compiler (declared in
//! the contract header) and defines registers the assembler must treat
//! as fragment-owned, so the verified whole-program encoder
//! (`sa check --emit-sab`, plugin_bridge.encodeSabFromFlat) rejects it:
//! inputs trap as UnknownRegister, outputs as MemoryLeak at function
//! exit. The Zig SLA plugin sidesteps this in-process with
//! plugin_bridge.encodeSabFromFlatUnchecked; external frontends (the
//! Rust standalone) cannot. This module is the versioned host contract
//! for that encode:
//!
//!   * `sa encode-fragment` (see cli.zig) parses the contract header,
//!     validates it against the flattened wrapper body, encodes the
//!     payload with the SAME unchecked encoder implementation the
//!     plugin uses, and wraps it in this container.
//!   * The container carries the fragment magic (sab.fragment_magic),
//!     so every ordinary SAB decode entry point rejects it with
//!     error.SabFragmentNotAProgram: a bare fragment can never be
//!     built, run, or checked as a whole program. Assembly (decoding
//!     the payload and inlining the wrapper body into a real module)
//!     is the consumer's job, and the assembled module must pass the
//!     ordinary whole-module verification — there is no
//!     fragment-to-product verification bypass.
//!
//! Fragment source format: the SA text starts with a header block
//! (each line is blanked out before flattening, so line numbers and
//! byte offsets of the body are preserved):
//!
//!   #fragment 1
//!   #fragment-function: __sla_macro_fragment_0
//!   #fragment-reads: __sla_macro_arg_1
//!   #fragment-owns: __sla_macro_arg_0, tmp_0
//!   #fragment-returns: __sla_macro_arg_0
//!   #fragment-caller: sla-rust 0.1.0
//!
//! `reads` names the external registers the body uses without defining
//! (the assembler's placeholders, including the wrapper's parameters);
//! `owns` names every register the body defines; `returns` names the
//! registers whose value/ownership is handed back to the assembler
//! (a subset of reads + owns; a read register not in `returns` is
//! consumed by the fragment). The host recomputes all three sets from
//! the flattened body and rejects any mismatch, plus program surface
//! in the fragment's own text (a @main, @test, @export, @ffi_wrapper,
//! or @gpu declaration, or a second function).

const std = @import("std");
pub const flattener = @import("flattener.zig");
const sab = @import("sab.zig");
const plugin_bridge = @import("plugin_bridge.zig");
pub const instruction = @import("common/instruction.zig");

/// Fragment container format version. Frontends pin this version; a
/// mismatch is a loud error, never a silent reinterpretation.
pub const format_major: u8 = 1;
pub const format_minor: u8 = 0;

/// The dedicated subcommand that produces fragment containers. The
/// name deliberately says "fragment", not "unchecked"/"no-verify":
/// the product is a different artifact kind, not a relaxed program.
pub const subcommand_name = "encode-fragment";

pub const ParseError = error{
    FragmentMissingHeader,
    FragmentVersionMismatch,
    FragmentMissingField,
    FragmentUnknownDirective,
    FragmentDuplicateDirective,
    FragmentDuplicateRegister,
    FragmentBadHeaderLine,
    FragmentHeaderAfterCode,
    OutOfMemory,
};

pub const DecodeError = error{
    InvalidFragmentMagic,
    UnsupportedFragmentVersion,
    TruncatedFragment,
    OutOfMemory,
};

pub const Contract = struct {
    /// Name of the wrapper function whose body is the fragment.
    function_name: []const u8,
    /// External registers the body reads (assembler-owned).
    reads: []const []const u8,
    /// Registers the body defines (fragment-owned).
    owns: []const []const u8,
    /// Registers handed back to the assembler (subset of reads+owns).
    returns: []const []const u8,
    /// Calling frontend name + version (attribution record).
    caller: []const u8,

    pub fn deinit(self: *Contract, allocator: std.mem.Allocator) void {
        allocator.free(self.function_name);
        freeNames(allocator, self.reads);
        freeNames(allocator, self.owns);
        freeNames(allocator, self.returns);
        allocator.free(self.caller);
        self.* = undefined;
    }
};

fn freeNames(allocator: std.mem.Allocator, names: []const []const u8) void {
    for (names) |name| allocator.free(name);
    if (names.len != 0) allocator.free(names);
}

pub const ParsedFragment = struct {
    contract: Contract,
    /// The source with every header line blanked to spaces (newlines
    /// kept), so flattening reports the body's original line numbers.
    stripped_source: []u8,

    pub fn deinit(self: *ParsedFragment, allocator: std.mem.Allocator) void {
        self.contract.deinit(allocator);
        allocator.free(self.stripped_source);
        self.* = undefined;
    }
};

const Directive = enum { version, function, reads, owns, returns, caller };

pub fn isIdentByte(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

fn validRegisterName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (c == ' ' or c == '\t' or c == '\r' or c == ',' or c == ':') return false;
    }
    return true;
}

fn parseRegisterList(allocator: std.mem.Allocator, raw: []const u8) ParseError![]const []const u8 {
    var names = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit();
    }
    const trimmed = std.mem.trim(u8, raw, " \t\r");
    if (trimmed.len == 0) return try names.toOwnedSlice();
    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |part| {
        const name = std.mem.trim(u8, part, " \t\r");
        if (!validRegisterName(name)) return error.FragmentBadHeaderLine;
        for (names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) return error.FragmentDuplicateRegister;
        }
        try names.append(try allocator.dupe(u8, name));
    }
    return try names.toOwnedSlice();
}

/// Parse the contract header at the top of a fragment source. Header
/// lines may be interleaved with blank lines but must all precede the
/// first code line; a `#fragment` line after code is an error.
pub fn parseFragmentSource(allocator: std.mem.Allocator, source: []const u8) ParseError!ParsedFragment {
    var stripped = try allocator.dupe(u8, source);
    errdefer allocator.free(stripped);

    var seen_version = false;
    var seen_bits: u32 = 0;
    var function_name: ?[]const u8 = null;
    var reads: ?[]const []const u8 = null;
    var owns: ?[]const []const u8 = null;
    var returns: ?[]const []const u8 = null;
    var caller: ?[]const u8 = null;
    errdefer {
        if (function_name) |name| allocator.free(name);
        if (reads) |list| freeNames(allocator, list);
        if (owns) |list| freeNames(allocator, list);
        if (returns) |list| freeNames(allocator, list);
        if (caller) |text| allocator.free(text);
    }

    var in_header = true;
    var line_start: usize = 0;
    while (line_start <= source.len) {
        const line_end = std.mem.indexOfScalarPos(u8, source, line_start, '\n') orelse source.len;
        const line = source[line_start..line_end];
        const trimmed = std.mem.trim(u8, line, " \t\r");
        const is_fragment_line = std.mem.startsWith(u8, trimmed, "#fragment");
        if (is_fragment_line and !in_header) return error.FragmentHeaderAfterCode;
        if (in_header and trimmed.len != 0 and !is_fragment_line) in_header = false;
        if (is_fragment_line and in_header) {
            // Blank the header line in the stripped copy (keep bytes
            // before it and the newline itself untouched).
            const lead = line.len - std.mem.trimStart(u8, line, " \t\r").len;
            @memset(stripped[line_start .. line_start + lead + trimmed.len], ' ');

            if (std.mem.startsWith(u8, trimmed, "#fragment-")) {
                const rest = trimmed["#fragment-".len..];
                const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return error.FragmentBadHeaderLine;
                const key = rest[0..colon];
                const value = rest[colon + 1 ..];
                const directive: Directive = if (std.mem.eql(u8, key, "function"))
                    .function
                else if (std.mem.eql(u8, key, "reads"))
                    .reads
                else if (std.mem.eql(u8, key, "owns"))
                    .owns
                else if (std.mem.eql(u8, key, "returns"))
                    .returns
                else if (std.mem.eql(u8, key, "caller"))
                    .caller
                else
                    return error.FragmentUnknownDirective;
                const directive_bit = @as(u32, 1) << @intFromEnum(directive);
                if (seen_bits & directive_bit != 0) return error.FragmentDuplicateDirective;
                seen_bits |= directive_bit;
                switch (directive) {
                    .function => {
                        const name = std.mem.trim(u8, value, " \t\r");
                        if (!validRegisterName(name)) return error.FragmentBadHeaderLine;
                        function_name = try allocator.dupe(u8, name);
                    },
                    .reads => reads = try parseRegisterList(allocator, value),
                    .owns => owns = try parseRegisterList(allocator, value),
                    .returns => returns = try parseRegisterList(allocator, value),
                    .caller => {
                        const text = std.mem.trim(u8, value, " \t\r");
                        if (text.len == 0) return error.FragmentBadHeaderLine;
                        caller = try allocator.dupe(u8, text);
                    },
                    .version => unreachable,
                }
            } else if (std.mem.startsWith(u8, trimmed, "#fragment") and
                trimmed.len > "#fragment".len and
                (trimmed["#fragment".len] == ' ' or trimmed["#fragment".len] == '\t'))
            {
                if (seen_version) return error.FragmentDuplicateDirective;
                const value = std.mem.trim(u8, trimmed["#fragment".len..], " \t\r");
                const dot = std.mem.indexOfScalar(u8, value, '.');
                const major_text = if (dot) |d| value[0..d] else value;
                const major = std.fmt.parseInt(u32, major_text, 10) catch return error.FragmentBadHeaderLine;
                if (dot) |d| {
                    const minor = std.fmt.parseInt(u32, value[d + 1 ..], 10) catch return error.FragmentBadHeaderLine;
                    if (minor != format_minor) return error.FragmentVersionMismatch;
                }
                if (major != format_major) return error.FragmentVersionMismatch;
                seen_version = true;
            } else {
                return error.FragmentBadHeaderLine;
            }
        }
        if (line_end == source.len) break;
        line_start = line_end + 1;
    }

    if (!seen_version) return error.FragmentMissingHeader;
    if (function_name == null or reads == null or owns == null or caller == null) {
        return error.FragmentMissingField;
    }

    return .{
        .contract = .{
            .function_name = function_name.?,
            .reads = reads.?,
            .owns = owns.?,
            .returns = returns orelse &.{},
            .caller = caller.?,
        },
        .stripped_source = stripped,
    };
}

// ---------------------------------------------------------------------
// Contract validation against the flattened wrapper body
// ---------------------------------------------------------------------

pub const ViolationKind = @import("sab_fragment_validate.zig").ViolationKind;

pub const Violation = @import("sab_fragment_validate.zig").Violation;

pub const Validation = @import("sab_fragment_validate.zig").Validation;

pub const violation = @import("sab_fragment_validate.zig").violation;

/// Instruction kinds whose operands[0] (when a register) is a
/// definition of that register. Every other register operand is a
/// use. This mirrors the operand layout the verifier relies on.
pub const isDefiningKind = @import("sab_fragment_validate.zig").isDefiningKind;

pub const isDeclKind = @import("sab_fragment_validate.zig").isDeclKind;

pub const nameInList = @import("sab_fragment_validate.zig").nameInList;

/// SA primitive type and keyword names: these can appear inside a
/// call's textual argument list (casts, literals) but are never
/// register names.
pub const isPrimitiveTextName = @import("sab_fragment_validate.zig").isPrimitiveTextName;

/// Strictly scan a call instruction's textual operand
/// (`@callee(arg, &arg2, ^arg3)`) for argument registers. Every
/// identifier in argument position counts as a use, whether or not
/// it was interned into the symbol table — a placeholder that occurs
/// only here is exactly the case the contract exists to catch.
/// Callee tokens (after '@', or directly before '(') and primitive
/// type/keyword names never count.
pub const scanCallText = @import("sab_fragment_validate.zig").scanCallText;

/// Scan the fragment's own (stripped) source text for declarations.
/// The fragment's own text may declare exactly one function — the
/// wrapper named by the contract. Program surface (@main, @test,
/// @export) and other function kinds (@ffi_wrapper, @gpu) are
/// rejected; @import/@const/@extern lines are environment, not
/// declarations of the fragment itself. Lines inside [MACRO] blocks
/// are macro text, not declarations.
pub const scanOwnDeclarations = @import("sab_fragment_validate.zig").scanOwnDeclarations;

/// Validate a flattened fragment against its contract. `flat` is the
/// flatten of the header-stripped source (imports included — only the
/// wrapper function's body is the fragment; imported functions are
/// its environment). Returns the first violation found, with set
/// mismatches reported in sorted register-name order so diagnostics
/// are deterministic.
pub const validateContract = @import("sab_fragment_validate.zig").validateContract;

pub fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

pub fn containsName(list: []const []const u8, name: []const u8) bool {
    return nameInList(list, name);
}

// ---------------------------------------------------------------------
// Container encode/decode
// ---------------------------------------------------------------------

pub const FragmentArtifact = struct {
    contract: Contract,
    /// SHA-256 of the fragment source text (attribution record).
    source_sha256: [32]u8,
    /// SAB version of the payload encoding.
    sab_major: u8,
    sab_minor: u8,
    /// The unchecked-encoded SAB module bytes (borrowed from the
    /// container bytes passed to decodeFragment).
    payload: []const u8,

    pub fn deinit(self: *FragmentArtifact, allocator: std.mem.Allocator) void {
        self.contract.deinit(allocator);
        self.* = undefined;
    }
};

/// Encode a validated fragment: the payload is produced by
/// plugin_bridge.encodeSabFromFlatUnchecked — the exact
/// implementation the Zig plugin uses in-process (there is no second
/// encoder) — and wrapped in the fragment container.
pub fn encodeFragment(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
    contract: *const Contract,
    source_text: []const u8,
) ![]u8 {
    const payload = try plugin_bridge.encodeSabFromFlatUnchecked(allocator, flat);
    defer allocator.free(payload);
    var source_sha256: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source_text, &source_sha256, .{});
    return encodeContainer(allocator, contract, &source_sha256, payload);
}

pub fn encodeContainer(
    allocator: std.mem.Allocator,
    contract: *const Contract,
    source_sha256: *const [32]u8,
    payload: []const u8,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    try writer.writeAll(sab.fragment_magic);
    try writer.writeByte(format_major);
    try writer.writeByte(format_minor);
    try writer.writeByte(sab.version_major);
    try writer.writeByte(sab.version_minor);
    try writer.writeAll(source_sha256);
    try writeName(writer, contract.caller);
    try writeName(writer, contract.function_name);
    try writeNameList(writer, contract.reads);
    try writeNameList(writer, contract.owns);
    try writeNameList(writer, contract.returns);
    try sab.encodeUleb128(writer, payload.len);
    try writer.writeAll(payload);
    return try out.toOwnedSlice();
}

fn writeName(writer: *std.Io.Writer, name: []const u8) !void {
    try sab.encodeUleb128(writer, name.len);
    try writer.writeAll(name);
}

fn writeNameList(writer: *std.Io.Writer, names: []const []const u8) !void {
    try sab.encodeUleb128(writer, names.len);
    for (names) |name| try writeName(writer, name);
}

const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    fn readByte(self: *Cursor) DecodeError!u8 {
        if (self.index >= self.bytes.len) return error.TruncatedFragment;
        const byte = self.bytes[self.index];
        self.index += 1;
        return byte;
    }

    fn readSlice(self: *Cursor, len: usize) DecodeError![]const u8 {
        if (len > self.bytes.len - self.index) return error.TruncatedFragment;
        const start = self.index;
        self.index += len;
        return self.bytes[start..self.index];
    }

    fn readUleb(self: *Cursor) DecodeError!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        while (true) {
            const byte = try self.readByte();
            result |= @as(u64, byte & 0x7f) << shift;
            if ((byte & 0x80) == 0) return result;
            if (shift >= 63) return error.TruncatedFragment;
            shift += 7;
        }
    }

    fn readName(self: *Cursor, allocator: std.mem.Allocator) DecodeError![]const u8 {
        const len = try self.readUleb();
        if (len > self.bytes.len) return error.TruncatedFragment;
        return try allocator.dupe(u8, try self.readSlice(@intCast(len)));
    }

    fn readNameList(self: *Cursor, allocator: std.mem.Allocator) DecodeError![]const []const u8 {
        const count = try self.readUleb();
        if (count > self.bytes.len) return error.TruncatedFragment;
        const names = try allocator.alloc([]const u8, @intCast(count));
        var filled: usize = 0;
        errdefer {
            for (names[0..filled]) |name| allocator.free(name);
            allocator.free(names);
        }
        while (filled < count) : (filled += 1) {
            names[filled] = try self.readName(allocator);
        }
        return names;
    }
};

pub fn isFragment(bytes: []const u8) bool {
    return sab.isFragmentBytes(bytes);
}

/// Decode a fragment container. Version fields are checked loudly:
/// a container written by a newer fragment format, or carrying a
/// payload in a SAB version this host does not speak, is rejected
/// instead of being reinterpreted.
pub fn decodeFragment(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!FragmentArtifact {
    if (!sab.isFragmentBytes(bytes)) return error.InvalidFragmentMagic;
    var cursor = Cursor{ .bytes = bytes, .index = sab.fragment_magic.len };
    const fmt_major = try cursor.readByte();
    const fmt_minor = try cursor.readByte();
    if (fmt_major != format_major or fmt_minor != format_minor) return error.UnsupportedFragmentVersion;
    const sab_major = try cursor.readByte();
    const sab_minor = try cursor.readByte();
    if (sab_major != sab.version_major) return error.UnsupportedFragmentVersion;
    const sha_bytes = try cursor.readSlice(32);
    var source_sha256: [32]u8 = undefined;
    @memcpy(&source_sha256, sha_bytes);
    const caller = try cursor.readName(allocator);
    errdefer allocator.free(caller);
    const function_name = try cursor.readName(allocator);
    errdefer allocator.free(function_name);
    const reads = try cursor.readNameList(allocator);
    errdefer freeNames(allocator, reads);
    const owns = try cursor.readNameList(allocator);
    errdefer freeNames(allocator, owns);
    const returns = try cursor.readNameList(allocator);
    errdefer freeNames(allocator, returns);
    const payload_len = try cursor.readUleb();
    if (payload_len > cursor.bytes.len) return error.TruncatedFragment;
    const payload = try cursor.readSlice(@intCast(payload_len));
    return .{
        .contract = .{
            .function_name = function_name,
            .reads = reads,
            .owns = owns,
            .returns = returns,
            .caller = caller,
        },
        .source_sha256 = source_sha256,
        .sab_major = sab_major,
        .sab_minor = sab_minor,
        .payload = payload,
    };
}
