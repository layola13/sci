// DEF-RF-DSE: hand-written standard O2/O3 pipelines for the opt_level >= 1
// ("release-fast") path, transcribed from LLVM 14.0.6's legacy
// PassManagerBuilder (llvm/lib/Transforms/IPO/PassManagerBuilder.cpp) with
// exactly one deliberate deviation: DeadStoreElimination is never added.
//
// Why: upstream LLVM 14's DSE pass segfaults on legal IR produced from the
// slaredis tree at --release-fast (triage DEF-RF-DSE; fix form A ruled by
// Jev 0.70 + Gemini blind 0.72). The legacy C API offers no way to keep the
// PassManagerBuilder pipeline while excluding a single pass, so the two
// populate calls the shim used to make are re-implemented here pass for
// pass, in C++, where every factory PMB calls is reachable.
//
// Fidelity contract: the transcription mirrors PMB under exactly the
// configuration the shim used to drive through the C API --
//   OptLevel = level (1..3), SizeLevel = 0,
//   Inliner = createFunctionInliningPass(level >= 3 ? 900 : 225),
//   no extensions, LibraryInfo = nullptr, and every PMB option that comes
//   from a command-line flag or a constructor default left at that default
//   (DisableUnrollLoops=false, SLPVectorize=false, LoopVectorize=true,
//   LoopsInterleaved=true, RerollLoops=false, NewGVN=false,
//   DisableGVNLoadPRE=false, ForgetAllSCEVInLoopUnroll=false,
//   MergeFunctions=false, PrepareForLTO/ThinLTO=false, PGO off,
//   AttributorRun=NONE, EnableHotColdSplit=true, CallGraphProfile=true,
//   all other Enable* flags false, LICM MSSA caps 100/250 per LICM.cpp).
// Branches PMB would take under those settings are written out; branches it
// would not take (PGO, LTO, ThinLTO, matrix, constraint elimination, GVN
// hoist/sink, loop interchange/flatten/unroll-and-jam, simple-loop-unswitch,
// DFA jump threading, function specialization, IR outliner, merge
// functions, partial inlining, CHR, extra vectorizer passes) are absent,
// matching what PMB actually scheduled. DSE occurred in PMB in exactly one
// reachable place (addFunctionSimplificationPasses, OptLevel > 1); that
// single add is omitted and marked below. The shim's own former explicit
// DeadStoreElimination add in its post-populate tail is removed in the
// shim, so the release pipeline contains no DSE at all.

#include <llvm-c/Core.h>

#include "llvm/Analysis/GlobalsModRef.h"
#include "llvm/Analysis/ScopedNoAliasAA.h"
#include "llvm/Analysis/TypeBasedAliasAnalysis.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/Transforms/AggressiveInstCombine/AggressiveInstCombine.h"
#include "llvm/Transforms/IPO.h"
#include "llvm/Transforms/IPO/ForceFunctionAttrs.h"
#include "llvm/Transforms/IPO/FunctionAttrs.h"
#include "llvm/Transforms/IPO/InferFunctionAttrs.h"
#include "llvm/Transforms/InstCombine/InstCombine.h"
#include "llvm/Transforms/Instrumentation.h"
#include "llvm/Transforms/Scalar.h"
#include "llvm/Transforms/Scalar/GVN.h"
#include "llvm/Transforms/Scalar/LICM.h"
#include "llvm/Transforms/Utils.h"
#include "llvm/Transforms/Utils/SimplifyCFGOptions.h"
#include "llvm/Transforms/Vectorize.h"

using namespace llvm;

