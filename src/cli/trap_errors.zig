const std = @import("std");
const copyTextBuf = @import("text.zig").copyTextBuf;
const lineAt = @import("text.zig").lineAt;
const PackageTrapInfo = @import("types.zig").PackageTrapInfo;
const flattener = @import("../flattener.zig");
const trap = @import("../common/trap.zig");

pub fn trapFromFlattenError(source_path: []const u8, source: []const u8, err: anyerror, err_report: flattener.ErrorReport) trap.TrapReport {
    const last_line = err_report.line;
    const forbidden = flattener.findFirstForbiddenLine(source);
    const line_no = if (forbidden) |hit| hit.line_no else last_line orelse 1;
    const line_text = lineAt(source, line_no);
    const source_text = if (line_text) |line| std.mem.trimEnd(u8, line, "\r") else null;
    const source_text_buf: [256]u8 = std.mem.zeroes([256]u8);
    const original_text_buf: [256]u8 = std.mem.zeroes([256]u8);
    const file_buf: [128]u8 = std.mem.zeroes([128]u8);
    const bad_token_buf: [64]u8 = std.mem.zeroes([64]u8);
    // Origin-aware rendering: when the flattener recorded the failing
    // line's origin file, positions are in that file's coordinates. Text
    // and context may only be read from `source` when the origin is the
    // root file itself; for a foreign origin the root text at that line
    // number would be an unrelated line (the misattribution behind
    // DEF-ASM-AND-NAMED-REG), so it is suppressed instead.
    const origin_path = err_report.path;
    const origin_is_root = origin_path == null or std.mem.eql(u8, origin_path.?, source_path);
    var origin_file_buf: [128]u8 = std.mem.zeroes([128]u8);
    if (origin_path) |path| copyTextBuf(&origin_file_buf, path);
    var macro_token_buf: [64]u8 = std.mem.zeroes([64]u8);
    if (err_report.detail) |detail_text| copyTextBuf(&macro_token_buf, detail_text);
    const macro_line_no = last_line orelse 1;
    const macro_line_text = if (origin_is_root) lineAt(source, macro_line_no) else null;
    var report: trap.TrapReport = switch (err) {
        error.ForbiddenSyntax => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = if (forbidden) |hit| @as(u32, @intCast(hit.hit.column)) else null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = if (forbidden) |hit| switch (hit.hit.token) {
                .brace_open => "{",
                .brace_close => "}",
                .keyword_if => "if",
                .keyword_else => "else",
                .keyword_while => "while",
                .keyword_for => "for",
                .property_chain => ".",
            } else null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "forbidden syntax detected during flattening",
            .hint = if (forbidden) |hit| forbiddenHint(hit.hit) else null,
        },
        error.UnsupportedType => .{
            .trap = .unsupported_type,
            .trap_code = trap.trapCode(.unsupported_type),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = if (line_text) |lt| if (std.mem.indexOfAny(u8, lt, "*&")) |idx| @as(u32, @intCast(idx + 1)) else null else null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = firstBadTokenForTypeLine(source_text),
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "unsupported type annotation during flattening",
            .hint = unsupportedTypeHint(line_text),
            .repair_alternatives = .{ null, null, null },
            .repair_alternatives_len = 0,
        },
        error.InvalidImportPath, error.PackageNotResolved, error.AmbiguousPackageVersion, error.PrecompiledArtifactRejected, error.InvalidPath => .{
            .trap = .import_resolution_failed,
            .trap_code = trap.trapCode(.import_resolution_failed),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = importResolutionMessage(err),
            .hint = importResolutionHint(line_text, err),
            .repair_action = "fix-import",
            .repair_hint = importResolutionHint(line_text, err),
            .repair_confidence = if (err == error.InvalidImportPath) "high" else "medium",
            .repair_alternatives = .{ null, null, null },
            .repair_alternatives_len = 0,
        },
        error.OutOfMemory => .{
            .trap = .arena_oom,
            .trap_code = trap.trapCode(.arena_oom),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "out of memory while flattening",
            .hint = null,
        },
        error.ImportCycle => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "import cycle detected during flattening",
            .hint = "break the cycle in imported files or inline the shared definitions",
        },
        error.DuplicateDef => .{
            .trap = .duplicate_def,
            .trap_code = trap.trapCode(.duplicate_def),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "duplicate definition detected during flattening",
            .hint = null,
        },
        error.UnknownNpmBindTarget => .{
            .trap = .import_resolution_failed,
            .trap_code = trap.trapCode(.import_resolution_failed),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "#npm_bind target must name a declared @extern function",
            .hint = "bind each #npm_bind line to an @extern with the same name; npm bindings are only honored by `sa build-js`",
            .repair_action = "fix-import",
            .repair_hint = "bind each #npm_bind line to an @extern with the same name",
            .repair_confidence = "high",
            .repair_alternatives = .{ null, null, null },
            .repair_alternatives_len = 0,
        },
        error.MacroRecursionLimit => .{
            .trap = .macro_recursion_limit,
            .trap_code = trap.trapCode(.macro_recursion_limit),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "macro recursion limit exceeded",
            .hint = null,
        },
        error.InvalidAtomicOrdering => .{
            .trap = .invalid_atomic_ordering,
            .trap_code = trap.trapCode(.invalid_atomic_ordering),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "invalid atomic ordering",
            .hint = null,
        },
        error.UndefinedMacro => .{
            .trap = .undefined_macro,
            .trap_code = trap.trapCode(.undefined_macro),
            .file_buf = if (origin_is_root) file_buf else origin_file_buf,
            .file = if (origin_is_root) source_path else null,
            .line = macro_line_no,
            .source_line = macro_line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = macro_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "macro is not defined",
            .hint = "EXPAND names a macro with no [MACRO] definition in the imported sources; if the macro comes from sa_std, the std in use is older than the program being assembled (std version skew)",
        },
        error.InvalidMacroInvocation, error.InvalidMacroDefinitionContext, error.UnbalancedMacro, error.UnbalancedRep, error.InvalidSyntax => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = @errorName(err),
            .hint = switch (err) {
                error.InvalidMacroInvocation => "check the macro name, argument count, and comma-separated expansion syntax",
                error.InvalidMacroDefinitionContext => "macro definitions are only allowed at top level",
                error.UnbalancedMacro => "make sure [MACRO] has a matching [END_MACRO]",
                error.UnbalancedRep => "make sure [REP] has a matching [END_REP]",
                error.InvalidSyntax => "check the flattened line syntax and operand ordering",
                else => null,
            },
        },
        else => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = @errorName(err),
            .hint = "flattening failed before a public trap mapping was available",
        },
    };
    if (err == error.UndefinedMacro) {
        if (macro_line_text) |line| {
            setLineText(&report, sourceExcerpt(line));
            fillContextWindow(&report, source, macro_line_no);
        }
    } else if (origin_is_root) {
        if (line_text) |line| {
            const excerpt = sourceExcerpt(line);
            setLineText(&report, excerpt);
            fillContextWindow(&report, source, line_no);
        }
    }
    switch (report.trap) {
        .forbidden_syntax => {
            report.repair_action = "rewrite";
            report.repair_hint = "lower structured control flow into labels, branches, and explicit register moves";
            report.repair_confidence = "high";
            setRepairAlternatives(&report, &.{ "jmp", "label", "ptr" });
        },
        .unsupported_type => {
            report.repair_action = "inspect-signature";
            report.repair_hint = "replace unsupported structured types with ptr or a primitive SA type and adjust the callee signature";
            report.repair_confidence = "medium";
            setRepairAlternatives(&report, &.{ "ptr", "u64", "i64" });
        },
        .import_resolution_failed => {
            report.repair_action = "pin-import";
            report.repair_hint = "pin one package ref or replace the import path with a unique local package identity";
            report.repair_confidence = "medium";
            setRepairAlternatives(&report, &.{ "sa.mod", "local package", "pinned ref" });
        },
        .duplicate_def => {
            report.repair_action = "rename-def";
            report.repair_hint = "change one of the conflicting names or namespace the symbol";
            report.repair_confidence = "high";
        },
        .macro_recursion_limit => {
            report.repair_action = "simplify-macro";
            report.repair_hint = "reduce recursive expansion depth or inline the macro body";
            report.repair_confidence = "medium";
        },
        .invalid_atomic_ordering => {
            report.repair_action = "adjust-ordering";
            report.repair_hint = "use a success ordering that is not weaker than the failure ordering";
            report.repair_confidence = "medium";
        },
        else => {},
    }
    return report;
}

