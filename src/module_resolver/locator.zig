//! 模块定位器 —— SA 标准库模块化 Phase 2（Import Resolver）。
//!
//! 职责：把一条 import 说明符解析成磁盘上的模块文件（ModuleInfo），
//! 是提案 §4 的 `sa-module-resolver` 的定位部分。只做存在性判断，
//! 不读文件内容、不解析、不做语义分析。
//!
//! 与现有机制的关系（本定位器不替换以下任何一处）：
//!   - flattener 的 seen_paths 去重与 ImportCycle 循环检测
//!     （src/flattener/expandimportsinto.zig，约 110 行处）继续负责
//!     @import 文本包含的去重与成环报错；本定位器不跟踪加载状态。
//!   - src/pkg/resolver.zig 的 `sa_std/` 前缀解析继续负责包名前缀到
//!     仓库内 sa_std/ 树的映射；本定位器假定 std_root 已由调用方按
//!     该映射给好，只在树内做域校验与扩展名试探。
//!   - Phase 3 懒加载器消费本模块时再接线：定位（本文件）→ 按需读取
//!     → 解析 → 状态机推进（ModuleState.unloaded → analyzed）。
//!
//! 定位流程（Locator.locate）：归一化 → 包名/域校验（未知域报
//! ModuleNotFound）→ 扩展名试探 → 命中则返回；未命中则试顶层旧路径
//! shim（sa_std/<leaf>.sa 等）；两路皆无报 ModuleNotFound。
//!
//! 定位器只认识本地单一版本的 sa_std 树：包名非 `sa_std` 的说明符一律
//! ModuleNotFound（无注册表可查）；ImportSpec.version 只记录、不校验
//! （sa.mod 第 5 行注释：版本/依赖字段当前 manifest 语法不支持）。
//!
//! 文件系统调用走本仓的 sio 兼容层（src/sa_io.zig），不用裸 std.fs：
//! Zig 0.17 的 std.fs 已无 Dir/cwd（只剩 path 等），旧式调用形状由 sio
//! 在 std.Io 之上复原（`sio.cwd()`、`sio.Dir.statFile(path)` 等）；
//! `std.fs.path.*` 与 `std.fs.max_path_bytes` 在 0.17 仍有效，保持原样。

const std = @import("std");
const sio = @import("sio");
const types = @import("types.zig");

pub const ImportKind = types.ImportKind;
pub const ImportSpec = types.ImportSpec;
pub const ModuleId = types.ModuleId;
pub const ModuleInfo = types.ModuleInfo;
pub const ModuleState = types.ModuleState;
pub const ResolveError = types.ResolveError;
pub const SymbolEdge = types.SymbolEdge;

/// sa_std 的域（功能领域）描述。
pub const Domain = struct {
    /// 域名，如 `io`。也是逻辑模块路径 `sa_std.<name>...` 的第二段。
    name: []const u8,
    /// 域目录相对 sa_std/ 的路径。当前所有域均为顶层单目录，与 name 相同；
    /// 保留该字段是为以后域目录改名/嵌套时表与路径解耦。
    dir: []const u8,
    /// 该域是否有 prelude.sa（模块级导入的聚合入口）。
    has_prelude: bool,
};