// ABI bridge for createCFGSimplificationPass -- the one factory used here
// whose signature crosses the C++ standard library: its second parameter
// is a std::function<bool(const Function &)>. Distro libLLVM is built
// against libstdc++, which mangles that as St8function; this TU is
// compiled by zig against libc++, which mangles it as St3__18function, so
// the plain declaration does not resolve at link time. PMB always passes
// an empty filter, so declare the factory under its exact libstdc++
// symbol name with an ABI-exact stand-in for the empty std::function: on
// x86-64 SysV a by-value std::function travels as an invisible reference,
// and an all-zero 32-byte object is an empty libstdc++ std::function (its
// manager pointer is null). Other factories take no stdlib-typed
// parameters and link normally.
#if defined(__linux__)
namespace llvm {
struct SaEmptyStdFunction {
    alignas(8) char storage[32];
};
FunctionPass *sa_create_cfg_simplification(SimplifyCFGOptions Options,
                                           const SaEmptyStdFunction *Ftor)
    __asm__("_ZN4llvm27createCFGSimplificationPassENS_18SimplifyCFGOptionsESt"
            "8functionIFbRKNS_8FunctionEEE");
} // namespace llvm
static FunctionPass *cfg_simplify(SimplifyCFGOptions Options) {
    static const SaEmptyStdFunction kEmpty = {};
    return sa_create_cfg_simplification(Options, &kEmpty);
}
#else
static FunctionPass *cfg_simplify(SimplifyCFGOptions Options) {
    return createCFGSimplificationPass(Options);
}
#endif

