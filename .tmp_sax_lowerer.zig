const std = @import("std");
const parser = @import("src/sax/parser.zig");
const lowerer = @import("src/sax/lowerer.zig");

pub fn main() !void {
    const source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\    last = 0
        \\  </state>
        \\
        \\  <div class="counter">
        \\    <h1>{count}</h1>
        \\    <p>Last updated: {last} ms ago</p>
        \\    <button onclick={^inc}>+1</button>
        \\    <button onclick={^dec}>-1</button>
        \\    <button onclick={^reset}>Reset</button>
        \\  </div>
        \\
        \\  @inc:
        \\  L_ENTRY:
        \\    count = load state+Counter_count as i64
        \\    count = add count, 1
        \\    store state+Counter_count, count as i64
        \\    last = call @sax_get_time()
        \\    store state+Counter_last, last as i64
        \\    call @render()
        \\    ret
        \\
        \\  @dec:
        \\  L_ENTRY:
        \\    count = load state+Counter_count as i64
        \\    count = sub count, 1
        \\    store state+Counter_count, count as i64
        \\    last = call @sax_get_time()
        \\    store state+Counter_last, last as i64
        \\    call @render()
        \\    ret
        \\
        \\  @reset:
        \\  L_ENTRY:
        \\    store state+Counter_count, 0 as i64
        \\    last = call @sax_get_time()
        \\    store state+Counter_last, last as i64
        \\    call @render()
        \\    ret
        \\
        \\  !count !last
        \\</Component>
    ;
    var p = parser.SaxParser.init(std.heap.page_allocator, source);
    var program = try p.parse();
    defer program.deinit();
    var l = try lowerer.SaxLowerer.init(std.heap.page_allocator, program.components[0]);
    defer l.deinit();
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    defer out.deinit();
    try l.lower(&out, .{});
    try std.io.getStdOut().writer().writeAll(out.items);
}