/// 19 个域 → 实为 23 个：任务原文写“19 个域目录”，但其枚举的域名共 23 个，
/// 与 `ls -d sa_std/*/` 的实际目录逐一对照后也是 23 个（见 /tmp 下的核对脚本
/// 输出）。以磁盘实际为准，表里 23 条；“19”之说记为任务文本笔误，待裁决。
pub const domains: [23]Domain = .{
    .{ .name = "alloc", .dir = "alloc", .has_prelude = true },
    .{ .name = "collections", .dir = "collections", .has_prelude = true },
    .{ .name = "core", .dir = "core", .has_prelude = true },
    .{ .name = "crypto", .dir = "crypto", .has_prelude = true },
    .{ .name = "db", .dir = "db", .has_prelude = true },
    .{ .name = "encoding", .dir = "encoding", .has_prelude = true },
    .{ .name = "ffi", .dir = "ffi", .has_prelude = true },
    .{ .name = "fmt", .dir = "fmt", .has_prelude = true },
    .{ .name = "http", .dir = "http", .has_prelude = true },
    .{ .name = "io", .dir = "io", .has_prelude = true },
    .{ .name = "marker", .dir = "marker", .has_prelude = true },
    .{ .name = "mem", .dir = "mem", .has_prelude = true },
    .{ .name = "net", .dir = "net", .has_prelude = true },
    .{ .name = "num", .dir = "num", .has_prelude = true },
    .{ .name = "os", .dir = "os", .has_prelude = true },
    // string/ 是唯一无 prelude.sa 的域：现状缺口，Phase 2 不新建 prelude 文件；
    // 模块级导入 sa_std.string 在此阶段报 ModuleNotFound（见 findPrelude）。
    .{ .name = "string", .dir = "string", .has_prelude = false },
    .{ .name = "sync", .dir = "sync", .has_prelude = true },
    .{ .name = "task", .dir = "task", .has_prelude = true },
    .{ .name = "testing", .dir = "testing", .has_prelude = true },
    .{ .name = "text", .dir = "text", .has_prelude = true },
    .{ .name = "thread", .dir = "thread", .has_prelude = true },
    .{ .name = "time", .dir = "time", .has_prelude = true },
    .{ .name = "tree_sitter", .dir = "tree_sitter", .has_prelude = true },
};

/// 已知的 SA 源文件扩展名；同时也是 probeExtensions 的试探顺序。
/// 顺序即优先级：.sa 规范实现优先，.sal 声明次之，.sla/.sai 再次之。
/// 命中即唯一结果，不产生歧义（AmbiguousImport 在 Phase 2 不触发）。
pub const probe_order: [4][]const u8 = .{ ".sa", ".sal", ".sla", ".sai" };

/// 按域名查表，未知域返回 null。
pub fn findDomain(name: []const u8) ?*const Domain {
    for (&domains) |*d| {
        if (std.mem.eql(u8, d.name, name)) return d;
    }
    return null;
}

/// 去掉路径末尾已知的源文件扩展名（.sa/.sal/.sla/.sai）；无已知扩展名时原样返回。
fn stripKnownExtension(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return path;
    for (probe_order) |known| {
        if (std.mem.eql(u8, ext, known)) return path[0 .. path.len - ext.len];
    }
    return path;
}

/// 路径末尾的已知源文件扩展名；无则返回 null。
pub fn knownExtension(path: []const u8) ?[]const u8 {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return null;
    for (probe_order) |known| {
        if (std.mem.eql(u8, ext, known)) return known;
    }
    return null;
}

/// 归一化一条 import 说明符，返回调用方所有的新字符串。
///
/// 规则：
///   - 点分转斜杠：`sa_std.io.print` → `sa_std/io/print`；
///     斜杠写法原样保留；两种写法可混用（`sa_std.io/print` 也合法）。
///   - 点号一律视为分隔符，只有一个例外：末尾已知的源文件扩展名
///     （.sa/.sal/.sla/.sai）不碰，如 `sa_std/io/print.sa` 的 `.sa` 不会
///     变成 `/sa`。未知后缀（如 `.txt`）不视为扩展名，按分隔符处理。
///   - 去重斜杠、去掉 `.` 段（如 `sa_std/./io/print` → `sa_std/io/print`）。
///   - `..` 段是路径逃逸，报 InvalidImportSpec（不静默丢弃、不解析；
///     相对导入的基准目录解析是 Phase 3 的事，见 Locator.locate）。
///   - 空说明符、归一化后为空（如 `.`、`/`）报 InvalidImportSpec。
/// 不做：不校验域是否存在（那是 locate 的事）、不触磁盘。
pub fn normalizeSpecifier(allocator: std.mem.Allocator, spec: []const u8) ResolveError![]u8 {
    if (spec.len == 0) return error.InvalidImportSpec;

    // 先剥离末尾已知扩展名，归一化完再接回去。
    var stem = spec;
    var ext: ?[]const u8 = null;
    for (probe_order) |known| {
        if (std.mem.endsWith(u8, spec, known)) {
            stem = spec[0 .. spec.len - known.len];
            ext = known;
            break;
        }
    }
    if (stem.len == 0) return error.InvalidImportSpec;

    // `..` 段预检：必须在点号转斜杠之前做，否则 `..` 会变成空段被丢弃，
    // 悄悄改变路径含义（如 `sa_std/io/../../etc` 会被误读成 `sa_std/io/etc`）。
    var seg_it = std.mem.splitScalar(u8, stem, '/');
    while (seg_it.next()) |seg| {
        if (std.mem.eql(u8, seg, "..")) return error.InvalidImportSpec;
    }

    // 点号转斜杠：剩余点号全是分隔符。
    const slashy = try allocator.dupe(u8, stem);
    defer allocator.free(slashy);
    for (slashy) |*c| {
        if (c.* == '.') c.* = '/';
    }

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    var it = std.mem.splitScalar(u8, slashy, '/');
    var first = true;
    while (it.next()) |seg| {
        if (seg.len == 0) continue; // 去重斜杠
        if (std.mem.eql(u8, seg, ".")) continue; // 去 `.` 段
        if (!first) try out.append('/');
        try out.appendSlice(seg);
        first = false;
    }
    if (out.items.len == 0) {
        out.deinit();
        return error.InvalidImportSpec;
    }
    if (ext) |e| try out.appendSlice(e);
    return out.toOwnedSlice();
}