namespace {

// PMB hard-codes these through its members, themselves initialised from the
// LICM.cpp command-line defaults (SetLicmMssaOptCap=100,
// SetLicmMssaNoAccForPromotionCap=250); nobody overrides them here.
const unsigned kLicmMssaOptCap = 100;
const unsigned kLicmMssaNoAccForPromotionCap = 250;

// PMB::addInitialAliasAnalysisPasses with UseCFLAA at its default (None):
// TypeBasedAA then ScopedNoAliasAA. (No BasicAA wrapper: the legacy pass
// manager's alias-analysis group falls back to BasicAA on its own.)
void add_initial_alias_analysis(legacy::PassManagerBase &pm) {
    pm.add(createTypeBasedAAWrapperPass());
    pm.add(createScopedNoAliasAAWrapperPass());
}

SimplifyCFGOptions cfg_convert_switch() {
    return SimplifyCFGOptions().convertSwitchRangeToICmp(true);
}

// PMB::addFunctionSimplificationPasses, transcribed for the configuration
// above, minus createDeadStoreEliminationPass (DEF-RF-DSE).
void add_function_simplification(legacy::PassManagerBase &mpm, unsigned level) {
    mpm.add(createSROAPass());
    mpm.add(createEarlyCSEPass(true /* UseMemorySSA */));

    if (level > 1) {
        mpm.add(createSpeculativeExecutionIfHasBranchDivergencePass());
        mpm.add(createJumpThreadingPass());
        mpm.add(createCorrelatedValuePropagationPass());
    }

    mpm.add(cfg_simplify(cfg_convert_switch()));

    if (level > 2)
        mpm.add(createAggressiveInstCombinerPass());
    mpm.add(createInstructionCombiningPass());

    // SizeLevel == 0 && !DisableLibCallsShrinkWrap (default false).
    mpm.add(createLibCallsShrinkWrapPass());
    // SizeLevel == 0.
    mpm.add(createPGOMemOPSizeOptLegacyPass());

    if (level > 1)
        mpm.add(createTailCallEliminationPass());

    mpm.add(cfg_simplify(cfg_convert_switch()));
    mpm.add(createReassociatePass());

    // Loop pipeline, first segment (simple-loop-unswitch off by default, so
    // the classic LoopUnswitch runs; DivergentTarget=false).
    mpm.add(createLICMPass(kLicmMssaOptCap, kLicmMssaNoAccForPromotionCap,
                           /*AllowSpeculation=*/false));
    mpm.add(createLoopRotatePass(-1, false /* PrepareForLTO */));
    mpm.add(createLICMPass(kLicmMssaOptCap, kLicmMssaNoAccForPromotionCap,
                           /*AllowSpeculation=*/true));
    mpm.add(createLoopUnswitchPass(level < 3 /* SizeLevel(0) || OptLevel<3 */,
                                   false /* DivergentTarget */));
    mpm.add(cfg_simplify(cfg_convert_switch()));
    mpm.add(createInstructionCombiningPass());

    // Loop pipeline, second segment.
    mpm.add(createLoopIdiomPass());
    mpm.add(createIndVarSimplifyPass());
    mpm.add(createLoopDeletionPass());
    mpm.add(createSimpleLoopUnrollPass(level, false /* OnlyWhenForced =
                                               DisableUnrollLoops */,
                                        false /* ForgetSCEV */));

    mpm.add(createSROAPass());

    if (level > 1) {
        mpm.add(createMergedLoadStoreMotionPass());
        mpm.add(createGVNPass(false /* DisableGVNLoadPRE */));
    }

    mpm.add(createSCCPPass());
    mpm.add(createBitTrackingDCEPass());
    mpm.add(createInstructionCombiningPass());

    if (level > 1) {
        mpm.add(createJumpThreadingPass());
        mpm.add(createCorrelatedValuePropagationPass());
    }

    mpm.add(createAggressiveDCEPass());
    mpm.add(createMemCpyOptPass());

    if (level > 1) {
        // DEF-RF-DSE: PMB adds createDeadStoreEliminationPass() here. It is
        // deliberately omitted -- the upstream LLVM 14 DSE segfaults on
        // legal SA-emitted IR (slaredis --release-fast). The LICM that
        // followed it in PMB stays.
        mpm.add(createLICMPass(kLicmMssaOptCap, kLicmMssaNoAccForPromotionCap,
                               /*AllowSpeculation=*/true));
    }

    mpm.add(cfg_simplify(
        SimplifyCFGOptions().hoistCommonInsts(true).sinkCommonInsts(true)));
    mpm.add(createInstructionCombiningPass());
}

// PMB::addVectorPasses(IsFullLTO=false) for the configuration above:
// LoopVectorize on, SLP off, ExtraVectorizerPasses off, unroll-and-jam off.
void add_vector_passes(legacy::PassManagerBase &pm, unsigned level) {
    pm.add(createLoopVectorizePass(false /* InterleaveOnlyWhenForced =
                                              !LoopsInterleaved */,
                                   false /* VectorizeOnlyWhenForced =
                                              !LoopVectorize */));
    pm.add(createLoopLoadEliminationPass());
    pm.add(createInstructionCombiningPass());

    pm.add(cfg_simplify(
        SimplifyCFGOptions()
            .forwardSwitchCondToPhi(true)
            .convertSwitchRangeToICmp(true)
            .convertSwitchToLookupTable(true)
            .needCanonicalLoops(false)
            .hoistCommonInsts(true)
            .sinkCommonInsts(true)));

    // SLPVectorize == false: no SLP pass. VectorCombine runs regardless.
    pm.add(createVectorCombinePass());

    pm.add(createInstructionCombiningPass());
    pm.add(createLoopUnrollPass(level, false /* OnlyWhenForced =
                                              DisableUnrollLoops */,
                                false /* ForgetSCEV */));
    // !DisableUnrollLoops: cleanup after runtime unrolling.
    pm.add(createInstructionCombiningPass());
    pm.add(createLICMPass(kLicmMssaOptCap, kLicmMssaNoAccForPromotionCap,
                          /*AllowSpeculation=*/true));
    pm.add(createWarnMissedTransformationsPass());

    pm.add(createAlignmentFromAssumptionsPass());
}

} // namespace

