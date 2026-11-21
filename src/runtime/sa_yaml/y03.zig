const std = @import("std");
const sio = @import("sio");
const Fail = @import("y01.zig").Fail;
const FlowParser = @import("y04.zig").FlowParser;
const KIND_ARRAY = @import("y01.zig").KIND_ARRAY;
const Line = @import("y02.zig").Line;
const LineView = @import("y02.zig").LineView;
const MapBuilder = @import("y02.zig").MapBuilder;
const MapPart = @import("y02.zig").MapPart;
const TextCursor = @import("y01.zig").TextCursor;
const Value = @import("y01.zig").Value;
const appendFoldedBreak = @import("y01.zig").appendFoldedBreak;
const countLeadingSpaces = @import("y01.zig").countLeadingSpaces;
const deepClone = @import("y01.zig").deepClone;
const failAt = @import("y01.zig").failAt;
const failUnknownAlias = @import("y02.zig").failUnknownAlias;
const failUnsupported = @import("y01.zig").failUnsupported;
const isBlankRaw = @import("y02.zig").isBlankRaw;
const isCommentRaw = @import("y02.zig").isCommentRaw;
const isSeqStart = @import("y02.zig").isSeqStart;
const lineIndent = @import("y02.zig").lineIndent;
const null_value = @import("y01.zig").null_value;
const parseDoubleQuoted = @import("y01.zig").parseDoubleQuoted;
const parseSingleQuoted = @import("y01.zig").parseSingleQuoted;
const resolvePlainScalar = @import("y02.zig").resolvePlainScalar;
const rtrimWs = @import("y01.zig").rtrimWs;
const scanBlockKey = @import("y02.zig").scanBlockKey;
const stringValue = @import("y01.zig").stringValue;
const stripComment = @import("y01.zig").stripComment;
const stripPrefixes = @import("y02.zig").stripPrefixes;
const trimWs = @import("y01.zig").trimWs;
const validAnchorName = @import("y02.zig").validAnchorName;