/// `dir` 内 `path` 是否为一个真实文件（非目录、非缺失）。
fn fileExists(dir: sio.Dir, path: []const u8) bool {
    const stat = dir.statFile(path) catch return false;
    return stat.kind == .file;
}

/// 给定无扩展名路径，按 `.sa` → `.sal` → `.sla` → `.sai` 顺序试探磁盘
/// 存在性。只做存在性判断，不读内容。命中返回该扩展名（静态字符串），
/// 四路皆无返回 null。
pub fn probeExtensions(dir: sio.Dir, stem: []const u8) ?[]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    for (probe_order) |ext| {
        const candidate = std.fmt.bufPrint(&buf, "{s}{s}", .{ stem, ext }) catch continue;
        if (fileExists(dir, candidate)) return ext;
    }
    return null;
}

/// 域 → 该域 prelude.sa 的相对路径（如 `io/prelude.sa`），调用方所有。
///
/// 无 prelude 的域（当前只有 string/）返回 null；未知域名也返回 null
/// （调用方 locatePrelude 统一转成 ModuleNotFound）。
/// 本函数不触磁盘：存在性由 locatePrelude 在返回 ModuleInfo 前复核；
/// 表与磁盘的一致性由核对脚本保证（见 domains 表头注释）。
pub fn findPrelude(allocator: std.mem.Allocator, domain_name: []const u8) ResolveError!?[]u8 {
    const domain = findDomain(domain_name) orelse return null;
    // string/ 走此分支：现状缺口，Phase 2 不新建 prelude 文件。
    if (!domain.has_prelude) return null;
    return std.fmt.allocPrint(allocator, "{s}/prelude.sa", .{domain.dir});
}