pub fn trapFromPackagePreflightError(err: anyerror) ?trap.TrapReport {
    const info: PackageTrapInfo = switch (err) {
        error.ForbiddenGlobalConfig => .{
            .kind = .forbidden_global_config,
            .message = "global SA package configuration is forbidden for reproducible builds",
            .hint = "remove ~/.sa/config.toml, ~/.sa/mirror.toml, and /etc/sa/*.toml; use sa.mod or project .sa_env mirrors instead",
        },
        error.SumHashMismatch => .{
            .kind = .sum_hash_mismatch,
            .message = "sa.sum does not match the resolved dependency tree",
            .hint = "run sa install to refresh sa.sum, or restore the vendored dependency source",
        },
        error.UpstreamShaMismatch => .{
            .kind = .upstream_sha_mismatch,
            .message = "package source hash does not match the granted requirement",
            .hint = "verify the dependency source and update the manifest hash only after auditing it",
        },
        error.UnauthorizedPrimitive => .{
            .kind = .unauthorized_primitive,
            .message = "package uses @sys_* outside its declared grants",
            .hint = "add the explicit grant only after auditing the package source, or remove the dependency",
        },
        error.MissingTtyForConfirmation => .{
            .kind = .missing_tty_for_confirmation,
            .message = "high-risk package confirmation requires an interactive TTY",
            .hint = "run from a real terminal and type the full package URL, or use CI taint mode deliberately",
        },
        error.BlockedRiskUnconfirmed => .{
            .kind = .blocked_risk_unconfirmed,
            .message = "high-risk package confirmation did not match the full package URL",
            .hint = "rerun and type the exact package URL shown in the review banner",
        },
        error.AutoApproveForbidden => .{
            .kind = .blocked_risk_unconfirmed,
            .message = "package risk confirmation cannot be auto-approved",
            .hint = "remove --yes/--auto-approve and type the exact package URL in a TTY",
        },
        error.UnauditedRiskBlocked => .{
            .kind = .blocked_risk_unconfirmed,
            .message = "CI blocked a high-risk unaudited package",
            .hint = "audit the dependency locally or rerun CI with --allow-unaudited-risks to produce a tainted build",
        },
        error.PackageNotResolved, error.InvalidImportPath, error.AmbiguousPackageVersion, error.PrecompiledArtifactRejected, error.InvalidPath => .{
            .kind = .import_resolution_failed,
            .message = importResolutionMessage(err),
            .hint = importResolutionHint(null, err),
        },
        else => return null,
    };

    return .{
        .trap = info.kind,
        .trap_code = trap.trapCode(info.kind),
        .line = 1,
        .source_line = 1,
        .registers = &.{},
        .message = info.message,
        .hint = info.hint,
    };
}

