pub fn emitJsonParse(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
    try writer.writeAll(" size_t pos = 0;");
    try writer.writeAll(" sa_json_node_t *nd = sa_json_parse_value(&sa_mem[x], (size_t)a1, &pos, 0);");
    try writer.writeAll(" if (nd == 0) return 0;");
    try writer.writeAll(" while (pos < (size_t)a1 && (sa_mem[x + pos] == ' ' || sa_mem[x + pos] == '\\t' || sa_mem[x + pos] == '\\n' || sa_mem[x + pos] == '\\r')) pos++;");
    try writer.writeAll(" if (pos != (size_t)a1) return 0;");
    try writer.writeAll(" return nd->h; } }\n");
}

pub fn emitJsonFree(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0) return 0;");
    try writer.writeAll(" o->h = 0; return 0; } }\n");
}

pub fn emitJsonObjectGet(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u64(a3, 0);");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (a2 == 0) return 1;");
    try writer.writeAll(" sa_u64 ci = o->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" if (m->klen == a2) {");
    try writer.writeAll(" uint32_t mk = sa_checked_addr(m->kptr, m->klen);");
    try writer.writeAll(" size_t i; int eq = 1;");
    try writer.writeAll(" for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }");
    try writer.writeAll(" if (eq) {");
    try writer.writeAll(" if (m->h == 0) m->h = sa_alloc(8);");
    try writer.writeAll(" sa_store_u64(a3, m->h); return 0; } }");
    try writer.writeAll(" ci = m->next; }");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitJsonObjectGetI64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u64(a3, 0);");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (a2 == 0) return 1;");
    try writer.writeAll(" sa_u64 ci = o->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" if (m->klen == a2) {");
    try writer.writeAll(" uint32_t mk = sa_checked_addr(m->kptr, m->klen);");
    try writer.writeAll(" size_t i; int eq = 1;");
    try writer.writeAll(" for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }");
    try writer.writeAll(" if (eq) {");
    try writer.writeAll(" if (m->kind == 2) { sa_store_u64(a3, (sa_u64)m->ival); return 0; }");
    try writer.writeAll(" if (m->kind == 3) {");
    try writer.writeAll(" union { sa_u64 u; double v; } t; t.u = m->fbits;");
    try writer.writeAll(" if (t.v != t.v) return 1;");
    try writer.writeAll(" if (t.v >= 9223372036854775808.0 || t.v < -9223372036854775808.0) return 1;");
    try writer.writeAll(" sa_i64 vv = (sa_i64)t.v;");
    try writer.writeAll(" union { sa_u64 u; double v; } u2; u2.v = (double)vv;");
    try writer.writeAll(" if (u2.u != m->fbits) return 1;");
    try writer.writeAll(" sa_store_u64(a3, (sa_u64)vv); return 0; }");
    try writer.writeAll(" return 1; } }");
    try writer.writeAll(" ci = m->next; }");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitJsonObjectGetString(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u64(a3, 0); sa_store_u64(a4, 0);");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (a2 == 0) return 1;");
    try writer.writeAll(" sa_u64 ci = o->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" if (m->klen == a2) {");
    try writer.writeAll(" uint32_t mk = sa_checked_addr(m->kptr, m->klen);");
    try writer.writeAll(" size_t i; int eq = 1;");
    try writer.writeAll(" for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }");
    try writer.writeAll(" if (eq) {");
    try writer.writeAll(" if (m->kind != 5) return 1;");
    try writer.writeAll(" sa_store_u64(a3, m->vptr); sa_store_u64(a4, m->vlen); return 0; } }");
    try writer.writeAll(" ci = m->next; }");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitJsonObjectGetBool(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u8(a3, 0);");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (a2 == 0) return 1;");
    try writer.writeAll(" sa_u64 ci = o->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" if (m->klen == a2) {");
    try writer.writeAll(" uint32_t mk = sa_checked_addr(m->kptr, m->klen);");
    try writer.writeAll(" size_t i; int eq = 1;");
    try writer.writeAll(" for (i = 0; i < (size_t)a2; i++)");
    try writer.writeAll(" if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }");
    try writer.writeAll(" if (eq) {");
    try writer.writeAll(" if (m->kind != 1) return 1;");
    try writer.writeAll(" sa_store_u8(a3, m->bval ? 1 : 0); return 0; } }");
    try writer.writeAll(" ci = m->next; }");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitJsonArrayGet(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u64(a2, 0);");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 6) return 1;");
    try writer.writeAll(" sa_u64 ci = o->first; sa_u64 i = 0;");
    try writer.writeAll(" while (ci != 0 && i < a1) {");
    try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" ci = m->next; i++; }");
    try writer.writeAll(" if (ci == 0) return 1;");
    try writer.writeAll(" { sa_json_node_t *m = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" if (m->h == 0) m->h = sa_alloc(8);");
    try writer.writeAll(" sa_store_u64(a2, m->h); return 0; } } }\n");
}

pub fn emitJsonValueCount(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u64(a1, 0);");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || (o->kind != 6 && o->kind != 7)) return 1;");
    try writer.writeAll(" sa_u64 ci = o->first; sa_u64 n = 0;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" ci = m->next; n++; }");
    try writer.writeAll(" sa_store_u64(a1, n); return 0; } }\n");
}

pub fn emitJsonAsI64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_store_u64(a1, 0);");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0) return 1;");
    try writer.writeAll(" if (o->kind == 2) { sa_store_u64(a1, (sa_u64)o->ival); return 0; }");
    try writer.writeAll(" if (o->kind == 3) {");
    try writer.writeAll(" union { sa_u64 u; double v; } t; t.u = o->fbits;");
    try writer.writeAll(" if (t.v != t.v) return 1;");
    try writer.writeAll(" if (t.v >= 9223372036854775808.0 || t.v < -9223372036854775808.0) return 1;");
    try writer.writeAll(" sa_i64 vv = (sa_i64)t.v;");
    try writer.writeAll(" union { sa_u64 u; double v; } u2; u2.v = (double)vv;");
    try writer.writeAll(" if (u2.u != o->fbits) return 1;");
    try writer.writeAll(" sa_store_u64(a1, (sa_u64)vv); return 0; }");
    try writer.writeAll(" return 1; } }\n");
}

pub fn emitJsonObjectSetString(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (a2 == 0) return 1;");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
    try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" sa_u64 nx = cm->next;");
    try writer.writeAll(" sa_json_retire_subtree(cm);");
    try writer.writeAll(" ci = nx; }");
    try writer.writeAll(" m->first = 0; }");
    try writer.writeAll(" else { m = sa_json_new();");
    try writer.writeAll(" if (m == 0) return 2;");
    try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
    try writer.writeAll(" m->klen = a2;");
    try writer.writeAll(" sa_json_append_child(o, m); }");
    try writer.writeAll(" m->kind = 5;");
    try writer.writeAll(" m->vptr = sa_json_guest_dup(a3, a4);");
    try writer.writeAll(" m->vlen = a4;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonObjectSetI64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (a2 == 0) return 1;");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
    try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" sa_u64 nx = cm->next;");
    try writer.writeAll(" sa_json_retire_subtree(cm);");
    try writer.writeAll(" ci = nx; }");
    try writer.writeAll(" m->first = 0; }");
    try writer.writeAll(" else { m = sa_json_new();");
    try writer.writeAll(" if (m == 0) return 2;");
    try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
    try writer.writeAll(" m->klen = a2;");
    try writer.writeAll(" sa_json_append_child(o, m); }");
    try writer.writeAll(" m->kind = 2;");
    try writer.writeAll(" m->ival = (sa_i64)a3;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonObjectSetF64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (a2 == 0) return 1;");
    try writer.writeAll(" union { sa_u64 u; double v; } t; t.u = a3;");
    try writer.writeAll(" if (!(t.v <= 1.7976931348623157e308 &&");
    try writer.writeAll(" t.v >= -1.7976931348623157e308)) return 1;");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
    try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" sa_u64 nx = cm->next;");
    try writer.writeAll(" sa_json_retire_subtree(cm);");
    try writer.writeAll(" ci = nx; }");
    try writer.writeAll(" m->first = 0; }");
    try writer.writeAll(" else { m = sa_json_new();");
    try writer.writeAll(" if (m == 0) return 2;");
    try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
    try writer.writeAll(" m->klen = a2;");
    try writer.writeAll(" sa_json_append_child(o, m); }");
    try writer.writeAll(" m->kind = 3;");
    try writer.writeAll(" m->fbits = a3;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonObjectSetBool(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (a2 == 0) return 1;");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
    try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" sa_u64 nx = cm->next;");
    try writer.writeAll(" sa_json_retire_subtree(cm);");
    try writer.writeAll(" ci = nx; }");
    try writer.writeAll(" m->first = 0; }");
    try writer.writeAll(" else { m = sa_json_new();");
    try writer.writeAll(" if (m == 0) return 2;");
    try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
    try writer.writeAll(" m->klen = a2;");
    try writer.writeAll(" sa_json_append_child(o, m); }");
    try writer.writeAll(" m->kind = 1;");
    try writer.writeAll(" m->bval = a3 != 0;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonObjectSetNull(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (a2 == 0) return 1;");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
    try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" sa_u64 nx = cm->next;");
    try writer.writeAll(" sa_json_retire_subtree(cm);");
    try writer.writeAll(" ci = nx; }");
    try writer.writeAll(" m->first = 0; }");
    try writer.writeAll(" else { m = sa_json_new();");
    try writer.writeAll(" if (m == 0) return 2;");
    try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
    try writer.writeAll(" m->klen = a2;");
    try writer.writeAll(" sa_json_append_child(o, m); }");
    try writer.writeAll(" m->kind = 0;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonObjectSetNode(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (a2 == 0) return 1;");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
    try writer.writeAll(" sa_json_node_t *ch = sa_json_find(a3);");
    try writer.writeAll(" if (ch == 0) return 2;");
    try writer.writeAll(" sa_json_node_t *cl = sa_json_clone_node(ch);");
    try writer.writeAll(" if (cl == 0) return 2;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
    try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
    try writer.writeAll(" while (ci != 0) {");
    try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
    try writer.writeAll(" sa_u64 nx = cm->next;");
    try writer.writeAll(" sa_json_retire_subtree(cm);");
    try writer.writeAll(" ci = nx; }");
    try writer.writeAll(" m->kind = cl->kind;");
    try writer.writeAll(" m->vptr = cl->vptr;");
    try writer.writeAll(" m->vlen = cl->vlen;");
    try writer.writeAll(" m->ival = cl->ival;");
    try writer.writeAll(" m->fbits = cl->fbits;");
    try writer.writeAll(" m->bval = cl->bval;");
    try writer.writeAll(" m->first = cl->first;");
    try writer.writeAll(" cl->first = 0;");
    try writer.writeAll(" cl->h = 0; }");
    try writer.writeAll(" else { cl->kptr = sa_json_guest_dup(a1, a2);");
    try writer.writeAll(" cl->klen = a2;");
    try writer.writeAll(" sa_json_append_child(o, cl); }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonObjectRemove(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { if (a2 == 0) return 1;");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
    try writer.writeAll(" if (m == 0) return 3;");
    try writer.writeAll(" sa_json_unlink_child(o, m);");
    try writer.writeAll(" sa_json_retire_subtree(m);");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonArrayPushString(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" {");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
    try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
    try writer.writeAll(" if (nd == 0) return 2;");
    try writer.writeAll(" nd->kind = 5;");
    try writer.writeAll(" nd->vptr = sa_json_guest_dup(a1, a2);");
    try writer.writeAll(" nd->vlen = a2;");
    try writer.writeAll(" sa_json_append_child(o, nd);");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonArrayPushI64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" {");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
    try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
    try writer.writeAll(" if (nd == 0) return 2;");
    try writer.writeAll(" nd->kind = 2;");
    try writer.writeAll(" nd->ival = (sa_i64)a1;");
    try writer.writeAll(" sa_json_append_child(o, nd);");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonArrayPushF64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" {");
    try writer.writeAll(" union { sa_u64 u; double v; } t; t.u = a1;");
    try writer.writeAll(" if (!(t.v <= 1.7976931348623157e308 &&");
    try writer.writeAll(" t.v >= -1.7976931348623157e308)) return 1;");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
    try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
    try writer.writeAll(" if (nd == 0) return 2;");
    try writer.writeAll(" nd->kind = 3;");
    try writer.writeAll(" nd->fbits = a1;");
    try writer.writeAll(" sa_json_append_child(o, nd);");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonArrayPushBool(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" {");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
    try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
    try writer.writeAll(" if (nd == 0) return 2;");
    try writer.writeAll(" nd->kind = 1;");
    try writer.writeAll(" nd->bval = a1 != 0;");
    try writer.writeAll(" sa_json_append_child(o, nd);");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonArrayPushNull(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" {");
    try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
    try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
    try writer.writeAll(" if (nd == 0) return 2;");
    try writer.writeAll(" nd->kind = 0;");
    try writer.writeAll(" sa_json_append_child(o, nd);");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonArrayPushNode(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_node_t *o = sa_json_find(a0);");
    try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
    try writer.writeAll(" sa_json_node_t *ch = sa_json_find(a1);");
    try writer.writeAll(" if (ch == 0) return 2;");
    try writer.writeAll(" sa_json_node_t *cl = sa_json_clone_node(ch);");
    try writer.writeAll(" if (cl == 0) return 2;");
    try writer.writeAll(" sa_json_append_child(o, cl);");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterNew(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    // Minified-only writers in the corpus; other whitespace modes
    // or flags fail loudly rather than emitting wrong JSON.
    try writer.writeAll(" { sa_store_u64(a5, 0);");
    try writer.writeAll(" if (a0 != 0 || a1 != 0 || a2 != 0 || a3 != 0 || a4 != 0) return 1;");
    try writer.writeAll(" unsigned i; sa_json_writer_t *w = 0;");
    try writer.writeAll(" for (i = 0; i < SA_JSON_MAX_WRITERS; i++)");
    try writer.writeAll(" if (sa_json_writers[i].h == 0) { w = &sa_json_writers[i]; break; }");
    try writer.writeAll(" if (w == 0) return 1;");
    try writer.writeAll(" { sa_u64 h = sa_alloc(8);");
    try writer.writeAll(" w->h = h; w->buf = 0; w->len = 0; w->cap = 0;");
    try writer.writeAll(" w->depth = 0; w->done = 0; w->started = 0;");
    try writer.writeAll(" w->complete = 0; w->pending = 0;");
    try writer.writeAll(" sa_store_u64(a5, h); return 0; } } }\n");
}

pub fn emitJsonWriterBeginObject(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0) return 1;");
    try writer.writeAll(" if (w->pending) w->pending = 0;");
    try writer.writeAll(" else {");
    try writer.writeAll(" if (w->depth == 0) {");
    try writer.writeAll(" if (w->complete) return 1;");
    try writer.writeAll(" w->started = 1; w->complete = 1; }");
    try writer.writeAll(" else {");
    try writer.writeAll(" if (w->first[w->depth - 1]) w->first[w->depth - 1] = 0;");
    try writer.writeAll(" else if (sa_jw_putc(w, ',')) return 1;");
    try writer.writeAll(" w->started = 1; } }");
    try writer.writeAll(" if (w->depth >= 32) return 1;");
    try writer.writeAll(" w->kinds[w->depth] = '{'; w->first[w->depth] = 1; w->depth++;");
    try writer.writeAll(" if (sa_jw_putc(w, '{')) return 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterEndObject(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0 || w->depth == 0 || w->pending) return 1;");
    try writer.writeAll(" if (w->kinds[w->depth - 1] != '{') return 1;");
    try writer.writeAll(" w->depth--;");
    try writer.writeAll(" if (sa_jw_putc(w, '}')) return 1;");
    try writer.writeAll(" if (w->depth == 0) w->complete = 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterBeginArray(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0) return 1;");
    try writer.writeAll(" if (w->pending) w->pending = 0;");
    try writer.writeAll(" else {");
    try writer.writeAll(" if (w->depth == 0) {");
    try writer.writeAll(" if (w->complete) return 1;");
    try writer.writeAll(" w->started = 1; w->complete = 1; }");
    try writer.writeAll(" else {");
    try writer.writeAll(" if (w->first[w->depth - 1]) w->first[w->depth - 1] = 0;");
    try writer.writeAll(" else if (sa_jw_putc(w, ',')) return 1;");
    try writer.writeAll(" w->started = 1; } }");
    try writer.writeAll(" if (w->depth >= 32) return 1;");
    try writer.writeAll(" w->kinds[w->depth] = '['; w->first[w->depth] = 1; w->depth++;");
    try writer.writeAll(" if (sa_jw_putc(w, '[')) return 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterEndArray(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0 || w->depth == 0 || w->pending) return 1;");
    try writer.writeAll(" if (w->kinds[w->depth - 1] != '[') return 1;");
    try writer.writeAll(" w->depth--;");
    try writer.writeAll(" if (sa_jw_putc(w, ']')) return 1;");
    try writer.writeAll(" if (w->depth == 0) w->complete = 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterFieldBool(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
    try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
    try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)(a3 ? \"true\" : \"false\"), a3 ? 4 : 5)) return 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterFieldI64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
    try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
    try writer.writeAll(" { char tmp[130];");
    try writer.writeAll(" int n = sa_fmt_int(tmp, a3, 10, 1, 0);");
    try writer.writeAll(" if (n < 0) return 1;");
    try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)tmp, (size_t)n)) return 1; }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterFieldF64(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
    try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
    try writer.writeAll(" { union { sa_u64 u; double d; } t; t.u = a3;");
    try writer.writeAll(" if (t.d != t.d) return 1;");
    try writer.writeAll(" if ((t.u & (sa_u64)0x7FF0000000000000ULL) == (sa_u64)0x7FF0000000000000ULL) return 1;");
    try writer.writeAll(" char tmp[256];");
    try writer.writeAll(" int n = snprintf(tmp, sizeof(tmp), \"%.17g\", t.d);");
    try writer.writeAll(" if (n < 0 || n >= 256) return 1;");
    try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)tmp, (size_t)n)) return 1; }");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterFieldString(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" uint32_t v = sa_checked_addr(a3, (size_t)a4);");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
    try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
    try writer.writeAll(" if (sa_jw_string(w, &sa_mem[v], (size_t)a4)) return 1;");
    try writer.writeAll(" return 0; } }\n");
}

pub fn emitJsonWriterObjectField(writer: anytype, _name: []const u8, _uniform_arity: usize, _gas: bool) !void {
    _ = _name;
    _ = _uniform_arity;
    _ = _gas;
    try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
    try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
    try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
    try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
    try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
    try writer.writeAll(" w->pending = 1;");
    try writer.writeAll(" return 0; } }\n");
}
