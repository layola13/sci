//! src/module_loader/policy.zig — 加载器策略（Std 模块化 Phase 3，P3B）。
//!
//! 职责：把 Phase 2 RESULT §6 留给 Phase 3 的三项待裁决落成加载器策略，
//! 并给出提案 §2 的语义规则（默认 strict，放宽条件只写注释、不实现）。
//! 本文件是裁决的记录处与策略的默认值处；它不改任何现有文件的行为——
//! 接线（把裁决写进 spec.zig / locator.zig 的分类与定位）是后续任务
//! 的事，见每项裁决末尾的“接线指引”。
//!
//! =====================================================================
//! 裁决一：消歧规则——文件与 prelude 并存的真实歧义，优先文件
//! =====================================================================
//! 结论：优先文件（Disambiguation.file_first）。
//!
//! 理由：
//!   1. 真实语料 100% 是带扩展名的文件导入。实测（基线 7adf9695，
//!      2026-11-22，sa_std/ 内 @import 全量统计）：sa_std 前缀的导入
//!      185 条，185 条带已知扩展名（.sa/.sal/.sla/.sai），0 条裸写
//!      （唯一的 1 条裸形 `sa_std/...` 出自 sa_std/core/MANIFEST.md
//!      的文档行，不是代码）。点分写法全仓 0 条。歧义只在裸写
//!      （无扩展名）时才可能出现，真实代码今天根本不触发。
//!   2. 域级歧义是良性的。10 个域同时存在顶层文件与域 prelude
//!      （ffi、fmt、io、marker、mem、net、num、task、thread、time，
//!      如 sa_std/io.sa 与 sa_std/io/prelude.sa 并存）；但顶层 .sa
//!      文件是 Phase 1 的薄转发 shim（首行即 `@import "io/prelude.sa"`，
//!      见 sa_std/io.sa、sa_std/fmt.sa），文件与 prelude 指向同一规范
//!      内容。域级选文件不损失任何语义。
//!   3. 子域级歧义选文件更安全。17 处“文件 stem 与目录同名”碰撞中，
//!      按探针口径（目录侧须含 prelude.sa/.sal）只有 1 处是真歧义：
//!      sa_std/io/print——print.sa 是真实符号文件，print/prelude.sa
//!      是目录聚合。作者写出三段路径时几乎总是指单个符号文件；选
//!      prelude 会静默加载聚合体，是错模块。选文件与点分规则也一致
//!      （三段点分按末段符号名判 symbol，见裁决二）。
//!   4. 与定位器已有的顺序一致。locator.locate 对无扩展名路径先跑
//!      probeExtensions（.sa → .sal → .sla → .sai，文件优先），
//!      命中才返回；shim 与 prelude 都是后备。分类器选文件，等于让
//!      分类与定位用同一顺序，不另起一套。
//!
//! 影响：
//!   - spec.zig 的 classifyImport / classifyImportAt 里 `.both =>
//!     return error.AmbiguousImport` 改为 `.both => return .symbol`
//!    （接线指引，见下）；AmbiguousImport 变体保留，留给真正的多候选
//!     歧义（如未来的多版本树），不再用于文件/prelude 探针。
//!   - 二段裸路径（sa_std/io）是个例外：分类器按文件优先会判 symbol，
//!     但 locator.locate 对 `sa_std/<leaf>` 有域名优先规则（leaf 是
//!     域名 → 直接 locatePrelude），端到端仍解析到 prelude。分类器的
//!     kind 标注在二段路径上只是建议性的，定位器的域名规则才是终局；
//!     三段及以上路径两者一致（文件优先）。接线时不得把分类器的 kind
//!     当成定位结果去覆盖 locator 的域名规则。
//!
//! 接线指引（后续任务做，本文件不改 spec.zig）：
//!   spec.zig classifyImport 与 classifyImportAt 各一处：
//!     `.both => return error.AmbiguousImport,`
//!     → `.both => return .symbol, // P3B 裁决一：优先文件`
//!   其余分支（.file_only/.dir_only/.neither）不动。
//!
//! =====================================================================
//! 裁决二：斜杠/点分同形不同义——不统一，各走各的规则
//! =====================================================================
//! 结论：不统一（SpellingRule.keep_distinct）。斜杠无扩展名路径走探针
//! 判 module/file，点分按末段符号名（段数 >= 3 → symbol，否则 module）
//! 判——两套规则都保留，各管各的拼写。
//!
//! 现状（实测，基线 7adf9695，2026-11-22）：
//!   - 点分写法全仓 0 条：点分只是提案 §7 的逻辑模块路径形式，真实
//!     语法始终是 `@import "斜杠路径 + 扩展名"`（spec.zig 文件头已记）。
//!   - 斜杠裸写（无扩展名）在真实代码里也是 0 条（见裁决一）。
//!   - 两种拼写经 canonicalize 后归一化到同一斜杠路径，定位器看到的
//!     是一样的串；分歧只活在 classifyImport 的纯语法分类步（它按
//!     spec.raw 的原文拼写选分支），不在定位结果里。
//!   - 分歧唯一可能咬住的活例是 sa_std/io/print（见裁决一理由 3）：
//!     点分 `sa_std.io.print` → symbol；斜杠 `sa_std/io/print` → 探针
//!     .both → 现状 AmbiguousImport，裁决一落地后 → symbol。裁决一
//!     落地后，两种拼写在唯一活例上结论收敛，无需再统一规则。
//!
//! 理由：
//!   - 点分没有文件系统锚点：让点分走探针，须先 canonicalize 再探针，
//!     等于把分类器的纯语法层（classifySyntactic 不碰文件系统）与
//!     探针层合并，破坏 spec.zig 的分层；0 条真实用例不值得付这个代价。
//!   - 反过来让斜杠走段数规则会误判：二段斜杠 `sa_std/io` 按段数应判
//!     module，但定位器端到端已按域名规则给 prelude（见裁决一影响）；
//!     段数规则对斜杠没有提供比探针更多的信息。
//!   - 统一的唯一收益是“同一规范路径只有一种分类结论”，而这个结论
//!     今天在唯一活例上已由裁决一达成，不必再动代码结构。
//!
//! 影响：
//!   - classifyImport / classifyImportAt 的结构不动；classifyBySpelling
//!     （见本文件末尾）把“拼写 → 规则”的选择落成可执行函数，供加载器
//!     与后续测试复用口径。
//!   - 仍存在的表观分歧（仅分类 kind 标注层面）：二段裸路径上点分
//!     `sa_std.io` 判 module、斜杠 `sa_std/io` 探针 .both → 裁决一后
//!     判 symbol；但两者端到端都由定位器的域名规则解析到 prelude，
//!     定位结果一致。kind 标注分歧不进入定位结果，接线时不以此为准。
//!
//! 重开条件：点分写法一旦在真实代码里出现（全仓 grep
//! `@import "sa_std.` 计数 > 0），或斜杠裸写开始被使用，重开本裁决，
//! 届时以真实用例为准决定是否统一。
//!
//! =====================================================================
//! 裁决三：未知扩展名（如 .txt）——口径确认合适，修正一处表述
//! =====================================================================
//! 结论：口径确认合适，不改行为；但 spec.zig 文件头“最终由 locator
//! 以‘未知文件类型’拒绝”的表述不精确，予以修正说明。
//!
//! 实测（基线 7adf9695，2026-11-22）：全仓 sa_std 前缀导入中未知扩展
//! 名 0 条；sa_std/ 树内不存在 .txt 文件（只有 .md 文档，且从未被
//! import）。口径今天不咬住任何真实输入。
//!
//! 实际拒绝路径（按 locator.zig / spec.zig 代码逐段核对）：
//!   1. 分类器：hasKnownExtension 不认 .txt → 不判 symbol，落到探针/
//!      默认分支（默认 .module），不报错——分类器只分类，不拒绝。
//!   2. 归一化：normalizeSpecifier 只剥已知扩展名；未知后缀的点号被
//!      当作分隔符转斜杠——`sa_std/io/readme.txt` 归一化为
//!      `sa_std/io/readme/txt`（多出一段）。
//!   3. 定位器：knownExtension(rel_path) 为 null → probeExtensions 对
//!      整段 `io/readme/txt` 试 `.sa/.sal/.sla/.sai` → 无命中；
//!      再试顶层 shim → 无命中；最终报 ModuleNotFound。
//!
//! 修正说明：
//!   - 拒绝的错误是 ModuleNotFound，不是“未知文件类型”——ResolveError
//!     里没有表示“未知文件类型”的变体，locator 也没有扩展名校验步骤；
//!     拒绝发生在路径解析层面（未知后缀被当成路径段参与归一化），不是
//!     在扩展名校验层面。spec.zig 文件头的措辞应改成“最终由 locator
//!     以 ModuleNotFound 拒绝”，但本次不改 spec.zig（只新增文件），
//!     修正记在这里，接线任务顺手改注释。
//!   - 潜在 quirks（记录在案，不修）：`a/b.txt` 归一化为 `a/b/txt`，
//!     理论上可能与真实文件 `a/b/txt.sa` 碰撞而被误定位。今天无此
//!     碰撞（sa_std/ 内无 .txt 文件、无名为 txt 的叶文件）；若将来
//!     有 .txt（或同类）文件进入 sa_std/，须在 normalizeSpecifier 层
//!     显式拒绝未知扩展名，而不是依赖路径解析自然失败。
//!
//! 影响：
//!   - 本次不给 ResolveError 加新变体、不在 normalizeSpecifier 加未知
//!     扩展名校验（那会改变所有调用方的归一化语义，超出 P3B 范围）。
//!   - 未来的精确诊断（想要 `error.UnknownExtension` 之类的可区分错
//!     误）须另立任务，并同时处理上条的归一化碰撞问题。
//!
//! =====================================================================
//! 语义规则（提案 §2）：环合法性由语义规则定
//! =====================================================================
//! 默认规则：strict——任何环 → ImportCycle，与现行 flattener 行为一致
//! （expandimportsinto.zig 的 active_paths 检查）。本文件把 strict
//! 作为 LoaderPolicy.cycle 的默认值；cycle.zig 的 CyclePolicy.strict
//! 是它的执行件。
//!
//! 未来放宽的条件（只写在这里，不实现、不落成代码）：
//!   - 仅类型引用构成的环可放行：环上每条边都只引用类型（不引用值、
//!     不调用函数、不产生运行期依赖）时，加载器可按“先声明后定义”
//!     的方式分阶段加载，环不再是错误。此条件需要类型/值依赖的区分
//!     能力与分阶段加载的实现，今天两者都没有，所以只是条件陈述。
//!   - 其他放宽（如“环内某条边是弱引用/延迟加载”）须由语义规则任务
//!     逐条立项、逐条给判定实现；不得以 CyclePolicy.permissive_hook
//!     的存在本身作为“环合法”的依据。
//!
//! 纪律：
//!   - permissive_hook 是策略枚举里的预留值，不是语义判断。生产加载
//!     器在放宽规则落地前不得选用它；cycle.zig 的 checkCycle 在
//!     permissive_hook 下只是“发现环后放行并丢弃记录”，不是“判定环
//!     合法”。
//!   - 任何放宽实现必须先有判定（哪条边是纯类型引用）再有放行；
//!     顺序反过来（先放行、事后补判定）等于静默吞环，与 flattener
//!     现行行为的等价性即告破坏。
//!
//! =====================================================================
//! 本文件不做的事
//! =====================================================================
//!   - 不改 spec.zig / locator.zig / types.zig / closure.zig /
//!     flattener 的任何文件（P3B 只新增 src/module_loader/ 下文件）；
//!     三项裁决的接线指引见各节，接线由后续任务执行。
//!   - 不跑构建、不跑测试（见任务约束）；本文件只做策略记录与可执行
//!     的口径函数（disambiguate / classifyBySpelling /
//!     isKnownSourceExtension），不做磁盘 I/O、不读文件。
//!   - 不处理相对路径导入的基准目录（`@import "cell/arc.sa"` 的 base
//!     dir 解析，见 locator.zig 已知缺口）与中间层 shim 扩展——那是
//!     定位器接线任务的范围，不属于三项裁决。

