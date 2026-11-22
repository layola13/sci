// spec.zig — import 规约解析 (Std 模块化 Phase 2, P2B).
//
// 职责:只做 import 规约字符串的解析、分类与归一化,不做文件定位、
// 不读包注册表、不做网络取包、不做版本仲裁。定位属于 locator(P2A),
// 依赖闭包属于 closure(P2C,本 Phase),版本仲裁属于后续 Phase。
//
// 本文件是 Phase 2 的一个新增文件,不修改任何已有文件。
// 它引用 P2A 的 types.zig(本文件所在副本里 types.zig 尚不存在是正常
// 的;`zig ast-check` 是 parse-only,不解析 import)。
//
// ── 与 types.zig 的约定(合并对齐后,P2A 的 types.zig 为准) ─────────────
//   pub const ImportKind = enum { symbol, module };
//     .symbol — 符号级导入:只加载该符号(通常是一个文件)及其依赖。
//     .module — 模块级导入:加载该模块(通常是一个目录/prelude)。
//     歧义(同一规约既可解为文件又可解为目录 prelude)不是第三种 kind:
//     classifyImport/classifyImportAt 遇歧义返回 error.AmbiguousImport,
//     不静默选边;消歧规则由 Phase 3 定。
//   pub const ImportSpec = struct {
//       raw: []const u8,       // 去引号、去 @version 后缀后的规约原文(owned)。
//       path: []const u8,      // 规范斜杠路径(owned,见 canonicalize)。
//       kind: ImportKind,      // parseImportSpec 已填好的分类。
//       package: []const u8,   // 包名(借用 path 首段;相对路径为空串)。
//       symbol: ?[]const u8,   // 符号级为符号名(借用 path 末段去扩展名),
//                              // 模块级为 null。
//       version: ?[]const u8,  // 版本请求原文(不含前导 '@',含操作符,
//                              // 如 "^1.0";无版本后缀时为 null;owned)。
//   };
//   所有权:raw/path/version 均为本文件用传入 allocator dupe 的 owned
//   切片;package/symbol 借用 path 的子串,不单独释放。调用方用
//   ImportSpec.deinit(allocator) 释放 raw/path/version 三者。
//   pub const ResolveError = error {
//       ModuleNotFound, InvalidImportSpec, ImportCycle,
//       AmbiguousImport, UnsupportedVersion, OutOfMemory,
//   }; // 本文件用到其中四种:InvalidImportSpec、UnsupportedVersion、
//      // AmbiguousImport(分类探针确认两侧并存时)、OutOfMemory。
//   pub const ModuleId = ...; // 本文件不用(定位器的事),只在此列出以
//                             // 表明已知有此类型。
//
// ── 事实先例(实测,2026-11-22) ───────────────────────────────────────
//   * 真实 import 语法是 `@import "路径"`(斜杠路径+扩展名),行分类见
//     src/flattener/line_classifier.zig 的 import_decl 与
//     src/flattener/line_classifier_parse.zig 的 parseImport:行首
//     (去空白后)以 `@import` 开头,后跟一对双引号,引号后只允许空白。
//     点分 `import sa_std.io.print` 语法不存在——点分只是提案
//     §7 的逻辑模块路径。本文件接受点分写法只是为了兼容提案里的
//     逻辑形式,并把它归一化成斜杠路径;写盘与真实语料一律用斜杠。
//   * sa_std/sa.mod 只有 `package "sa_std"` 一行;版本/依赖/feature/
//     ABI 字段当前 sa_std manifest 不用。manifest 语法本身
//     (src/pkg/manifest/parsemanifestwithfile.zig +
//     src/pkg/manifest/permissionsetbuilder.zig)支持
//     `package { name "..." version "..." abi N features [...] }`,
//     其中 version 是自由字符串(PackageDecl.version: ?[]const u8),
//     无范围操作符、无 `@` 后缀——这是树内唯一的版本语法先例。
//     因此本文件的版本操作符(>=、^、~ 等)是 Phase 2 新立的解析
//     约定,不是既有语法;只做解析与记录,不做仲裁。
//   * 依赖的版本字段同样无先例:RequireEntry 只有 url/ref/sha256,
//     ref 是 git ref 字符串,不是 semver。
//   * re-export 就是 1 行 @import 转发文件;@import 是文本包含 + 按
//     规范路径去重(src/flattener/expandimportsinto.zig seen_paths,
//     环报 ImportCycle);sa_std/ 前缀由 src/pkg/resolver.zig 解析;
//     .sa 与同 stem 的 .sai/.sal 必须同目录移动
//     (src/flattener/injectimportedfile.zig)。
//
// ── 责任边界 ─────────────────────────────────────────────────────────
//   spec 只做分类与归一化。相对路径 → 绝对路径的解析由 locator /
//   caller 结合 base dir(当前文件所在目录)做:spec 不存 is_relative
//   字段,相对性由调用方按 package 是否为空判定(package 为空即非包
//   限定,见 parseImportSpec);`..` 段 canonicalize 刻意保留,不拼接
//   base dir。
//   spec 不碰包根、不读 sa.mod、不查注册表、不联网。
//   歧义的权威判定在 locator(它知道包根);classifyImport 的文件系统
//   探针只是尽力而为(best-effort,相对当前工作目录),见下文。

