const std = @import("std");
const call = @import("../referee/call.zig");
const referee = @import("../referee.zig");
const atomic = @import("../common/atomic.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const FrameRegs = @import("memory.zig").FrameRegs;
const FunctionRange = @import("memory.zig").FunctionRange;
const Memory = @import("memory.zig").Memory;
const RegValue = @import("memory.zig").RegValue;
const SysCallOutcome = @import("memory.zig").SysCallOutcome;
const interpreter_init = @import("interpreter_init.zig");
const interpreter_opbinary = @import("interpreter_opbinary.zig");
const interpreter_execfunction = @import("interpreter_execfunction.zig");

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    program: *const referee.VerifyOk,
    ranges: []FunctionRange,
    function_index_by_name: std.StringHashMap(usize),
    argv: [][]const u8,
    argv_storage: [][]u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    const_addrs: std.StringHashMap(u64),
    anon_const_addrs: std.StringHashMap(u64),
    anon_const_keys: std.array_list.Managed([]u8),
    memory: Memory,
    trace_runtime: bool = false,
    exit_code: ?u8 = null,
    call_depth: usize = 0,
    pub fn init(
        allocator: std.mem.Allocator,
        program: *const referee.VerifyOk,
        argv: []const []const u8,
        stdout: *std.Io.Writer,
        stderr: *std.Io.Writer,
    ) !Interpreter { return interpreter_init.initImpl(allocator, program, argv, stdout, stderr); }
    pub fn deinit(self: *Interpreter) void { return interpreter_init.deinitImpl(self); }
    pub fn materializeAnonStringConsts(self: *Interpreter) !void { return interpreter_init.materializeAnonStringConstsImpl(self); }
    pub fn traceRuntime(allocator: std.mem.Allocator) !bool { return interpreter_init.traceRuntimeImpl(allocator); }
    pub fn constPointerValue(self: *Interpreter, id: u32) ?RegValue { return interpreter_init.constPointerValueImpl(self, id); }
    pub fn primWidth(ty: sig.PrimType) u32 { return interpreter_init.primWidthImpl(ty); }
    pub fn isSignedInt(ty: sig.PrimType) bool { return interpreter_init.isSignedIntImpl(ty); }
    pub fn isIntLike(ty: sig.PrimType) bool { return interpreter_init.isIntLikeImpl(ty); }
    pub fn isFloatLike(ty: sig.PrimType) bool { return interpreter_init.isFloatLikeImpl(ty); }
    pub fn intValueAsOffset(value: RegValue) i64 { return interpreter_init.intValueAsOffsetImpl(value); }
    pub fn maskForWidth(width: u32) u64 { return interpreter_init.maskForWidthImpl(width); }
    pub fn valueFromInt(ty: sig.PrimType, value: i128) !RegValue { return interpreter_init.valueFromIntImpl(ty, value); }
    pub fn valueFromFloat(ty: sig.PrimType, value: f64) !RegValue { return interpreter_init.valueFromFloatImpl(ty, value); }
    pub fn intValue(value: RegValue, signed: bool) i128 { return interpreter_init.intValueImpl(value, signed); }
    pub fn floatValue(value: RegValue) f64 { return interpreter_init.floatValueImpl(value); }
    pub fn coerce(self: *Interpreter, value: RegValue, target: sig.PrimType) !RegValue { return interpreter_init.coerceImpl(self, value, target); }
    pub fn regValueToBytes(value: RegValue) u64 { return interpreter_init.regValueToBytesImpl(value); }
    pub fn loadFromMemory(self: *Interpreter, addr: u64, ty: sig.PrimType) !RegValue { return interpreter_init.loadFromMemoryImpl(self, addr, ty); }
    pub fn storeToMemory(self: *Interpreter, addr: u64, value: RegValue, ty: sig.PrimType) !void { return interpreter_init.storeToMemoryImpl(self, addr, value, ty); }
    pub fn atomicRmwApply(op: atomic.AtomicRmwOp, target: RegValue, value: RegValue) !RegValue { return interpreter_init.atomicRmwApplyImpl(op, target, value); }
    pub fn numKind(a: RegValue, b: RegValue) enum { signed, unsigned, float } { return interpreter_init.numKindImpl(a, b); }
    pub fn opUnary(self: *Interpreter, op: inst.OpKind, value: RegValue, target: ?sig.PrimType) !RegValue { return interpreter_init.opUnaryImpl(self, op, value, target); }
    pub fn bitcastValue(value: RegValue, target: sig.PrimType) !RegValue { return interpreter_init.bitcastValueImpl(value, target); }
    pub fn opBinary(self: *Interpreter, op: inst.OpKind, a: RegValue, b: RegValue) !RegValue { return interpreter_opbinary.opBinaryImpl(self, op, a, b); }
    pub fn findFunctionIndex(self: *Interpreter, name: []const u8) ?usize { return interpreter_opbinary.findFunctionIndexImpl(self, name); }
    pub fn resolveTextOperand(self: *Interpreter, range: *const FunctionRange, regs: *FrameRegs, text: []const u8) !RegValue { return interpreter_opbinary.resolveTextOperandImpl(self, range, regs, text); }
    pub fn callArgValue(self: *Interpreter, range: *const FunctionRange, regs: *FrameRegs, arg: call.ParsedArg) !RegValue { return interpreter_opbinary.callArgValueImpl(self, range, regs, arg); }
    pub fn resolveSizeOperand(self: *Interpreter, regs: *FrameRegs, operand: inst.Operand) !u64 { return interpreter_opbinary.resolveSizeOperandImpl(self, regs, operand); }
    pub fn materializeConsts(self: *Interpreter) !void { return interpreter_opbinary.materializeConstsImpl(self); }
    pub fn decodeBinaryValue(self: *Interpreter, ty: sig.PrimType, bytes: []const u8) !RegValue { return interpreter_opbinary.decodeBinaryValueImpl(self, ty, bytes); }
    pub fn decodeBinaryArgs(self: *Interpreter, sig_index: usize, arg_blob: []const u8) ![]RegValue { return interpreter_opbinary.decodeBinaryArgsImpl(self, sig_index, arg_blob); }
    pub fn parseImmediateValue(allocator: std.mem.Allocator, mem: *Memory, text: []const u8) !RegValue { return interpreter_opbinary.parseImmediateValueImpl(allocator, mem, text); }
    pub fn recordPanic(self: *Interpreter, code: u8, message: ?[]const u8) void { return interpreter_opbinary.recordPanicImpl(self, code, message); }
    pub fn printBytes(self: *Interpreter, ptr: u64, len: usize) !void { return interpreter_opbinary.printBytesImpl(self, ptr, len); }
    pub fn monotonicNowNs(self: *Interpreter) !u64 { return interpreter_opbinary.monotonicNowNsImpl(self); }
    pub fn writeUtcNow(self: *Interpreter, ptr: u64) !void { return interpreter_opbinary.writeUtcNowImpl(self, ptr); }
    pub fn handleSysCall(
        self: *Interpreter,
        name: []const u8,
        args: []const RegValue,
    ) !SysCallOutcome { return interpreter_opbinary.handleSysCallImpl(self, name, args); }
    pub fn execFunction(self: *Interpreter, sig_index: usize, arg_values: []const RegValue) anyerror!RegValue { return interpreter_execfunction.execFunctionImpl(self, sig_index, arg_values); }
    pub fn collectCallValues(self: *Interpreter, range: *const FunctionRange, parsed: call.ParsedCall, regs: *FrameRegs) ![]RegValue { return interpreter_execfunction.collectCallValuesImpl(self, range, parsed, regs); }
    pub fn collectArgs(self: *Interpreter, range: *const FunctionRange, parsed: call.ParsedCall, regs: *FrameRegs, params: []const sig.ParamSpec) ![]RegValue { return interpreter_execfunction.collectArgsImpl(self, range, parsed, regs, params); }
};