const std = @import("std");
const types = @import("../module_resolver/types.zig");
const spec = @import("../module_resolver/spec.zig");
const cycle = @import("cycle.zig");

pub const CyclePolicy = cycle.CyclePolicy;
pub const ImportKind = types.ImportKind;
pub const ResolveError = types.ResolveError;

/// 已知的 SA 源文件扩展名（与 spec.zig 的 source_extensions 同一表，
/// 直接复用，不另起一份——两表分叉是分类与定位不一致的源头）。
pub const known_source_extensions = spec.source_extensions;

// ---------------------------------------------------------------------
// 策略值
// ---------------------------------------------------------------------

/// 文件与 prelude 并存时的消歧方向（裁决一）。
pub const Disambiguation = enum {
    /// 优先文件（已裁决采用）。探针 .both 时判 symbol。
    file_first,
    /// 优先 prelude（已否决：见裁决一理由 3，子域级会错载聚合体）。
    prelude_first,
    /// 报 error.AmbiguousImport（Phase 2 现状；已否决：真实代码 0 触发，
    /// 且首个裸写三段路径就会误报）。
    ambiguous_error,

    /// 已裁决的默认值。
    pub const default: Disambiguation = .file_first;
};

/// 斜杠与点分两种拼写的分类关系（裁决二）。
pub const SpellingRule = enum {
    /// 各走各的规则（已裁决采用）：斜杠走探针，点分按段数。
    keep_distinct,
    /// 统一走探针（已否决：点分无文件系统锚点，须先归一化，破坏分层）。
    unified_probe,
    /// 统一按段数（已否决：二段斜杠的段数结论与定位器域名规则重复，
    /// 且不提供比探针更多的信息）。
    unified_segment_count,

    /// 已裁决的默认值。
    pub const default: SpellingRule = .keep_distinct;
};

