# SAX DOM Airlock API 文档

> 本文档与 `src/sax/airlock_gen.zig` 的当前实现保持一致，只描述今天 `sa sax build` 真正生成的 `airlock.js`。
> 如果某个 API 没有列在这里，当前生成器就不会输出它。
> 
> 上游的 SAX parser / lowerer 负责标签、属性、事件名和 handler 名的校验；`airlock.js` 本身只做 DOM 读写和事件转发。

---

## 1. 生成物

`sa sax build <file.sax>` 生成前端三件套：

- `app.wasm`
- `airlock.js`
- `index.html`
- 以及对应的 `.sa` 侧车文件

当前 `airlock.js` 的骨架由 `src/sax/airlock_gen.zig` 直接拼出，核心成员如下：

```javascript
const SAX_AIRLOCK_VERSION = "1.0";

const _nodeMap = new Map();
const _bindingMap = new Map();
let _nextHandle = 1;
let _mem;
let _wasm_instance;

export const sax_airlock = {
  /* DOM / 属性 / class / value / 事件 / 工具函数 */
};

export async function sax_init(wasm_url) {
  const { instance } = await WebAssembly.instantiateStreaming(
    fetch(wasm_url),
    { env: sax_airlock }
  );
  _wasm_instance = instance;
  _mem = instance.exports.memory;
  if (instance.exports.sax_app_init) {
    instance.exports.sax_app_init();
  }
}
```

运行时约定：

- `nodeMap` 保存整数句柄到 DOM 节点的映射，句柄通过 `BigInt` 在 WASM 和 JS 之间传递。
- `bindingMap` 的键是 `node::evt::handler::ctx` 形式的字符串；同一键重复绑定时会先移除旧监听器。
- `_read_str` / `_write_str` 使用 `TextDecoder` / `TextEncoder` 在 WASM 线性内存里读写 UTF-8。
- `sax_init` 只做 wasm 加载和 `memory` 缓存，然后调用 `sax_app_init`。
- 当前生成器没有 `_wasm_call` 间接调用层。

---

## 2. 节点查询

```
@extern sax_dom_query(*sel_ptr: ptr, sel_len: i64) -> i64
```
- 等价 JS：`document.querySelector(selector)`
- `sel_ptr` / `sel_len` 指向 UTF-8 选择器字符串。
- 找到节点返回句柄；找不到返回 `-1n`。

```
@extern sax_dom_query_all(*sel_ptr: ptr, sel_len: i64, *out_ptr: ptr, max_count: i64) -> i64
```
- 等价 JS：`document.querySelectorAll(selector)`
- `out_ptr` 必须指向一段连续的 `i64` 缓冲区，JS 侧按 8 字节步长写入句柄。
- 返回实际写入的节点数量。

---

## 3. 节点创建与结构操作

```
@extern sax_dom_create(*tag_ptr: ptr, tag_len: i64) -> i64
```
- 等价 JS：`document.createElement(tag)`
- 标签白名单由 SAX parser / lowerer 负责；当前 `airlock.js` 不重复做校验。

```
@extern sax_dom_append_child(parent_h: i64, child_h: i64) -> void
```
- 等价 JS：`parent.appendChild(child)`

```
@extern sax_dom_remove_child(parent_h: i64, child_h: i64) -> void
```
- 等价 JS：`parent.removeChild(child)`

```
@extern sax_dom_remove_self(node_h: i64) -> void
```
- 等价 JS：`node.remove()`
- 先解绑该节点的所有监听器，再释放句柄映射。

```
@extern sax_dom_insert_before(parent_h: i64, new_h: i64, ref_h: i64) -> void
```
- 等价 JS：`parent.insertBefore(newNode, refNode)`

---

## 4. 文本、属性、class 和 value

```
@extern sax_dom_set_text(node_h: i64, *text_ptr: ptr, text_len: i64) -> void
```
- 等价 JS：`node.textContent = text`
- 通过 `_read_str` 把 WASM 内存中的 UTF-8 字节转成字符串。

```
@extern sax_dom_get_text(node_h: i64, *buf_ptr: ptr, buf_len: i64) -> i64
```
- 等价 JS：`node.textContent`
- 通过 `_write_str` 写回缓冲区，返回实际写入字节数。