extern "C" {

// Transcription of PassManagerBuilder::populateFunctionPassManager for
// OptLevel >= 1 with LibraryInfo == nullptr (the C API never set one).
void sa_rf_populate_function_pm(LLVMPassManagerRef fpm_ref, unsigned level) {
    legacy::FunctionPassManager &fpm =
        *reinterpret_cast<legacy::FunctionPassManager *>(fpm_ref);
    (void)level; // the populated sequence is level-independent above O0

    add_initial_alias_analysis(fpm);
    fpm.add(createLowerExpectIntrinsicPass());
    fpm.add(cfg_simplify(SimplifyCFGOptions()));
    fpm.add(createSROAPass());
    fpm.add(createEarlyCSEPass());
}

// Transcription of PassManagerBuilder::populateModulePassManager for
// OptLevel >= 1, DefaultOrPreLinkPipeline, no PGO/LTO/ThinLTO, minus DSE
// (inside add_function_simplification above).
void sa_rf_populate_module_pm(LLVMPassManagerRef mpm_ref, unsigned level) {
    legacy::PassManagerBase &mpm =
        *reinterpret_cast<legacy::PassManagerBase *>(mpm_ref);

    mpm.add(createAnnotation2MetadataLegacyPass());
    mpm.add(createForceFunctionAttrsLegacyPass());

    add_initial_alias_analysis(mpm);

    mpm.add(createInferFunctionAttrsLegacyPass());

    if (level > 2)
        mpm.add(createCallSiteSplittingPass());

    mpm.add(createIPSCCPPass());
    mpm.add(createCalledValuePropagationPass());
    mpm.add(createGlobalOptimizerPass());
    mpm.add(createPromoteMemoryToRegisterPass());
    mpm.add(createDeadArgEliminationPass());
    mpm.add(createInstructionCombiningPass());
    mpm.add(cfg_simplify(cfg_convert_switch()));

    mpm.add(createGlobalsAAWrapperPass());

    // Start of CallGraph SCC passes. The inliner is the one PMB configured
    // via LLVMPassManagerBuilderUseInlinerWithThreshold: 900 at level >= 3,
    // else 225.
    mpm.add(createPruneEHPass());
    mpm.add(createFunctionInliningPass(level >= 3 ? 900 : 225));
    if (level > 1)
        mpm.add(createOpenMPOptCGSCCLegacyPass());
    mpm.add(createPostOrderFunctionAttrsLegacyPass());
    if (level > 2)
        mpm.add(createArgumentPromotionPass());

    add_function_simplification(mpm, level);

    // Barrier after the implicit CGSCC pass manager (PMB's FIXME hack).
    mpm.add(createBarrierNoopPass());

    if (level > 1)
        mpm.add(createEliminateAvailableExternallyPass());

    mpm.add(createReversePostOrderFunctionAttrsPass());

    // RunInliner is true (an inliner was configured), so PMB re-runs the
    // global optimizer pair here.
    mpm.add(createGlobalOptimizerPass());
    mpm.add(createGlobalDCEPass());

    mpm.add(createGlobalsAAWrapperPass());
    mpm.add(createFloat2IntPass());
    mpm.add(createLowerConstantIntrinsicsPass());

    mpm.add(createLoopRotatePass(-1, false /* PrepareForLTO */));
    mpm.add(createLoopDistributePass());

    add_vector_passes(mpm, level);

    mpm.add(createStripDeadPrototypesPass());

    if (level > 1) {
        mpm.add(createGlobalDCEPass());
        mpm.add(createConstantMergePass());
    }

    // EnableHotColdSplit defaults to true; inert without profile data or
    // cold attributes, but scheduled by PMB, so scheduled here too.
    mpm.add(createHotColdSplittingPass());
    // CallGraphProfile defaults to true in the PMB constructor.
    mpm.add(createCGProfileLegacyPass());

    mpm.add(createLoopSinkPass());
    mpm.add(createInstSimplifyLegacyPass());
    mpm.add(createDivRemPairsPass());
    mpm.add(cfg_simplify(cfg_convert_switch()));

    mpm.add(createAnnotationRemarksLegacyPass());
}

} // extern "C"