/// 未知扩展名的处置（裁决三）。
pub const UnknownExtensionRule = enum {
    /// 不判 symbol，落到探针/默认分支，最终由 locator 以
    /// ModuleNotFound 拒绝（已裁决采用；措辞修正见裁决三）。
    probe_then_reject,
    /// 在归一化层显式拒绝未知扩展名（已否决于本次：会改变所有调用方
    /// 的归一化语义；待 .txt 之类文件进入 sa_std/ 或需要精确诊断时
    /// 另立任务，并同时处理归一化碰撞问题）。
    reject_early,

    /// 已裁决的默认值。
    pub const default: UnknownExtensionRule = .probe_then_reject;
};

/// 加载器策略聚合：三项裁决 + 环策略（默认 strict）。
/// 字段默认即裁决结论；调用方用结构体字面量覆盖某一项即可。
pub const LoaderPolicy = struct {
    cycle: CyclePolicy = .strict,
    disambiguation: Disambiguation = .file_first,
    spelling: SpellingRule = .keep_distinct,
    unknown_extension: UnknownExtensionRule = .probe_then_reject,

    /// 已裁决的默认策略（全字段默认值）。
    pub const default: LoaderPolicy = .{};
};

/// 默认策略常量（与 LoaderPolicy.default 同值，供不便写结构体字面量
/// 的调用方复用）。
pub const default_policy: LoaderPolicy = .{};