pub const Parser = struct {
    alloc: std.mem.Allocator,
    lines: []const Line,
    pos: usize = 0,
    anchors: std.StringHashMapUnmanaged(Value) = .empty,
    pending: ?LineView = null,

    pub fn registerAnchor(self: *Parser, name: []const u8, value: Value) Fail!void {
        try self.anchors.put(self.alloc, try self.alloc.dupe(u8, name), value);
    }

    fn skipBlankLines(self: *Parser) void {
        while (self.pos < self.lines.len) {
            const raw = self.lines[self.pos].raw;
            if (isBlankRaw(raw) or isCommentRaw(raw)) {
                self.pos += 1;
            } else break;
        }
    }

    fn peekView(self: *Parser) Fail!LineView {
        const line = self.lines[self.pos];
        const ind = try lineIndent(line);
        return .{
            .no = line.no,
            .ind = ind,
            .content = line.raw[ind..],
            .col = line.col0 + ind + 1,
            .physical = true,
        };
    }

    pub fn parseRoot(self: *Parser) Fail!Value {
        self.skipBlankLines();
        if (self.pos >= self.lines.len) return null_value;
        const v = try self.parseBlockNode(0, null, 0);
        self.skipBlankLines();
        if (self.pos < self.lines.len) {
            const line = self.lines[self.pos];
            return failAt(line.no, 1, "unexpected content after the document's root node");
        }
        return v;
    }

    /// Parse a block node whose first significant line is at indent
    /// >= min_indent. `parent_indent` is the indent of the structure
    /// that owns this node (drives block scalars and plain-scalar
    /// continuation). May consume the parser's pending first-line
    /// view (sequence compact notation).
    fn parseBlockNode(self: *Parser, min_indent: usize, anchor: ?[]const u8, parent_indent: usize) Fail!Value {
        var first: LineView = undefined;
        if (self.pending) |p| {
            first = p;
            self.pending = null;
        } else {
            self.skipBlankLines();
            if (self.pos >= self.lines.len) return null_value;
            first = try self.peekView();
            if (first.ind < min_indent) return null_value;
        }
        const content = stripComment(first.content);
        const pfx = try stripPrefixes(content, first.no, first.col, anchor);
        if (pfx.rest.len == 0) {
            // Anchor-only line: the node is on the following lines.
            if (first.physical) self.pos += 1;
            self.skipBlankLines();
            if (self.pos >= self.lines.len) {
                if (pfx.anchor) |a| try self.registerAnchor(a, null_value);
                return null_value;
            }
            const nv = try self.peekView();
            if (nv.ind < first.ind) {
                if (pfx.anchor) |a| try self.registerAnchor(a, null_value);
                return null_value;
            }
            return self.parseBlockNode(first.ind, pfx.anchor, parent_indent);
        }
        if (isSeqStart(pfx.rest)) {
            const fv = LineView{ .no = first.no, .ind = first.ind, .content = pfx.rest, .col = pfx.col, .physical = first.physical };
            return self.parseBlockSequence(first.ind, pfx.anchor, fv);
        }
        if ((try scanBlockKey(self.alloc, pfx.rest, first.no)) != null) {
            const fv = LineView{ .no = first.no, .ind = first.ind, .content = pfx.rest, .col = pfx.col, .physical = first.physical };
            return self.parseBlockMapping(first.ind, pfx.anchor, fv);
        }
        if (first.physical) self.pos += 1;
        return self.parseInlineNode(pfx.rest, first.no, pfx.col, parent_indent, pfx.anchor);
    }

    /// The value for a key (or a "- " entry) when nothing follows on
    /// the same line: a deeper block node, optionally a sequence at
    /// the key's own indent (mapping values only), or null.
    fn parseNestedValue(self: *Parser, key_indent: usize, anchor: ?[]const u8, allow_same_indent_seq: bool) Fail!Value {
        self.skipBlankLines();
        if (self.pos >= self.lines.len) {
            if (anchor) |a| try self.registerAnchor(a, null_value);
            return null_value;
        }
        const nv = try self.peekView();
        if (nv.ind > key_indent) {
            return self.parseBlockNode(key_indent + 1, anchor, key_indent);
        }
        if (allow_same_indent_seq and nv.ind == key_indent) {
            const content = stripComment(nv.content);
            const pfx = try stripPrefixes(content, nv.no, nv.col, anchor);
            if (isSeqStart(pfx.rest)) {
                const fv = LineView{ .no = nv.no, .ind = nv.ind, .content = pfx.rest, .col = pfx.col, .physical = true };
                return self.parseBlockSequence(key_indent, pfx.anchor, fv);
            }
        }
        if (anchor) |a| try self.registerAnchor(a, null_value);
        return null_value;
    }

    fn parseValueAfterKey(self: *Parser, rest_raw: []const u8, line_no: usize, rest_col: usize, key_indent: usize) Fail!Value {
        const pfx = try stripPrefixes(rest_raw, line_no, rest_col, null);
        if (pfx.rest.len == 0) {
            return self.parseNestedValue(key_indent, pfx.anchor, true);
        }
        return self.parseInlineNode(pfx.rest, line_no, pfx.col, key_indent, pfx.anchor);
    }

    fn parseBlockMapping(self: *Parser, indent: usize, anchor: ?[]const u8, first: LineView) Fail!Value {
        var builder = MapBuilder{ .parts = std.array_list.Managed(MapPart).init(self.alloc) };
        var first_pending: ?LineView = first;
        while (true) {
            const v: LineView = if (first_pending) |f| blk: {
                first_pending = null;
                break :blk f;
            } else blk: {
                self.skipBlankLines();
                if (self.pos >= self.lines.len) break;
                const pv = try self.peekView();
                if (pv.ind != indent) break;
                break :blk pv;
            };
            const content = stripComment(v.content);
            if (content.len == 0) {
                if (v.physical) self.pos += 1;
                continue;
            }
            if (isSeqStart(content)) {
                if (!v.physical) return failAt(v.no, v.col, "unexpected sequence entry inside a mapping");
                break;
            }
            if (content.len >= 2 and content[0] == '?' and content[1] == ' ') {
                return failUnsupported(v.no, v.col, "explicit (complex) keys");
            }
            const hit = (try scanBlockKey(self.alloc, content, v.no)) orelse
                return failAt(v.no, v.col, "could not find expected ':'");
            if (v.physical) self.pos += 1;
            const rest = content[hit.colon + 1 ..];
            const value = try self.parseValueAfterKey(rest, v.no, v.col + hit.colon + 1, indent);
            if (std.mem.eql(u8, hit.key, "<<")) {
                try builder.addMergeChecked(value, v.no, v.col);
            } else {
                try builder.addEntry(hit.key, value, v.no, v.col);
            }
        }
        const result = try builder.finish(self.alloc);
        if (anchor) |a| try self.registerAnchor(a, result);
        return result;
    }

    fn parseBlockSequence(self: *Parser, indent: usize, anchor: ?[]const u8, first: LineView) Fail!Value {
        var items = std.array_list.Managed(Value).init(self.alloc);
        var first_pending: ?LineView = first;
        while (true) {
            const v: LineView = if (first_pending) |f| blk: {
                first_pending = null;
                break :blk f;
            } else blk: {
                self.skipBlankLines();
                if (self.pos >= self.lines.len) break;
                const pv = try self.peekView();
                if (pv.ind != indent) break;
                break :blk pv;
            };
            const content = stripComment(v.content);
            if (!isSeqStart(content)) {
                if (!v.physical) return failAt(v.no, v.col, "expected a sequence entry");
                break;
            }
            if (v.physical) self.pos += 1;
            var idx: usize = 1;
            while (idx < content.len and content[idx] == ' ') idx += 1;
            const rest = content[idx..];
            if (rest.len == 0) {
                const item = try self.parseNestedValue(indent, null, false);
                try items.append(item);
            } else {
                self.pending = .{
                    .no = v.no,
                    .ind = indent + idx,
                    .content = rest,
                    .col = v.col + idx,
                    .physical = false,
                };
                const item = try self.parseBlockNode(indent + idx, null, indent);
                try items.append(item);
            }
        }
        const result = Value{ .kind = KIND_ARRAY, .array = try items.toOwnedSlice() };
        if (anchor) |a| try self.registerAnchor(a, result);
        return result;
    }

    /// Parse a value that starts on the current line: a block scalar
    /// header, a flow collection, a quoted scalar, an alias, or a
    /// plain scalar (which may continue on deeper-indented lines).
    /// `text` is the value's first-line text, prefixes already stripped.
    fn parseInlineNode(self: *Parser, text: []const u8, line_no: usize, col: usize, parent_indent: usize, anchor: ?[]const u8) Fail!Value {
        const c0 = text[0];
        var value: Value = undefined;
        if (c0 == '|' or c0 == '>') {
            value = try self.parseBlockScalar(text, line_no, col, parent_indent);
        } else if (c0 == '[' or c0 == '{') {
            const buf = try self.gatherFlowText(text, line_no);
            var fp = FlowParser{ .p = self, .cur = .{ .buf = buf, .line = line_no, .col = col } };
            value = try fp.parseNode();
            fp.skipWs();
            if (fp.cur.i != buf.len) {
                return failAt(fp.cur.line, fp.cur.col, "unexpected content after flow collection");
            }
        } else if (c0 == '\'' or c0 == '"') {
            value = stringValue(try self.parseQuotedGathered(text, line_no, col, c0));
        } else if (c0 == '*') {
            const name = trimWs(text[1..]);
            if (!validAnchorName(name)) return failAt(line_no, col, "invalid alias name");
            const src = self.anchors.get(name) orelse return failUnknownAlias(name, line_no, col + 1);
            value = try deepClone(self.alloc, src);
        } else {
            value = try self.parsePlainBlockScalar(text, line_no, col, parent_indent);
        }
        if (anchor) |a| try self.registerAnchor(a, value);
        return value;
    }

    fn parseQuotedGathered(self: *Parser, first_text: []const u8, line_no: usize, col: usize, quote: u8) Fail![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.alloc);
        try buf.appendSlice(first_text);
        while (true) {
            var cur = TextCursor{ .buf = buf.items, .line = line_no, .col = col };
            const parsed = if (quote == '\'') parseSingleQuoted(self.alloc, &cur) else parseDoubleQuoted(self.alloc, &cur);
            if (parsed) |text| {
                var rest = buf.items[cur.i..];
                if (std.mem.indexOfScalar(u8, rest, '\n')) |nl| rest = rest[0..nl];
                if (trimWs(stripComment(rest)).len != 0) {
                    return failAt(cur.line, cur.col, "unexpected content after quoted scalar");
                }
                return text;
            } else |err| switch (err) {
                error.Unterminated => {
                    if (self.pos >= self.lines.len) {
                        return failAt(line_no, col, "unterminated quoted scalar");
                    }
                    try buf.append('\n');
                    try buf.appendSlice(self.lines[self.pos].raw);
                    self.pos += 1;
                },
                error.OutOfMemory => return error.OutOfMemory,
                error.ParseFail => return error.ParseFail,
            }
        }
    }

    fn parsePlainBlockScalar(self: *Parser, first_text: []const u8, line_no: usize, col: usize, parent_indent: usize) Fail!Value {
        if (first_text.len > 1 and first_text[0] == '-' and first_text[1] == ' ') {
            return failAt(line_no, col, "block sequence entries are not allowed in this context");
        }
        if (first_text.len > 1 and first_text[0] == '?' and first_text[1] == ' ') {
            return failUnsupported(line_no, col, "explicit (complex) keys");
        }
        if (std.mem.indexOf(u8, first_text, ": ") != null) {
            return failAt(line_no, col, "mapping values are not allowed here");
        }
        const Part = struct { text: []const u8, gap: usize };
        var parts = std.array_list.Managed(Part).init(self.alloc);
        try parts.append(.{ .text = rtrimWs(first_text), .gap = 0 });
        var scan = self.pos;
        var consumed = self.pos;
        var pending_blanks: usize = 0;
        while (scan < self.lines.len) {
            const line = self.lines[scan];
            if (isBlankRaw(line.raw) or isCommentRaw(line.raw)) {
                pending_blanks += 1;
                scan += 1;
                continue;
            }
            const ind = try lineIndent(line);
            if (ind <= parent_indent) break;
            const content = stripComment(line.raw[ind..]);
            if (content.len == 0) {
                pending_blanks += 1;
                scan += 1;
                continue;
            }
            if (isSeqStart(content)) {
                return failAt(line.no, line.col0 + ind + 1, "block sequence entries are not allowed in this context");
            }
            if ((try scanBlockKey(self.alloc, content, line.no)) != null) {
                return failAt(line.no, line.col0 + ind + 1, "mapping values are not allowed here");
            }
            try parts.append(.{ .text = content, .gap = pending_blanks + 1 });
            pending_blanks = 0;
            scan += 1;
            consumed = scan;
        }
        self.pos = consumed;
        var out = std.array_list.Managed(u8).init(self.alloc);
        for (parts.items, 0..) |part, idx| {
            if (idx > 0) try appendFoldedBreak(&out, part.gap);
            try out.appendSlice(part.text);
        }
        const text = try out.toOwnedSlice();
        return resolvePlainScalar(self.alloc, text);
    }

    fn parseBlockScalar(self: *Parser, header: []const u8, line_no: usize, col: usize, parent_indent: usize) Fail!Value {
        const folded = header[0] == '>';
        var chomp: enum { clip, strip, keep } = .clip;
        var indicator: ?usize = null;
        var seen_chomp = false;
        var seen_ind = false;
        var i: usize = 1;
        while (i < header.len) : (i += 1) {
            const c = header[i];
            if (c == '+' or c == '-') {
                if (seen_chomp) return failAt(line_no, col + i, "duplicate chomping indicator in block scalar header");
                seen_chomp = true;
                chomp = if (c == '+') .keep else .strip;
            } else if (c >= '1' and c <= '9') {
                if (seen_ind) return failAt(line_no, col + i, "duplicate indent indicator in block scalar header");
                seen_ind = true;
                indicator = c - '0';
            } else break;
        }
        if (trimWs(header[i..]).len != 0) {
            return failAt(line_no, col + i, "invalid block scalar header");
        }

        var content_indent: usize = undefined;
        if (indicator) |d| {
            content_indent = parent_indent + d;
        } else {
            var detected: ?usize = null;
            var j = self.pos;
            while (j < self.lines.len) : (j += 1) {
                const line = self.lines[j];
                if (isBlankRaw(line.raw)) continue;
                detected = countLeadingSpaces(line.raw);
                break;
            }
            if (detected == null or detected.? <= parent_indent) {
                return stringValue("");
            }
            content_indent = detected.?;
        }

        var collected = std.array_list.Managed([]const u8).init(self.alloc);
        var j = self.pos;
        while (j < self.lines.len) : (j += 1) {
            const line = self.lines[j];
            if (isBlankRaw(line.raw)) {
                try collected.append("");
                continue;
            }
            const sp = countLeadingSpaces(line.raw);
            if (sp < content_indent) break;
            try collected.append(line.raw[content_indent..]);
        }
        self.pos = j;

        var trailing: usize = 0;
        while (collected.items.len > 0 and collected.items[collected.items.len - 1].len == 0) {
            trailing += 1;
            _ = collected.pop();
        }
        const body = collected.items;

        var out = std.array_list.Managed(u8).init(self.alloc);
        if (!folded) {
            for (body, 0..) |l, idx| {
                if (idx > 0) try out.append('\n');
                try out.appendSlice(l);
            }
        } else {
            // Folded style: a run of k breaks between two content
            // lines becomes one space (k == 1, unless either line is
            // more-indented) or k-1 breaks (k >= 2). Leading blank
            // lines are breaks verbatim.
            var idx: usize = 0;
            while (idx < body.len and body[idx].len == 0) : (idx += 1) {
                try out.append('\n');
            }
            var have_prev = false;
            var prev_line: []const u8 = "";
            var gap: usize = 0;
            while (idx < body.len) {
                const l = body[idx];
                if (have_prev) {
                    if (gap == 1) {
                        if (prev_line[0] == ' ' or l[0] == ' ') {
                            try out.append('\n');
                        } else {
                            try out.append(' ');
                        }
                    } else {
                        for (0..gap - 1) |_| try out.append('\n');
                    }
                }
                try out.appendSlice(l);
                prev_line = l;
                have_prev = true;
                var blanks: usize = 0;
                var nxt = idx + 1;
                while (nxt < body.len and body[nxt].len == 0) {
                    blanks += 1;
                    nxt += 1;
                }
                gap = blanks + 1;
                idx = nxt;
            }
        }
        if (body.len > 0) {
            for (0..trailing + 1) |_| try out.append('\n');
        } else {
            for (0..trailing) |_| try out.append('\n');
        }
        var text = try out.toOwnedSlice();
        switch (chomp) {
            .strip => {
                var end = text.len;
                while (end > 0 and text[end - 1] == '\n') end -= 1;
                text = text[0..end];
            },
            .clip => {
                var end = text.len;
                while (end > 0 and text[end - 1] == '\n') end -= 1;
                if (end == 0) {
                    text = "";
                } else {
                    const nt = try self.alloc.alloc(u8, end + 1);
                    @memcpy(nt[0..end], text[0..end]);
                    nt[end] = '\n';
                    text = nt;
                }
            },
            .keep => {},
        }
        return stringValue(text);
    }

    /// Gather a flow collection's full text: the first line's text
    /// plus raw following lines until the brackets balance.
    fn gatherFlowText(self: *Parser, first_text: []const u8, line_no: usize) Fail![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.alloc);
        try buf.appendSlice(first_text);
        while (!flowBalanced(buf.items)) {
            if (self.pos >= self.lines.len) {
                return failAt(line_no, 1, "unterminated flow collection");
            }
            try buf.append('\n');
            try buf.appendSlice(self.lines[self.pos].raw);
            self.pos += 1;
        }
        return buf.toOwnedSlice();
    }
};

