pub fn emitSignal(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Echo the signal number back (staged oracle semantics).
    try writer.writeAll(" return a0; }\n");
}

pub fn emitDlopen(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Real zeroed region stands in for the OS handle (mirrors
    // JS __sa_alloc(8)); nonzero is what the oracle checks.
    try writer.writeAll(" return sa_alloc(8); }\n");
}

pub fn emitDlsym(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return sa_alloc(8); }\n");
}

pub fn emitDlclose(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitParseFloat(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Manual scan (whitespace/sign/digits/dot/exponent) then
    // strtod on the scanned span; no digits -> quiet NaN,
    // overflow -> signed inf (mirrors the interpreter).
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" size_t i = 0; int neg = 0;");
    try writer.writeAll(" while (i < (size_t)a1) { uint8_t c = sa_mem[x + i];");
    try writer.writeAll(" if (c != ' ' && c != '\\t' && c != '\\n' && c != '\\r' && c != '\\f' && c != '\\v') break; i++; }");
    try writer.writeAll(" if (i < (size_t)a1 && (sa_mem[x + i] == '+' || sa_mem[x + i] == '-'))");
    try writer.writeAll(" { neg = sa_mem[x + i] == '-'; i++; }");
    try writer.writeAll(" { size_t j = i; while (j < (size_t)a1 && sa_mem[x + j] >= '0' && sa_mem[x + j] <= '9') j++;");
    try writer.writeAll(" size_t nd = j - i;");
    try writer.writeAll(" if (j < (size_t)a1 && sa_mem[x + j] == '.') { j++;");
    try writer.writeAll(" while (j < (size_t)a1 && sa_mem[x + j] >= '0' && sa_mem[x + j] <= '9') j++; }");
    try writer.writeAll(" size_t nf = j - nd - (j > nd && sa_mem[x + i + nd] == '.' ? 1 : 0);");
    try writer.writeAll(" if (nd == 0 && nf == 0)");
    try writer.writeAll(" return (sa_u64)0x7FF8000000000000ULL;");
    try writer.writeAll(" size_t k = j;");
    try writer.writeAll(" if (k < (size_t)a1 && (sa_mem[x + k] == 'e' || sa_mem[x + k] == 'E')) {");
    try writer.writeAll(" size_t m = k + 1;");
    try writer.writeAll(" if (m < (size_t)a1 && (sa_mem[x + m] == '+' || sa_mem[x + m] == '-')) m++;");
    try writer.writeAll(" size_t es = m;");
    try writer.writeAll(" while (m < (size_t)a1 && sa_mem[x + m] >= '0' && sa_mem[x + m] <= '9') m++;");
    try writer.writeAll(" if (m > es) k = m; }");
    try writer.writeAll(" { sa_u64 n = (sa_u64)(k - i); sa_u64 p = sa_alloc(n + 1);");
    try writer.writeAll(" uint32_t d = sa_checked_addr(p, n + 1);");
    try writer.writeAll(" size_t q; for (q = 0; q < (size_t)n; q++)");
    try writer.writeAll(" sa_mem[d + q] = sa_mem[x + i + q];");
    try writer.writeAll(" sa_mem[d + n] = 0; errno = 0;");
    try writer.writeAll(" union { sa_u64 u; double v; } t; t.v = strtod((const char *)&sa_mem[d], 0);");
    try writer.writeAll(" if (errno == ERANGE) {");
    try writer.writeAll(" if ((t.u & (sa_u64)0x7FF0000000000000ULL) == (sa_u64)0x7FF0000000000000ULL)");
    try writer.writeAll(" t.u = neg ? (sa_u64)0xFFF0000000000000ULL : (sa_u64)0x7FF0000000000000ULL; }");
    try writer.writeAll(" if (neg) t.v = -t.v; return t.u; } } } }\n");
}