/// 策略的一行摘要（供日志用），形如
/// `cycle=strict, disambiguation=file_first, spelling=keep_distinct,
/// unknown_extension=probe_then_reject`。返回 owned 串，调用方释放。
pub fn describePolicy(allocator: std.mem.Allocator, policy: LoaderPolicy) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "cycle={s}, disambiguation={s}, spelling={s}, unknown_extension={s}",
        .{
            policy.cycle.name(),
            @tagName(policy.disambiguation),
            @tagName(policy.spelling),
            @tagName(policy.unknown_extension),
        },
    );
}

// ---------------------------------------------------------------------
// 裁决一的可执行口径：探针结果 → ImportKind
// ---------------------------------------------------------------------

/// 按裁决一（优先文件）把探针结果翻成分类。
///
///   - has_file=true, has_prelude=false → .symbol（仅文件）。
///   - has_file=false, has_prelude=true → .module（仅目录 prelude）。
///   - 两侧并存 → .symbol（文件优先；裁决一的核心）。
///   - 两侧皆无 → null：探针无结论，调用方取语法默认 .module（缺失由
///     locator 报 ModuleNotFound，不是分类器的职责）——与 spec.zig 的
///     classifyImport 里 `.neither => {}`（落到默认 .module）同义。
///
/// `policy` 参数让否决掉的选项仍可被表达（测试与未来重开裁决用）：
/// .prelude_first 时两侧并存 → .module；.ambiguous_error 时两侧并存
/// 的调用方应把本函数的返回值视为不可用——本函数无法返回错误，故
/// .ambiguous_error 分支返回 null 并由调用方自行报 AmbiguousImport；
/// 为避免静默误用，见 disambiguateOrError。
pub fn disambiguate(
    policy: Disambiguation,
    has_file: bool,
    has_prelude: bool,
) ?ImportKind {
    if (has_file and has_prelude) {
        return switch (policy) {
            .file_first => .symbol,
            .prelude_first => .module,
            .ambiguous_error => null,
        };
    }
    if (has_file) return .symbol;
    if (has_prelude) return .module;
    return null;
}