const std = @import("std");
const sio = @import("sio");
const Types = @import("types.zig");

pub const ImportSpec = Types.ImportSpec;
pub const ImportKind = Types.ImportKind;
pub const ModuleId = Types.ModuleId;
pub const ResolveError = Types.ResolveError;

/// 已知的 SA 源文件扩展名。分类规则里“以扩展名结尾的路径”只认这四种
/// (提案与 Phase 1 涉及的全部源文件类型)。其他扩展名(如 .txt)不认作
/// 符号导入:它会落到探针/默认分支,最终由 locator 以“未知文件类型”
/// 拒绝——那是定位器的职责,不是分类器的。
pub const source_extensions = [_][]const u8{ ".sa", ".sal", ".sla", ".sai" };

/// 版本请求的操作符。无前缀与 `=` 都是 .exact。
/// 注意:这些操作符在树内没有任何既有先例(见文件头);它们是 Phase 2
/// 新立的解析约定,只做记录与校验,不做版本仲裁。
pub const VersionOp = enum {
    exact,
    gte,
    lte,
    gt,
    lt,
    caret,
    tilde,
};

/// 一条版本请求。raw 是调用方传入的原文(去首尾空白后,含前导 '@' 与
/// 操作符,owned);major/minor/patch 是解析出的数字段,缺失的段为 null
/// (如 "1.2" 的 patch 为 null,"1" 的 minor/patch 均为 null)。
/// 不含预发布/构建元数据字段:带 `-rc1` / `+build` 的写法现阶段报
/// UnsupportedVersion(见 parseVersionSpec)。
pub const VersionSpec = struct {
    raw: []const u8,
    op: VersionOp,
    major: u32,
    minor: ?u32 = null,
    patch: ?u32 = null,
};

// ---------------------------------------------------------------------
// 小工具(私有)
// ---------------------------------------------------------------------