pub fn importResolutionMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidImportPath => "invalid import path",
        error.PackageNotResolved => "import path could not be resolved",
        error.AmbiguousPackageVersion => "multiple package versions match this import",
        error.PrecompiledArtifactRejected => "precompiled artifact imports are not allowed",
        error.InvalidPath => "invalid path while resolving an import",
        else => "import resolution failed",
    };
}

pub fn forbiddenHint(hit: flattener.ForbiddenHit) []const u8 {
    return switch (hit.token) {
        .brace_open, .brace_close => "remove brace syntax and flatten the control flow into labels and jumps",
        .keyword_if, .keyword_else, .keyword_while, .keyword_for => "replace control-flow keywords with labels and jmp/br instructions",
        .property_chain => "replace dotted property access with explicit SSA registers or constant expansion",
    };
}

pub fn importResolutionHint(line: ?[]const u8, err: anyerror) []const u8 {
    _ = line;
    return switch (err) {
        error.InvalidImportPath => "use a valid relative `.sa` or package identity without `../`, empty segments, or whitespace",
        error.PackageNotResolved => "check the import path, package identity, local vendor tree, and package cache",
        error.AmbiguousPackageVersion => "pin the required package ref in `sa.mod` so the resolver can choose one version",
        error.PrecompiledArtifactRejected => "depend on the source package instead of a precompiled artifact",
        error.InvalidPath => "check the project root or import path for filesystem errors",
        else => "check the import path, package identity, local vendor tree, and package cache",
    };
}