```
@extern sax_dom_set_attr(node_h: i64, *key_ptr: ptr, key_len: i64, *val_ptr: ptr, val_len: i64) -> void
```
- 等价 JS：`node.setAttribute(key, val)`

```
@extern sax_dom_remove_attr(node_h: i64, *key_ptr: ptr, key_len: i64) -> void
```
- 等价 JS：`node.removeAttribute(key)`

```
@extern sax_dom_get_attr(node_h: i64, *key_ptr: ptr, key_len: i64, *buf_ptr: ptr, buf_len: i64) -> i64
```
- 等价 JS：`node.getAttribute(key)`
- 属性不存在时写回空字符串，返回 `0`。

```
@extern sax_dom_add_class(node_h: i64, *cls_ptr: ptr, cls_len: i64) -> void
```
- 等价 JS：`node.classList.add(cls)`

```
@extern sax_dom_remove_class(node_h: i64, *cls_ptr: ptr, cls_len: i64) -> void
```
- 等价 JS：`node.classList.remove(cls)`

```
@extern sax_dom_toggle_class(node_h: i64, *cls_ptr: ptr, cls_len: i64, force: i1) -> i1
```
- 等价 JS：`node.classList.toggle(cls, force)`
- JS 侧返回值会被转换成 `BigInt(1)` 或 `BigInt(0)`。

```
@extern sax_dom_get_value(node_h: i64, *buf_ptr: ptr, buf_len: i64) -> i64
```
- 等价 JS：`input.value`

```
@extern sax_dom_set_value(node_h: i64, *val_ptr: ptr, val_len: i64) -> void
```
- 等价 JS：`input.value = val`

---

## 5. 事件转发

```
@extern sax_dom_bind_event(node_h: i64, *evt_ptr: ptr, evt_len: i64, *handler_ptr: ptr, handler_len: i64, ctx: ptr) -> void
```
- 等价 JS：`node.addEventListener(evt, listener)`
- `handler_ptr` / `handler_len` 传入的是 WASM 导出函数名的字节串，不是函数表索引。
- 监听器触发时，JS 侧执行 `instance.exports[handler](ctx)`；如果导出不存在，则静默跳过。
- 重复绑定同一 `node + evt + handler + ctx` 时，会先移除旧监听器再安装新的。

```
@extern sax_dom_unbind_event(node_h: i64, *evt_ptr: ptr, evt_len: i64, *handler_ptr: ptr, handler_len: i64, ctx: ptr) -> void
```
- 等价 JS：`node.removeEventListener(evt, listener)`
- 必须使用和绑定时完全相同的 `node / evt / handler / ctx` 组合。

绑定逻辑对应的 JS 片段大致是：

```javascript
const listener = () => {
  if (_wasm_instance && _wasm_instance.exports[handler]) {
    _wasm_instance.exports[handler](ctx);
  }
};
const key = `${Number(node_h)}::${evt}::${handler}::${ctx}`;
```

---

## 6. 工具函数

```
@extern sax_get_time() -> i64
```
- 等价 JS：`Date.now()`

```
@extern sax_itoa(value: i64, *buf_ptr: ptr, buf_len: i64) -> i64
```
- 把整数写成十进制字符串并返回字节数。

```
@extern sax_ftoa(value: f64, decimals: i64, *buf_ptr: ptr, buf_len: i64) -> i64
```
- 把浮点数写成固定小数位字符串并返回字节数。

```
@extern sax_mem_copy(*dst_ptr: ptr, *src_ptr: ptr, len: i64) -> void
```
- 在 WASM 线性内存内部做字节拷贝，不分配新内存。

---

## 7. 路由与 HTTP 扩展

当前生成器已经输出以下扩展接口：

- `sax_set_timeout` / `sax_set_interval`
- `sax_clear_timeout` / `sax_clear_interval`
- `sax_http_get` / `sax_http_post`
- `sax_router_push` / `sax_router_replace` / `sax_router_get_path`

它们都挂在 `sax_airlock` 白名单对象上。路由接口直接包装 `history.pushState` / `history.replaceState`，并通过 `popstate` / `hashchange` 同步当前路径；HTTP 接口当前实现为同步请求，返回一个三字段结果块，布局与 SAX 侧 `load result+0/8/16` 的用法兼容。

以下名字仍然保留为路线图或草案内容：

- `sax_event_get_key` / `sax_event_get_data_int` / `sax_event_get_input_value`
- `_wasm_call`