fn trimSpec(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

/// 去掉首尾成对的一对双引号。无引号时原样返回;只有一边有引号时报
/// InvalidImportSpec(不成对的引号是残缺规约,不是合法规约)。
fn stripQuotes(s: []const u8) ResolveError![]const u8 {
    const starts = s.len > 0 and s[0] == '"';
    const ends = s.len > 0 and s[s.len - 1] == '"';
    if (starts and ends) {
        if (s.len < 2) return error.InvalidImportSpec;
        return s[1 .. s.len - 1];
    }
    if (starts or ends) return error.InvalidImportSpec;
    return s;
}

/// 规约路径只允许 ASCII 字母/数字与 `_` `-` `.` `/`。
/// 拒绝:空格、反斜杠(不静默把它当斜杠)、冒号、引号、`*?<>|#` 等、
/// 以及一切非 ASCII 字节(Phase 2 的规约是 ASCII-only)。
fn validatePathChars(path: []const u8) ResolveError!void {
    for (path) |c| {
        const ok = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '_' or c == '-' or c == '.' or c == '/';
        if (!ok) return error.InvalidImportSpec;
    }
}

fn hasKnownExtension(path: []const u8) bool {
    for (source_extensions) |ext| {
        if (std.mem.endsWith(u8, path, ext)) return true;
    }
    return false;
}

/// 已知扩展名后缀(含点),无则返回 ""。
fn knownExtensionSuffix(path: []const u8) []const u8 {
    for (source_extensions) |ext| {
        if (std.mem.endsWith(u8, path, ext)) return ext;
    }
    return "";
}

/// 点分形式 → 斜杠形式。只在 `text` 不含 '/' 时调用。
/// 先剥已知扩展名(`sa_std.io.print.sa` → stem `sa_std.io.print` + `.sa`),
/// 再把 stem 按 '.' 切段用 '/' 连接。裸文件名(`print.sa` → stem `print`,
/// 无点)与裸名(`foo`)原样返回。
/// 含空段的点分(`.foo`、`foo..bar`、`foo.`)报 InvalidImportSpec。
/// 歧义说明:不含 '/' 又含点的裸名一律按点分理解;同目录下一个字面
/// 文件名本身含点(如 `my.file.sa`)必须写成 `./my.file.sa`(含 '/'
/// 后不再走点分分支),否则会被当成点分路径。这是点分作为逻辑形式
/// 的固有代价,真实语料里无此写法(见文件尾的语料统计)。
fn normalizeDotted(allocator: std.mem.Allocator, text: []const u8) ResolveError![]const u8 {
    const ext = knownExtensionSuffix(text);
    const stem = text[0 .. text.len - ext.len];
    if (stem.len == 0) return error.InvalidImportSpec;
    if (std.mem.indexOfScalar(u8, stem, '.') == null) {
        return allocator.dupe(u8, text);
    }
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var it = std.mem.splitScalar(u8, stem, '.');
    var first = true;
    while (it.next()) |seg| {
        if (seg.len == 0) return error.InvalidImportSpec;
        if (!first) try out.append(allocator, '/');
        try out.appendSlice(allocator, seg);
        first = false;
    }
    try out.appendSlice(allocator, ext);
    return out.toOwnedSlice(allocator);
}

/// 相对性判定(按规约原文拼写,不看 canonicalize 后的结果,因为
/// canonicalize 会丢掉 `./` 前缀)。
/// 相对:以 `./`、`../` 开头,或裸名/裸路径(如 `cell/arc.sa`、`io`)。
/// 非相对:以 `/` 开头(绝对路径)、以 `sa_std/` 开头或恰为 `sa_std`、
/// 以 `sa_std.` 开头的点分形式。其他包名前缀一律按相对处理——
/// Phase 2 只认 `sa_std` 这一个包根,多包名是后续 Phase 的事。
fn isRelativeSpelling(text: []const u8) bool {
    if (std.mem.startsWith(u8, text, "./") or
        std.mem.startsWith(u8, text, "../") or
        std.mem.eql(u8, text, ".") or std.mem.eql(u8, text, ".."))
    {
        return true;
    }
    if (std.mem.startsWith(u8, text, "/")) return false;
    if (std.mem.startsWith(u8, text, "sa_std/") or
        std.mem.eql(u8, text, "sa_std") or
        std.mem.startsWith(u8, text, "sa_std."))
    {
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------
// 规约解析
// ---------------------------------------------------------------------

/// 解析一条 import 规约字符串(@import 引号里的原文)。
/// 步骤:
///   ① 去首尾空白与成对双引号(调用方传已去引号的串也可以);
///   ② 若含 '@',在第一个 '@' 处切出版本后缀,用 parseVersionSpec
///      校验(非法版本会把错误向上传),其余部分为路径;
///      '@' 在路径字符集之外,所以第一个 '@' 就是版本分隔符。
///      版本后缀写法是 Phase 2 新立约定,树内无先例(见文件头);
///   ③ 点分 `sa_std.io.print` → 斜杠归一化;斜杠路径原样;
///   ④ 相对路径(`./`、`../`、无前缀如 `cell/arc.sa`)以 package 置空串
///      标记为相对,path 字段存 canonicalize 后的相对路径(保留 `..` 段)。
///      相对 → 绝对的解析是 locator/caller 的责任:它结合当前文件
///      所在目录(base dir)拼接,本文件不拼 base dir、不读包根。
///   ⑤ 空串、引号不成对、非法字符、空段点分、解析后为空,报
///      InvalidImportSpec;不支持的版本写法报 UnsupportedVersion。
/// 返回的 spec.kind 由 classifyImport 填好;raw/path/version 均为
/// owned 切片,package/symbol 借用 path 的子串(见文件头所有权约定)。
/// 歧义时 classifyImport 返回 error.AmbiguousImport,本函数向上传。
pub fn parseImportSpec(allocator: std.mem.Allocator, raw: []const u8) ResolveError!ImportSpec {
    var text = trimSpec(raw);
    text = try stripQuotes(text);

    var version_text: ?[]const u8 = null;
    if (std.mem.indexOfScalar(u8, text, '@')) |at| {
        const vpart = text[at + 1 ..];
        if (vpart.len == 0) return error.InvalidImportSpec;
        // 只校验,不保留解析结果:版本原文另存一份进 spec.version。
        const parsed = try parseVersionSpec(allocator, vpart);
        allocator.free(parsed.raw);
        version_text = vpart;
        text = text[0..at];
    }

    if (text.len == 0) return error.InvalidImportSpec;
    try validatePathChars(text);
    const relative = isRelativeSpelling(text);

    const path = try canonicalize(allocator, text);
    errdefer allocator.free(path);
    const raw_owned = try allocator.dupe(u8, text);
    errdefer allocator.free(raw_owned);
    var version_owned: ?[]const u8 = null;
    errdefer {
        if (version_owned) |v| allocator.free(v);
    }
    if (version_text) |vt| {
        version_owned = try allocator.dupe(u8, vt);
    }

    // package:相对路径为空串;非相对取 path 首段(包名)。package 借用
    // path 的子串(见 types.zig 所有权规则),不单独分配、不单独释放。
    const package: []const u8 = if (relative) "" else packageOfPath(path);
    var spec = ImportSpec{
        .raw = raw_owned,
        .path = path,
        .kind = .module,
        .package = package,
        .symbol = null,
        .version = version_owned,
    };
    spec.kind = try classifyImport(spec);
    if (spec.kind == .symbol) {
        spec.symbol = symbolName(path);
    }
    return spec;
}

/// 取规范路径的首段作包名(非相对路径用)。`sa_std/io/print` → `sa_std`;
/// 单段 `sa_std` → `sa_std` 自身。调用方保证 path 非相对、非空。
fn packageOfPath(path: []const u8) []const u8 {
    const slash = std.mem.indexOfScalar(u8, path, '/') orelse return path;
    return path[0..slash];
}

/// 取规范路径的符号名:末段去已知扩展名。`sa_std/io/print.sa` → `print`;
/// `sa_std/io/print` → `print`。借用 path 的子串,不单独分配。
fn symbolName(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    for (source_extensions) |ext| {
        if (std.mem.endsWith(u8, base, ext)) return base[0 .. base.len - ext.len];
    }
    return base;
}

// ---------------------------------------------------------------------
// 分类
// ---------------------------------------------------------------------

/// 纯语法分类:不需要文件系统就能判定的部分。
/// 返回非 null 表示语法已决定;返回 null 表示语法未定,须由探针
/// (文件与目录并存检查)决定。
fn classifySyntactic(spec: ImportSpec) ?ImportKind {
    // 以扩展名结尾的路径 → 符号(一个文件)。
    if (hasKnownExtension(spec.path)) return .symbol;
    // 点分原文(无 '/'):段数 >= 3 时末段是符号名 → 符号;
    // 段数 <= 2 时是包名/域名 → 模块。段数按 canonicalize 后的
    // path 计(点分段数与斜杠段数一一对应)。
    if (std.mem.indexOfScalar(u8, spec.raw, '/') == null) {
        var count: usize = 0;
        var it = std.mem.splitScalar(u8, spec.path, '/');
        while (it.next()) |seg| {
            if (seg.len != 0) count += 1;
        }
        if (count >= 3) return .symbol;
        return .module;
    }
    return null;
}

/// 文件系统探针的四种结果(私有):文件侧与目录侧的并存情况。
/// 歧义不在此处裁决——调用方把 .both 转成 error.AmbiguousImport。
const ProbeOutcome = enum { file_only, dir_only, both, neither };

/// 在给定目录句柄下对一条无扩展名斜杠路径做文件系统探针。
///   文件侧:存在 `<path>.sa` / `.sal` / `.sla` / `.sai` 任一文件。
///   目录侧:存在 `<path>` 目录,且其中含 `prelude.sa` 或 `prelude.sal`
///     (按任务原文“同名目录 prelude”;`string/` 目录无任何 prelude,
///     是 dir 侧须有 prelude 这一口径的活例证——若只要求目录存在,
///     `sa_std/string` 会被判歧义,而按本口径它只有文件侧,判符号)。
///   两侧并存 → .both;仅文件 → .file_only;仅目录 → .dir_only;
///   两侧皆无 → .neither(探针无结论,调用方取语法默认 .module;
///   缺失由 locator 报,不是分类器的职责)。
/// 任何 stat/open 失败都按“该侧不存在”处理:探针是尽力而为的,
/// 绝不因文件系统错误把一次分类变成一次报错。
/// 文件系统调用走仓库 sio 封装(Zig 0.17 的 std.fs 已无 Dir/cwd)。
fn probeInDir(dir: sio.Dir, path: []const u8) ProbeOutcome {
    var has_file = false;
    for (source_extensions) |ext| {
        var buf: [4096]u8 = undefined;
        const candidate = std.fmt.bufPrint(&buf, "{s}{s}", .{ path, ext }) catch continue;
        const st = dir.statFile(candidate) catch continue;
        if (st.kind == .file) {
            has_file = true;
            break;
        }
    }

    var has_dir = false;
    if (dir.statFile(path)) |st| {
        if (st.kind == .directory) {
            var sub = dir.openDir(path, .{}) catch null;
            if (sub) |*s| {
                defer s.close();
                for ([_][]const u8{ "prelude.sa", "prelude.sal" }) |prelude| {
                    if (s.statFile(prelude)) |pst| {
                        if (pst.kind == .file) {
                            has_dir = true;
                            break;
                        }
                    } else |_| {}
                }
            }
        }
    } else |_| {}

    if (has_dir and has_file) return .both;
    if (has_file) return .file_only;
    if (has_dir) return .dir_only;
    return .neither;
}

/// 分类规则(实现与注释一致):
///   * 以扩展名(.sa/.sal/.sla/.sai)结尾的路径 → symbol。
///   * 以末段符号名结尾的点分路径(点分段数 >= 3,如 `sa_std.io.print`)
///     → symbol;点分段数 <= 2(如 `sa_std.io`) → module。
///   * 以域名或域路径结尾、无扩展名、无末段符号的斜杠路径
///     (如 `sa_std/io`) → 探针:文件与目录 prelude 并存 → 报
///     error.AmbiguousImport,仅文件 → symbol,仅目录 → module,
///     两侧皆无 → module(语法默认;缺失由 locator 报)。
///   * 歧义消歧:优先文件还是优先 prelude 由 Phase 3 定,Phase 2 只报
///     歧义不静默选边。歧义是错误(ImportKind 只有 .symbol/.module
///     两态,无 .ambiguous 变体),不是第三种 kind。
///   * 斜杠与点分同形不同义:斜杠 `sa_std/io/print`(无扩展名)走探针,
///     目录存在则判 module;而点分 `sa_std.io.print` 按末段符号名判
///     symbol。同一规范路径、两种拼写、两种结论——这是任务规则的字面
///     含义,是否要统一由 Phase 3 裁决,本文件如实记录,不私自统一。
///   * 探针只对包限定路径做(spec.package 非空;相对路径的参照系是当前
///     文件目录,不是 cwd,探针无意义;绝对路径不走 cwd 探针)。探针以
///     当前工作目录为根,是尽力而为的;在仓库根目录外运行时探针找不到
///     两侧,退回语法默认 .module——权威判定在 locator(它知道包根),
///     见 classifyImportAt。
pub fn classifyImport(spec: ImportSpec) ResolveError!ImportKind {
    if (classifySyntactic(spec)) |kind| return kind;
    if (spec.package.len != 0) {
        switch (probeInDir(sio.cwd(), spec.path)) {
            .both => return error.AmbiguousImport,
            .file_only => return .symbol,
            .dir_only => return .module,
            .neither => {},
        }
    }
    return .module;
}

/// classifyImport 的根目录版:locator 用包根(或仓库根)显式调用,
/// 避免依赖进程 cwd。探针失败(根打不开)时退回语法默认 .module。
/// 相对路径与绝对路径同样跳过探针(理由同 classifyImport)。
/// openDir 接受绝对路径(openat 语义:绝对路径忽略 dirfd),故相对与
/// 绝对根目录可用同一调用打开,不用 openDirAbsolute。
pub fn classifyImportAt(spec: ImportSpec, root_path: []const u8) ResolveError!ImportKind {
    if (classifySyntactic(spec)) |kind| return kind;
    if (spec.package.len != 0) {
        var dir = sio.cwd().openDir(root_path, .{}) catch return .module;
        defer dir.close();
        switch (probeInDir(dir, spec.path)) {
            .both => return error.AmbiguousImport,
            .file_only => return .symbol,
            .dir_only => return .module,
            .neither => {},
        }
    }
    return .module;
}

// ---------------------------------------------------------------------
// 规范化
// ---------------------------------------------------------------------

/// 规约 → 规范斜杠路径。
///   * 去首尾空白、去成对双引号、去 `@version` 后缀(后缀先经
///     parseVersionSpec 校验,不合规的版本会报错,不是静默丢掉);
///   * 去点分:无 '/' 的点分按 normalizeDotted 转斜杠;
///   * 去重复斜杠、去 `.` 段;
///   * 保留 `..` 段供调用方处理(调用方结合 base dir 解析时再消解;
///     本函数不消解,因为不知道 base dir,消解会改变相对含义);
///   * 保留前导 `/`(绝对路径)。
/// 不做:不补扩展名、不补 `sa_std/` 前缀、不解析符号、不碰文件系统、
/// 不消解符号链接。空结果(`/`、`.`、`./`、空串)报 InvalidImportSpec。
pub fn canonicalize(allocator: std.mem.Allocator, raw: []const u8) ResolveError![]const u8 {
    var text = trimSpec(raw);
    text = try stripQuotes(text);
    if (std.mem.indexOfScalar(u8, text, '@')) |at| {
        const vpart = text[at + 1 ..];
        if (vpart.len == 0) return error.InvalidImportSpec;
        const parsed = try parseVersionSpec(allocator, vpart);
        allocator.free(parsed.raw);
        text = text[0..at];
    }
    if (text.len == 0) return error.InvalidImportSpec;
    try validatePathChars(text);

    const slashed = if (std.mem.indexOfScalar(u8, text, '/') == null)
        try normalizeDotted(allocator, text)
    else
        try allocator.dupe(u8, text);
    defer allocator.free(slashed);

    const absolute = std.mem.startsWith(u8, slashed, "/");
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    if (absolute) try out.append(allocator, '/');
    var segments: usize = 0;
    var first = true;
    var it = std.mem.splitScalar(u8, slashed, '/');
    while (it.next()) |seg| {
        if (seg.len == 0 or std.mem.eql(u8, seg, ".")) continue;
        if (!first) try out.append(allocator, '/');
        try out.appendSlice(allocator, seg);
        first = false;
        segments += 1;
    }
    if (segments == 0) return error.InvalidImportSpec;
    return out.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------
// 版本解析
// ---------------------------------------------------------------------

/// 解析版本请求。
/// 支持集(先扫过树内先例再定——见文件头:唯一的版本先例是 manifest
/// `version "..."` 自由字符串,无操作符、无 `@` 后缀;以下操作符是
/// Phase 2 新立的解析约定,只做记录与校验):
///   * 前导 '@' 可选(它是 import 规约里路径与版本的分隔符,如
///     `sa_std/io@^1.0` 中的 '@';单独传版本串时也可写 `@1.2.3`);
///   * 操作符可选:`=`(或无前缀)→ exact,`>=`、`<=`、`>`、`<`、`^`、`~`;
///   * 前导 `v` 可选(如 `v1.2.3`,与 git tag 写法兼容);
///   * 数字段:1–3 段,每段全数字,缺失的段为 null(`1`、`1.2`、`1.2.3`)。
/// 不支持 → UnsupportedVersion:通配符(`*`、`x`、`1.x`)、复合区间
///   (`>=1.0 <2.0`、逗号、`||`)、预发布/构建元数据(`-rc1`、`+build`)、
///   四段及以上(`1.2.3.4`)。
/// 结构残缺 → InvalidImportSpec:空串、只有 `@`/操作符/`v`、数字段为空
///   (`1..2`、`1.`、`.1`)、数字段含非法字符、数字溢出 u32。
/// 注释——sa.mod 尚无版本字段,本地树只有单一版本,解析结果现阶段只做
/// 记录与校验:版本仲裁(请求与本地版本比对、选哪个版本)是后续 Phase
/// 的事。Phase 2 不发明注册表、不做网络取包、不下载、不校验哈希。
/// 本地唯一版本事实:sa_std/sa.mod 只有 `package "sa_std"`,连 version
/// 字段都没填;manifest 的 version 字段本身是自由字符串,不是 semver。
pub fn parseVersionSpec(allocator: std.mem.Allocator, raw: []const u8) ResolveError!VersionSpec {
    const text = trimSpec(raw);
    if (text.len == 0) return error.InvalidImportSpec;

    var rest = text;
    if (rest[0] == '@') {
        rest = rest[1..];
        if (rest.len == 0) return error.InvalidImportSpec;
    }

    var op: VersionOp = .exact;
    if (std.mem.startsWith(u8, rest, ">=")) {
        op = .gte;
        rest = rest[2..];
    } else if (std.mem.startsWith(u8, rest, "<=")) {
        op = .lte;
        rest = rest[2..];
    } else if (std.mem.startsWith(u8, rest, "=")) {
        op = .exact;
        rest = rest[1..];
    } else if (std.mem.startsWith(u8, rest, ">")) {
        op = .gt;
        rest = rest[1..];
    } else if (std.mem.startsWith(u8, rest, "<")) {
        op = .lt;
        rest = rest[1..];
    } else if (std.mem.startsWith(u8, rest, "^")) {
        op = .caret;
        rest = rest[1..];
    } else if (std.mem.startsWith(u8, rest, "~")) {
        op = .tilde;
        rest = rest[1..];
    }
    if (rest.len == 0) return error.InvalidImportSpec;

    if (rest[0] == 'v' or rest[0] == 'V') {
        rest = rest[1..];
        if (rest.len == 0) return error.InvalidImportSpec;
    }

    // 先扫一遍:数字与点之外的一切字符定性。
    // 通配/复合区间/预发布/构建元数据 → UnsupportedVersion(可辨认但不支持);
    // 其他非法字符 → InvalidImportSpec(结构残缺)。
    for (rest) |c| {
        switch (c) {
            '0'...'9', '.' => {},
            '*', 'x', 'X', ' ', ',', '|', '-', '+' => return error.UnsupportedVersion,
            else => return error.InvalidImportSpec,
        }
    }

    var major: u32 = undefined;
    var minor: ?u32 = null;
    var patch: ?u32 = null;
    var it = std.mem.splitScalar(u8, rest, '.');
    var count: usize = 0;
    while (it.next()) |part| {
        if (part.len == 0) return error.InvalidImportSpec;
        count += 1;
        if (count > 3) return error.UnsupportedVersion;
        const value = std.fmt.parseInt(u32, part, 10) catch return error.InvalidImportSpec;
        switch (count) {
            1 => major = value,
            2 => minor = value,
            3 => patch = value,
            else => unreachable,
        }
    }
    if (count == 0) return error.InvalidImportSpec;

    const owned = try allocator.dupe(u8, text);
    return VersionSpec{
        .raw = owned,
        .op = op,
        .major = major,
        .minor = minor,
        .patch = patch,
    };
}

// ---------------------------------------------------------------------
// @import 抽取
// ---------------------------------------------------------------------

/// 从一段 SA 源码文本里抽出所有 @import 的规约字符串(引号内原文)。
/// 行级文本扫描,不依赖 Lexer;与真实行分类
/// (src/flattener/line_classifier_parse.zig parseImport)的口径一致:
/// 行首空白后以 `@import` 开头,后跟一对双引号,取首对双引号内容,
/// 闭合引号后只允许空白。口径不一致的行(如无闭合引号、引号后还有
/// 东西、空内容)直接跳过,不报错——抽取是尽力而为的扫描,不是解析器。
/// 局限(写明):不处理行内注释里的假 import(行首 `// @import` 不会
/// 命中,因为行首不是 `@import`;但块注释 `/* ... @import ... */`
/// 里的行若恰好行首是 `@import` 会被误抽);不处理宏生成的 import
/// (宏展开后的文本不在源码里);不处理引号内转义(与 parseImport
/// 相同,第一个 `"` 即闭合);不验证规约合法性(那是 parseImportSpec
/// 的事)。返回的每个字符串与外层切片均为 owned,调用方须逐个 free
/// 再 free 切片。
pub fn extractImportStrings(allocator: std.mem.Allocator, source: []const u8) ![][]const u8 {
    var out = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (out.items) |s| allocator.free(s);
        out.deinit(allocator);
    }
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "@import")) continue;
        const after = std.mem.trimStart(u8, trimmed["@import".len..], " \t");
        if (after.len < 2 or after[0] != '"') continue;
        const end = std.mem.indexOfScalarPos(u8, after, 1, '"') orelse continue;
        const content = after[1..end];
        const rest = std.mem.trim(u8, after[end + 1 ..], " \t\r");
        if (rest.len != 0) continue;
        if (content.len == 0) continue;
        const owned = try allocator.dupe(u8, content);
        out.append(allocator, owned) catch {
            allocator.free(owned);
            return error.OutOfMemory;
        };
    }
    return out.toOwnedSlice(allocator);
}
