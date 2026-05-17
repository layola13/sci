// Airlock JS 生成器：自动生成 WASM ↔ DOM 胶水层

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const AirlockGenerator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) AirlockGenerator {
        return .{ .allocator = allocator };
    }

    /// 生成 airlock.js 胶水层代码
    pub fn generateAirlockJS(self: *AirlockGenerator) !std.ArrayList(u8) {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        const airlock_template =
            \\// airlock.js — SAX 自动生成，请勿手动修改
            \\// WASM ↔ DOM 胶水层（Airlock 气闸舱）
            \\
            \\const SAX_AIRLOCK_VERSION = "1.0";
            \\
            \\// ── 节点句柄映射表
            \\const _nodeMap = new Map();
            \\let _nextHandle = 1;
            \\function _alloc_handle(el) {
            \\  const h = _nextHandle++;
            \\  _nodeMap.set(h, el);
            \\  return h;
            \\}
            \\function _get_node(h) {
            \\  return _nodeMap.get(Number(h));
            \\}
            \\function _free_handle(h) {
            \\  _nodeMap.delete(Number(h));
            \\}
            \\
            \\// ── WASM 内存读写工具
            \\let _mem;
            \\function _read_str(ptr, len) {
            \\  return new TextDecoder().decode(
            \\    new Uint8Array(_mem.buffer, Number(ptr), Number(len))
            \\  );
            \\}
            \\function _write_str(ptr, len, str) {
            \\  const bytes = new TextEncoder().encode(str);
            \\  const n = Math.min(bytes.length, Number(len));
            \\  new Uint8Array(_mem.buffer, Number(ptr), n).set(bytes.subarray(0, n));
            \\  return BigInt(n);
            \\}
            \\
            \\// ── Airlock 白名单 API
            \\export const sax_airlock = {
            \\  // DOM 查询
            \\  sax_dom_query(sel_ptr, sel_len) {
            \\    const sel = _read_str(sel_ptr, sel_len);
            \\    const el = document.querySelector(sel);
            \\    return el ? BigInt(_alloc_handle(el)) : -1n;
            \\  },
            \\
            \\  sax_dom_query_all(sel_ptr, sel_len, out_ptr, max_count) {
            \\    const sel = _read_str(sel_ptr, sel_len);
            \\    const els = document.querySelectorAll(sel);
            \\    const count = Math.min(els.length, Number(max_count));
            \\    for (let i = 0; i < count; i++) {
            \\      const h = BigInt(_alloc_handle(els[i]));
            \\      new BigInt64Array(_mem.buffer, Number(out_ptr) + i * 8, 1).set([h]);
            \\    }
            \\    return BigInt(count);
            \\  },
            \\
            \\  // 节点操作
            \\  sax_dom_create(tag_ptr, tag_len) {
            \\    const tag = _read_str(tag_ptr, tag_len);
            \\    const el = document.createElement(tag);
            \\    return BigInt(_alloc_handle(el));
            \\  },
            \\
            \\  sax_dom_append_child(parent_h, child_h) {
            \\    _get_node(parent_h).appendChild(_get_node(child_h));
            \\  },
            \\
            \\  sax_dom_remove_child(parent_h, child_h) {
            \\    _get_node(parent_h).removeChild(_get_node(child_h));
            \\  },
            \\
            \\  sax_dom_remove_self(node_h) {
            \\    _get_node(node_h).remove();
            \\    _free_handle(node_h);
            \\  },
            \\
            \\  sax_dom_insert_before(parent_h, new_h, ref_h) {
            \\    _get_node(parent_h).insertBefore(_get_node(new_h), _get_node(ref_h));
            \\  },
            \\
            \\  // 内容操作
            \\  sax_dom_set_text(node_h, text_ptr, text_len) {
            \\    _get_node(node_h).textContent = _read_str(text_ptr, text_len);
            \\  },
            \\
            \\  sax_dom_get_text(node_h, buf_ptr, buf_len) {
            \\    return _write_str(buf_ptr, buf_len, _get_node(node_h).textContent ?? "");
            \\  },
            \\
            \\  // 属性操作
            \\  sax_dom_set_attr(node_h, key_ptr, key_len, val_ptr, val_len) {
            \\    const key = _read_str(key_ptr, key_len);
            \\    const val = _read_str(val_ptr, val_len);
            \\    _get_node(node_h).setAttribute(key, val);
            \\  },
            \\
            \\  sax_dom_remove_attr(node_h, key_ptr, key_len) {
            \\    const key = _read_str(key_ptr, key_len);
            \\    _get_node(node_h).removeAttribute(key);
            \\  },
            \\
            \\  sax_dom_get_attr(node_h, key_ptr, key_len, buf_ptr, buf_len) {
            \\    const key = _read_str(key_ptr, key_len);
            \\    const val = _get_node(node_h).getAttribute(key) ?? "";
            \\    return _write_str(buf_ptr, buf_len, val);
            \\  },
            \\
            \\  // CSS class 操作
            \\  sax_dom_add_class(node_h, cls_ptr, cls_len) {
            \\    const cls = _read_str(cls_ptr, cls_len);
            \\    _get_node(node_h).classList.add(cls);
            \\  },
            \\
            \\  sax_dom_remove_class(node_h, cls_ptr, cls_len) {
            \\    const cls = _read_str(cls_ptr, cls_len);
            \\    _get_node(node_h).classList.remove(cls);
            \\  },
            \\
            \\  sax_dom_toggle_class(node_h, cls_ptr, cls_len, force) {
            \\    const cls = _read_str(cls_ptr, cls_len);
            \\    return BigInt(_get_node(node_h).classList.toggle(cls, !!force) ? 1 : 0);
            \\  },
            \\
            \\  // 表单值
            \\  sax_dom_get_value(node_h, buf_ptr, buf_len) {
            \\    return _write_str(buf_ptr, buf_len, _get_node(node_h).value ?? "");
            \\  },
            \\
            \\  sax_dom_set_value(node_h, val_ptr, val_len) {
            \\    _get_node(node_h).value = _read_str(val_ptr, val_len);
            \\  },
            \\
            \\  // 事件系统
            \\  sax_dom_bind_event(node_h, evt_ptr, evt_len, fn_idx) {
            \\    const evt = _read_str(evt_ptr, evt_len);
            \\    const el = _get_node(node_h);
            \\    el.addEventListener(evt, () => {
            \\      // 调用 WASM 导出函数
            \\      if (_wasm_instance && _wasm_instance.exports[fn_idx]) {
            \\        _wasm_instance.exports[fn_idx]();
            \\      }
            \\    });
            \\  },
            \\
            \\  sax_dom_unbind_event(node_h, evt_ptr, evt_len, fn_idx) {
            \\    // Phase 2: 实现事件解绑
            \\  },
            \\
            \\  // 工具函数
            \\  sax_get_time() {
            \\    return BigInt(Date.now());
            \\  },
            \\
            \\  sax_itoa(value, buf_ptr, buf_len) {
            \\    return _write_str(buf_ptr, buf_len, value.toString());
            \\  },
            \\
            \\  sax_ftoa(value, decimals, buf_ptr, buf_len) {
            \\    return _write_str(buf_ptr, buf_len, value.toFixed(Number(decimals)));
            \\  },
            \\
            \\  sax_mem_copy(dst_ptr, src_ptr, len) {
            \\    const dst = new Uint8Array(_mem.buffer, Number(dst_ptr), Number(len));
            \\    const src = new Uint8Array(_mem.buffer, Number(src_ptr), Number(len));
            \\    dst.set(src);
            \\  },
            \\};
            \\
            \\// ── WASM 加载入口
            \\let _wasm_instance;
            \\export async function sax_init(wasm_url) {
            \\  const { instance } = await WebAssembly.instantiateStreaming(
            \\    fetch(wasm_url),
            \\    { env: sax_airlock }
            \\  );
            \\  _wasm_instance = instance;
            \\  _mem = instance.exports.memory;
            \\  if (instance.exports.sax_app_init) {
            \\    instance.exports.sax_app_init();
            \\  }
            \\}
        ;

        try output.appendSlice(airlock_template);
        return output;
    }

    /// 生成 index.html 入口文件
    pub fn generateIndexHTML(self: *AirlockGenerator, app_name: []const u8) !std.ArrayList(u8) {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        try output.writer().print(
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\  <meta charset="UTF-8">
            \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\  <title>{s}</title>
            \\  <style>
            \\    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
            \\    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }}
            \\  </style>
            \\</head>
            \\<body>
            \\  <div id="app"></div>
            \\  <script type="module">
            \\    import {{ sax_init }} from './airlock.js';
            \\    sax_init('./{s}.wasm');
            \\  </script>
            \\</body>
            \\</html>
            , .{ app_name, app_name },
        );

        return output;
    }
};
