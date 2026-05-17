// SAX 模块主入口
// 整合 Parser、Lowerer、Airlock、Referee 规则

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const parser = @import("parser.zig");
pub const lowerer = @import("lowerer.zig");
pub const airlock_gen = @import("airlock_gen.zig");
pub const sax_rules = @import("sax_rules.zig");

pub const SaxCompiler = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) SaxCompiler {
        return .{ .allocator = allocator };
    }

    /// 完整编译流程：.sax → .saasm → Referee → WASM
    pub fn compile(
        self: *SaxCompiler,
        sax_source: []const u8,
        component_name: []const u8,
    ) !struct {
        saasm_code: std.ArrayList(u8),
        airlock_js: std.ArrayList(u8),
        index_html: std.ArrayList(u8),
    } {
        // Step 1: SAX Parser: .sax → .saasm
        var sax_parser = parser.SaxParser.init(self.allocator, sax_source);
        const saasm_code = try sax_parser.parse();
        errdefer saasm_code.deinit();

        // Step 2: Airlock 生成器
        var airlock_generator = airlock_gen.AirlockGenerator.init(self.allocator);
        const airlock_js = try airlock_generator.generateAirlockJS();
        errdefer airlock_js.deinit();

        const index_html = try airlock_generator.generateIndexHTML(component_name);
        errdefer index_html.deinit();

        return .{
            .saasm_code = saasm_code,
            .airlock_js = airlock_js,
            .index_html = index_html,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var compiler = SaxCompiler.init(allocator);
    _ = compiler;
}