pub fn flowBalanced(buf: []const u8) bool {
    var depth: i32 = 0;
    var quote: u8 = 0;
    var comment = false;
    var i: usize = 0;
    while (i < buf.len) {
        const c = buf[i];
        if (comment) {
            if (c == '\n') comment = false;
            i += 1;
            continue;
        }
        if (quote == '\'') {
            if (c == '\'') {
                if (i + 1 < buf.len and buf[i + 1] == '\'') {
                    i += 2;
                    continue;
                }
                quote = 0;
            }
            i += 1;
            continue;
        }
        if (quote == '"') {
            if (c == '\\') {
                i += 2;
                continue;
            }
            if (c == '"') quote = 0;
            i += 1;
            continue;
        }
        if (c == '#' and (i == 0 or buf[i - 1] == ' ' or buf[i - 1] == '\t' or buf[i - 1] == '\n')) {
            comment = true;
            i += 1;
            continue;
        }
        if (c == '\'' or c == '"') {
            quote = c;
            i += 1;
            continue;
        }
        if (c == '[' or c == '{') depth += 1;
        if (c == ']' or c == '}') depth -= 1;
        i += 1;
    }
    return depth <= 0;
}

// ---------------- flow parser ----------------
pub fn foldFlowPlain(alloc: std.mem.Allocator, raw: []const u8) Fail![]const u8 {
    var out = std.array_list.Managed(u8).init(alloc);
    var it = std.mem.splitScalar(u8, raw, '\n');
    var started = false;
    var pending_newlines: usize = 0;
    while (it.next()) |seg0| {
        const seg = trimWs(seg0);
        if (!started) {
            if (seg.len == 0) continue;
            try out.appendSlice(seg);
            started = true;
            continue;
        }
        if (seg.len == 0) {
            pending_newlines += 1;
            continue;
        }
        try appendFoldedBreak(&out, pending_newlines + 1);
        try out.appendSlice(seg);
        pending_newlines = 0;
    }
    return out.toOwnedSlice();
}
