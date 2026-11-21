const std = @import("std");
const manifest = @import("manifest.zig");
const AuditReport = @import("audit.zig").AuditReport;
const containsCapability = @import("audit.zig").containsCapability;
const riskLevelName = @import("audit.zig").riskLevelName;

pub fn writeSha256(writer: anytype, hash: [32]u8) !void {
    const encoded = std.fmt.bytesToHex(hash, .lower);
    try writer.print("sha256:{s}", .{encoded[0..]});
}

pub fn writeGrants(writer: anytype, grants: []const manifest.Capability) !void {
    try writer.writeByte('[');
    for (grants, 0..) |grant, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writer.writeAll(manifest.capabilityName(grant));
    }
    try writer.writeByte(']');
}

pub fn appendMissingCapability(list: *std.array_list.Managed(manifest.Capability), cap: manifest.Capability) !void {
    if (containsCapability(list.items, cap)) return;
    try list.append(cap);
}

pub fn missingCapabilities(allocator: std.mem.Allocator, report: AuditReport) ![]manifest.Capability {
    var missing = std.array_list.Managed(manifest.Capability).init(allocator);
    errdefer missing.deinit();
    for (report.primitives) |primitive| {
        if (primitive.granted) continue;
        if (primitive.capability) |cap| try appendMissingCapability(&missing, cap);
    }
    return try missing.toOwnedSlice();
}

pub fn writeTextReport(writer: anytype, allocator: std.mem.Allocator, report: AuditReport) !void {
    try writer.print("audit package: {s}\n", .{report.package_url});
    try writer.print("ref: {s}\n", .{report.ref});
    try writer.writeAll("source_sha256: ");
    try writeSha256(writer, report.source_sha256);
    try writer.writeByte('\n');
    try writer.print("trust_score: {d}\n", .{report.trust_score});
    try writer.print("risk: {s}\n", .{riskLevelName(report.risk_level)});
    try writer.writeAll("grants: ");
    try writeGrants(writer, report.grants);
    try writer.writeByte('\n');
    try writer.print("sys_primitives: {d}\n", .{report.primitives.len});
    for (report.primitives) |primitive| {
        try writer.print("- {s} at {s}:{d}:{d}", .{ primitive.name, primitive.file, primitive.line, primitive.col });
        if (primitive.capability) |cap| {
            try writer.print(" capability={s}", .{manifest.capabilityName(cap)});
        } else {
            try writer.writeAll(" capability=unknown");
        }
        try writer.print(" granted={}\n", .{primitive.granted});
    }

    const missing = try missingCapabilities(allocator, report);
    defer allocator.free(missing);
    if (missing.len != 0) {
        try writer.print("suggestion: require {s} @{s} ", .{ report.package_url, report.ref });
        try writeSha256(writer, report.source_sha256);
        try writer.writeAll(" grants ");
        try writeGrants(writer, missing);
        try writer.writeByte('\n');
    }
}

pub fn writeJsonString(writer: anytype, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => if (c < 0x20) {
                try writer.print("\\u{x:0>4}", .{c});
            } else {
                try writer.writeByte(c);
            },
        }
    }
    try writer.writeByte('"');
}

pub fn writeJsonReport(writer: anytype, report: AuditReport) !void {
    try writer.writeAll("{\"package\":");
    try writeJsonString(writer, report.package_url);
    try writer.writeAll(",\"ref\":");
    try writeJsonString(writer, report.ref);
    try writer.writeAll(",\"source_sha256\":\"");
    const encoded = std.fmt.bytesToHex(report.source_sha256, .lower);
    try writer.print("{s}", .{encoded[0..]});
    try writer.writeAll("\",\"trust_score\":");
    try writer.print("{d}", .{report.trust_score});
    try writer.writeAll(",\"risk\":");
    try writeJsonString(writer, riskLevelName(report.risk_level));
    try writer.writeAll(",\"grants\":[");
    for (report.grants, 0..) |grant, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writeJsonString(writer, manifest.capabilityName(grant));
    }
    try writer.writeAll("],\"primitives\":[");
    for (report.primitives, 0..) |primitive, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll("{\"name\":");
        try writeJsonString(writer, primitive.name);
        try writer.writeAll(",\"capability\":");
        if (primitive.capability) |cap| {
            try writeJsonString(writer, manifest.capabilityName(cap));
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"file\":");
        try writeJsonString(writer, primitive.file);
        try writer.print(",\"line\":{d},\"col\":{d},\"granted\":{}}}", .{ primitive.line, primitive.col, primitive.granted });
    }
    try writer.writeAll("]}\n");
}