/// 模块定位器：std_root 是 sa_std/ 树的路径（相对或绝对均可，由调用方按
/// src/pkg/resolver.zig 的 `sa_std/` 前缀映射给好）；本定位器只在树内工作。
pub const Locator = struct {
    allocator: std.mem.Allocator,
    std_root: []const u8,

    pub fn init(allocator: std.mem.Allocator, std_root: []const u8) Locator {
        return .{ .allocator = allocator, .std_root = std_root };
    }

    /// 打开 std_root；树不存在时按 ModuleNotFound 处理（不是 InvalidImportSpec：
    /// 说明符本身没错，是本地树缺失）。
    fn openRoot(self: Locator) ResolveError!sio.Dir {
        return sio.cwd().openDir(self.std_root, .{}) catch return error.ModuleNotFound;
    }

    /// 组装一条 ModuleInfo。`rel_path` 为相对 std_root 的命中路径（含扩展名）。
    /// fs_path 与 id.path 为新分配字符串，调用方负责释放。
    fn makeInfo(self: Locator, spec: ImportSpec, rel_path: []const u8, is_shim: bool) ResolveError!ModuleInfo {
        const fs_path = try std.fs.path.join(self.allocator, &.{ self.std_root, rel_path });
        errdefer self.allocator.free(fs_path);
        const id_path = try std.mem.concat(self.allocator, u8, &.{ spec.package, "/", rel_path });
        // package 恒为字面量 "sa_std"，不借用 spec.package：locate() 在调
        // 用 makeInfo 前已校验 spec.package == "sa_std"；借用会让长寿的
        // ModuleId 依赖调用方 spec 字符串的寿命（合并对齐）。
        return .{
            .id = .{ .package = "sa_std", .path = id_path },
            .state = .unloaded,
            .fs_path = fs_path,
            .kind = spec.kind,
            .is_shim = is_shim,
        };
    }

    /// 顶层旧路径 shim 试探：std_root/<leaf><ext>，按 probe_order 试探。
    /// 命中返回 is_shim=true 的 ModuleInfo；无命中报 ModuleNotFound。
    fn locateTopLevelShim(self: Locator, spec: ImportSpec, leaf: []const u8) ResolveError!ModuleInfo {
        var root = try self.openRoot();
        defer root.close();
        const ext = probeExtensions(root, leaf) orelse return error.ModuleNotFound;
        const resolved = try std.mem.concat(self.allocator, u8, &.{ leaf, ext });
        defer self.allocator.free(resolved);
        return self.makeInfo(spec, resolved, true);
    }

    /// 定位一条 import 说明符。
    ///
    /// 流程：归一化 → 包名/域校验 → 扩展名试探 → 命中返回；未命中试顶层 shim；
    /// 两路皆无报 ModuleNotFound。
    ///
    /// 接受的写法（spec.path 应已是归一化形式；此处再归一化一次，幂等）：
    ///   - 包限定：`sa_std/io/print`、`sa_std/io/print.sa`、
    ///     `sa_std.io.print`（点分由 normalizeSpecifier 归一化）。
    ///   - 域裸写：`io/print`（包名隐含为 sa_std）。
    ///   - 域本身：`sa_std/io`（模块级导入 → 域 prelude，见 locatePrelude）。
    /// 不接受的写法：
    ///   - 相对路径，如 `cell/arc.sa`（真实语法 `@import "cell/arc.sa"` 存在，
    ///     但它是相对于导入方文件所在目录的相对路径；本定位器没有基准目录，
    ///     调用方须先解析成包限定形式——Phase 3 懒加载器补基准目录参数）。
    ///     此类说明符首段既非包名也非域名，在此报 ModuleNotFound。
    ///   - 包名非 `sa_std`：Phase 2 只有本地 sa_std 单一版本树，无注册表，
    ///     其他包一律 ModuleNotFound。
    ///   - `sa_std/<name>` 且 <name> 不是域名：如 `sa_std/vec`，先试顶层 shim
    ///    （sa_std/vec.sa 存在即返回 is_shim=true）；shim 也不存在才报
    ///     ModuleNotFound。注意：中间层旧路径 shim（如 collections/vec_deque.sa）
    ///     不在本定位器的 shim 路径内，是已知缺口，见文件末尾注释。
    pub fn locate(self: Locator, spec: ImportSpec) ResolveError!ModuleInfo {
        if (spec.package.len == 0) return error.InvalidImportSpec;
        if (spec.path.len == 0) return error.InvalidImportSpec;
        if (!std.mem.eql(u8, spec.package, "sa_std")) return error.ModuleNotFound;

        const normalized = try normalizeSpecifier(self.allocator, spec.path);
        defer self.allocator.free(normalized);

        const first_slash = std.mem.indexOfScalar(u8, normalized, '/') orelse {
            // 单段：既无包名也无域名，无法定位（见上“不接受的写法”）。
            return error.ModuleNotFound;
        };
        const first = normalized[0..first_slash];
        const rest = normalized[first_slash + 1 ..];

        // rel_path：去包名前缀后、相对 sa_std/ 的路径；domain_name：待校验的域。
        var rel_path: []const u8 = undefined;
        var domain_name: []const u8 = undefined;

        if (std.mem.eql(u8, first, spec.package)) {
            // 包限定：sa_std/<domain>/... 或 sa_std/<leaf>。
            if (rest.len == 0) return error.InvalidImportSpec;
            if (std.mem.indexOfScalar(u8, rest, '/')) |second_slash| {
                domain_name = rest[0..second_slash];
                rel_path = rest;
            } else {
                // sa_std/<leaf>：无域内路径。
                // 域名优先：`sa_std/io` 是模块级导入 → 域 prelude。
                const leaf_base = stripKnownExtension(rest);
                if (findDomain(leaf_base) != null) {
                    return self.locatePrelude(leaf_base);
                }
                // 否则走顶层旧路径 shim：`sa_std/vec[.sa]` → sa_std/vec.sa。
                return self.locateTopLevelShim(spec, leaf_base);
            }
        } else if (findDomain(first) != null) {
            // 域裸写：io/print，包名隐含为 sa_std。
            domain_name = first;
            rel_path = normalized;
        } else {
            // 首段既非包名也非域名：相对路径或未知包，见上。
            return error.ModuleNotFound;
        }

        // 域表校验：未知域报 ModuleNotFound（不先试 shim）。
        // 域段若带扩展名（如 `sa_std/io.sa/print` 的笔误写法）先剥离再校验。
        const domain = findDomain(stripKnownExtension(domain_name)) orelse return error.ModuleNotFound;
        _ = domain;

        var root = try self.openRoot();
        defer root.close();

        // 1) 规范路径试探。
        if (knownExtension(rel_path) != null) {
            // 已带扩展名：只探该确切文件，不再试其他扩展名。
            if (fileExists(root, rel_path)) {
                return self.makeInfo(spec, rel_path, false);
            }
        } else if (probeExtensions(root, rel_path)) |ext| {
            const resolved = try std.mem.concat(self.allocator, u8, &.{ rel_path, ext });
            defer self.allocator.free(resolved);
            return self.makeInfo(spec, resolved, false);
        }

        // 2) 旧路径 shim：顶层同名文件 sa_std/<leaf><ext>。
        // 例：`sa_std/collections/vec_deque` 的规范路径不存在时，若顶层
        // vec_deque.sa 仍存在，返回 is_shim=true 的 ModuleInfo。
        const leaf = std.fs.path.basename(stripKnownExtension(rel_path));
        if (probeExtensions(root, leaf)) |ext| {
            const resolved = try std.mem.concat(self.allocator, u8, &.{ leaf, ext });
            defer self.allocator.free(resolved);
            return self.makeInfo(spec, resolved, true);
        }

        return error.ModuleNotFound;
    }

    /// 模块级导入用：定位某域的 prelude.sa。
    ///
    /// findPrelude 返回 null（无 prelude 的域，如 string/；或未知域名）
    /// 或磁盘上文件不存在时，报 ModuleNotFound。
    /// 成功返回 kind=.module、is_shim=false、state=.unloaded 的 ModuleInfo。
    pub fn locatePrelude(self: Locator, domain_name: []const u8) ResolveError!ModuleInfo {
        const rel = try findPrelude(self.allocator, domain_name) orelse return error.ModuleNotFound;
        defer self.allocator.free(rel);
        var root = try self.openRoot();
        defer root.close();
        if (!fileExists(root, rel)) return error.ModuleNotFound;
        const fs_path = try std.fs.path.join(self.allocator, &.{ self.std_root, rel });
        errdefer self.allocator.free(fs_path);
        const id_path = try std.mem.concat(self.allocator, u8, &.{ "sa_std/", rel });
        errdefer self.allocator.free(id_path);
        return .{
            .id = .{ .package = "sa_std", .path = id_path },
            .state = .unloaded,
            .fs_path = fs_path,
            .kind = .module,
            .is_shim = false,
        };
    }
};

// 已知缺口（只记，不修；Phase 2 不动 sa_std/、不动已有文件）：
//   - 中间层旧路径 shim 不覆盖：Phase 1 在 collections/ 下补了 6 个中间路径
//     shim（如 collections/vec_deque.sa → collections/deque/vec_deque.sa），
//     本定位器的 shim 路只试顶层 sa_std/<leaf>，这类中间 shim 命中不了，
//     须由 Phase 3 在接线时决定是否扩展 shim 搜索层级。
//   - 相对导入无基准目录：`@import "cell/arc.sa"` 这类相对导入需调用方先按
//     导入方文件所在目录解析成包限定形式；Locator.locate 对其报 ModuleNotFound。
//   - string/ 无 prelude.sa：模块级导入 sa_std.string 报 ModuleNotFound，
//     Phase 2 不新建该文件。
//   - 版本只记录不校验：ImportSpec.version 原样保留，定位时忽略；多版本 /
//     注册表解析留待以后。
//   - .sai 无 @import、不支持 shim 转发（Phase 1 RESULT §6 第 7 条）：定位器
//     只把 .sai 当作可试探的扩展名之一，不验证其内容。
