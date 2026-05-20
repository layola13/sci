import re

with open('src/runtime/sa_std.zig', 'r') as f:
    text = f.read()

fallible_def = """
pub fn Fallible(comptime T: type) type {
    return extern struct {
        status: i32,
        value: T,
    };
}

pub fn ok(comptime T: type, value: T) Fallible(T) {
    return .{ .status = SA_STD_OK, .value = value };
}

pub fn fail(comptime T: type, status: i32) Fallible(T) {
    return .{ .status = status, .value = @as(T, @bitCast(@as(std.meta.Int(.unsigned, @bitSizeOf(T)), 0))) };
}

"""

# Insert it before sa_std_version
text = text.replace('pub export fn sa_std_version() u32 {\n', fallible_def + 'pub export fn sa_std_version() u32 {\n')

# We also lost sa_json_parse returning Fallible(u64)!
text = re.sub(
    r'pub export fn sa_json_parse\(json_bytes: \?\[\*\]const u8, len: u64\) i32 \{\n    var handle: u64 = 0;\n    const input = constBytes\(json_bytes, len\) catch \|err\| return finishErr\(err\);\n    const document = jsonDocumentFromSlice\(std\.heap\.page_allocator, input\) catch \|err\| return finishErr\(err\);\n    handle = registerJsonNode\(document, document\.parsed\.value, false\) catch \|err\| return finishErr\(err\);\n    return @as\(i32, @intCast\(handle\)\);\n\}',
    r'pub export fn sa_json_parse(json_bytes: ?[*]const u8, len: u64) Fallible(u64) {\n    const input = constBytes(json_bytes, len) catch |err| return fail(u64, mapError(err));\n    const document = jsonDocumentFromSlice(std.heap.page_allocator, input) catch |err| return fail(u64, mapError(err));\n    const handle = registerJsonNode(document, document.parsed.value, false) catch |err| return fail(u64, mapError(err));\n    return ok(u64, handle);\n}',
    text
)

# And any other Fallible things that were there?
# Let's see if this fixes the compiler errors.

with open('src/runtime/sa_std.zig', 'w') as f:
    f.write(text)