pub fn firstBadTokenForTypeLine(line: ?[]const u8) ?[]const u8 {
    const text = line orelse return null;
    if (std.mem.indexOf(u8, text, "*")) |idx| {
        const tail = text[idx..];
        const end = std.mem.indexOfAny(u8, tail, " \t,)]}") orelse tail.len;
        return tail[0..end];
    }
    if (std.mem.indexOf(u8, text, "bool")) |_| return "bool";
    if (std.mem.indexOf(u8, text, "string")) |_| return "string";
    if (std.mem.indexOf(u8, text, "&")) |_| return "&";
    return null;
}

pub fn unsupportedTypeHint(line: ?[]const u8) []const u8 {
    if (lineContains(line, "call @")) {
        return "inspect the callee declaration referenced by this call site; the unsupported annotation is usually in the imported signature";
    }
    if (lineContains(line, "@import")) {
        return "inspect the imported file for unsupported primitive names or ownership suffixes";
    }
    return "check the primitive type names and ownership suffixes in the declaration";
}

pub fn setLineText(report: *trap.TrapReport, text: []const u8) void {
    report.source_text = null;
    report.original_text = null;
    report.source_text_buf = std.mem.zeroes([256]u8);
    report.original_text_buf = std.mem.zeroes([256]u8);
    copyTextBuf(&report.source_text_buf, text);
    copyTextBuf(&report.original_text_buf, text);
}

pub fn lineContains(line: ?[]const u8, needle: []const u8) bool {
    return if (line) |text| std.mem.indexOf(u8, text, needle) != null else false;
}

pub fn sourceExcerpt(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
}

pub fn fillContextWindow(report: *trap.TrapReport, source: []const u8, center_line: u32) void {
    const start_line = if (center_line > 2) center_line - 2 else 1;
    var idx: usize = 0;
    var line_no = start_line;
    while (idx < report.context.len and line_no <= center_line + 2) : ({
        idx += 1;
        line_no += 1;
    }) {
        if (lineAt(source, line_no)) |line| {
            copyContextLine(report, idx, line_no, sourceExcerpt(line));
        }
    }
    report.context_len = @intCast(idx);
}

pub fn copyContextLine(report: *trap.TrapReport, idx: usize, line_no: u32, text: []const u8) void {
    if (idx >= report.context.len) return;
    report.context[idx].line = line_no;
    report.context[idx].text = null;
    report.context[idx].text_buf = std.mem.zeroes([256]u8);
    copyTextBuf(&report.context[idx].text_buf, std.mem.trimEnd(u8, text, "\r"));
}

pub fn setRepairAlternatives(report: *trap.TrapReport, alternatives: []const []const u8) void {
    const limit = @min(report.repair_alternatives.len, alternatives.len);
    report.repair_alternatives_len = @intCast(limit);
    for (0..limit) |idx| {
        report.repair_alternatives[idx] = null;
        report.repair_alternatives_buf[idx] = std.mem.zeroes([64]u8);
        copyTextBuf(&report.repair_alternatives_buf[idx], alternatives[idx]);
        const end = std.mem.indexOfScalar(u8, report.repair_alternatives_buf[idx][0..], 0) orelse alternatives[idx].len;
        report.repair_alternatives[idx] = report.repair_alternatives_buf[idx][0..end];
    }
}

pub fn setFile(report: *trap.TrapReport, source_path: []const u8) void {
    report.file = null;
    report.file_buf = std.mem.zeroes([128]u8);
    copyTextBuf(&report.file_buf, source_path);
}