/// disambiguate 的报错版：两侧并存且策略为 .ambiguous_error 时返回
/// error.AmbiguousImport（Phase 2 现状的等价行为）；其余情况与
/// disambiguate 一致，两侧皆无时返回 null（调用方取默认 .module）。
/// 默认策略（file_first）下本函数永不返回 AmbiguousImport。
pub fn disambiguateOrError(
    policy: Disambiguation,
    has_file: bool,
    has_prelude: bool,
) ResolveError!?ImportKind {
    if (has_file and has_prelude and policy == .ambiguous_error) {
        return error.AmbiguousImport;
    }
    return disambiguate(policy, has_file, has_prelude);
}

// ---------------------------------------------------------------------
// 裁决二的可执行口径：拼写 → 分类规则
// ---------------------------------------------------------------------

/// import 说明符的拼写形式（按原文，不看归一化结果）。
pub const ImportSpelling = enum {
    /// 点分：`sa_std.io.print`（逻辑形式，全仓 0 条真实用例）。
    dotted,
    /// 斜杠：`sa_std/io/print`（真实语法）。
    slash,
};

/// 点分规则（classifySyntactic 的同款口径，抽出来供复用）：
/// 段数 >= 3 时末段是符号名 → .symbol；段数 <= 2 时是包名/域名 →
/// .module。段数按归一化后的斜杠路径计（点分段数与斜杠段数一一对应）。
/// 段数为 0 是非法输入，调用方应先由 parseImportSpec 拦掉；此处防御
/// 性地返回 .module（与 classifyImport 的语法默认一致）。
pub fn dottedSegmentKind(segment_count: usize) ImportKind {
    if (segment_count >= 3) return .symbol;
    return .module;
}

/// 按拼选规则分类（裁决二：不统一）。
///
///   - dotted → dottedSegmentKind(segment_count)，探针参数忽略（点分
///     没有文件系统锚点，不走探针；见裁决二理由）。
///   - slash → disambiguate(disambiguation, has_file, has_prelude)；
///     返回 null 表示探针无结论（两侧皆无），调用方取默认 .module。
///
/// `disambiguation` 只影响 slash 分支；裁决二本身只定“两套规则并存”，
/// 斜杠分支内部的文件优先由裁决一给定。
pub fn classifyBySpelling(
    spelling: ImportSpelling,
    disambiguation: Disambiguation,
    segment_count: usize,
    has_file: bool,
    has_prelude: bool,
) ?ImportKind {
    return switch (spelling) {
        .dotted => dottedSegmentKind(segment_count),
        .slash => disambiguate(disambiguation, has_file, has_prelude),
    };
}

// ---------------------------------------------------------------------
// 裁决三的可执行口径：扩展名识别
// ---------------------------------------------------------------------

/// 路径是否以已知 SA 源文件扩展名结尾（.sa/.sal/.sla/.sai）。
/// 未知扩展名（如 .txt）返回 false——不判 symbol（裁决三）；调用方
/// 按探针/默认分支继续走，最终由 locator 以 ModuleNotFound 拒绝。
/// 注意：本函数只看后缀，不做归一化；`a/b.txt` 的点号转斜杠发生在
/// normalizeSpecifier 里（见裁决三“实际拒绝路径”第 2 步与潜在
/// quirks）。
pub fn isKnownSourceExtension(path: []const u8) bool {
    for (known_source_extensions) |ext| {
        if (std.mem.endsWith(u8, path, ext)) return true;
    }
    return false;
}

/// 未知扩展名最终被拒绝时 locator 返回的错误（裁决三修正说明）：
/// ModuleNotFound——ResolveError 里没有“未知文件类型”变体，拒绝发生在
/// 路径解析层面。供诊断文案与测试断言复用口径，避免复述 spec.zig
/// 文件头的旧措辞。
pub const unknown_extension_rejection: ResolveError = error.ModuleNotFound;
