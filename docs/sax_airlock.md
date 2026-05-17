# SAX DOM Airlock API 文档

> Airlock（气闸舱）是 SAX WASM 模块与浏览器 DOM 之间的**唯一合法通道**。
> 它完全遵守 SA 的气闸舱 FFI 机制（design.md §3.7 / R13），所有 DOM 操作
> 只能通过本文档列出的白名单 API 进行，禁止 WASM 代码直接访问 JS 全局对象。
>
> 架构层次：
> ```
> SA 代码（.sax / .saasm）
>     │  @extern 声明
>     ▼
> Airlock 白名单（本文档）
>     │  airlock.js 实现
>     ▼
> 浏览器 DOM / Web API
> ```

---

## 1. 安全模型

### 1.1 隔离原则

| 层 | 职责 | 信任边界 |
|----|------|---------|
| WASM（SA 代码） | 业务逻辑、状态管理 | 完全沙箱，无法直接访问 JS |
| Airlock（airlock.js） | WASM ↔ DOM 转发，参数校验 | 只转发白名单操作 |
| 浏览器 DOM | UI 渲染、事件分发 | 受 CSP 保护 |

### 1.2 防护措施

- **防 XSS**：`sax_dom_set_text` 使用 `textContent`（非 `innerHTML`），文本内容不会被解析为 HTML
- **防属性注入**：`sax_dom_set_attr` 只允许白名单属性，`href`/`src` 等敏感属性需通过专用 API
- **防代码注入**：事件绑定通过 WASM 函数导出索引（整数），不接受字符串形式的函数名
- **防 DOM 逃逸**：节点句柄（`node_handle`）是整数 ID，由 Airlock 维护映射表，WASM 无法伪造

### 1.3 在 SA 代码中的使用方式

所有 Airlock API 必须通过 `@ffi_wrapper` 包装后才能在普通 SA 函数中调用：

```saasm
// 声明 Airlock 外部函数（由 SAX Lowerer 自动生成）
@extern sax_dom_set_text(*node_handle, *text_ptr, text_len)

// 气闸舱包装（@ffi_wrapper 标记）
@ffi_wrapper sax_update_text(^node, ^text_mem, len):
L_ENTRY:
  raw_node = *node              // 降级为裸指针（Untracked）
  raw_text = *text_mem
  call @extern sax_dom_set_text(raw_node, raw_text, len)
  ret
```

---

## 2. DOM 查询与节点操作

### 2.1 节点查询

```
@extern sax_dom_query(*selector_ptr, selector_len) -> node_handle
```
- 等价 JS：`document.querySelector(selector)`
- `selector`：CSS 选择器字符串（UTF-8），长度 `selector_len` 字节
- 返回：节点句柄（`i64`，Airlock 内部映射表索引）；找不到返回 `-1`
- 只在 `@onMount` 或初始化函数中调用，**禁止**在高频 `@render` 中调用

```
@extern sax_dom_query_all(*selector_ptr, selector_len, *out_handles, max_count) -> i64
```
- 等价 JS：`document.querySelectorAll(selector)`
- 将结果写入 `out_handles` 数组（`i64[]`），返回实际找到的节点数
- `max_count`：`out_handles` 数组最大容量

### 2.2 节点创建与删除

```
@extern sax_dom_create(*tag_ptr, tag_len) -> node_handle
```
- 等价 JS：`document.createElement(tag)`
- `tag`：仅接受 DOM 白名单标签（见 `sax_syntax.md §2.1`），其他触发 Airlock 错误

```
@extern sax_dom_append_child(parent_handle, child_handle)
```
- 等价 JS：`parent.appendChild(child)`

```
@extern sax_dom_remove_child(parent_handle, child_handle)
```
- 等价 JS：`parent.removeChild(child)`

```
@extern sax_dom_remove_self(node_handle)
```
- 等价 JS：`node.remove()`
- 同时从 Airlock 映射表中释放句柄

```
@extern sax_dom_insert_before(parent_handle, new_node_handle, ref_handle)
```
- 等价 JS：`parent.insertBefore(newNode, refNode)`

---

## 3. 内容与属性操作

### 3.1 文本内容

```
@extern sax_dom_set_text(node_handle, *text_ptr, text_len)
```
- 等价 JS：`node.textContent = text`（安全，不解析 HTML）
- `text_ptr`：WASM 线性内存中的 UTF-8 字节起始地址
- `text_len`：字节数（不含 `\0`）

```
@extern sax_dom_get_text(node_handle, *buf_ptr, buf_len) -> i64
```
- 等价 JS：`node.textContent`
- 将文本写入 `buf_ptr` 缓冲区，返回实际字节数；超出 `buf_len` 则截断

### 3.2 属性操作

```
@extern sax_dom_set_attr(node_handle, *key_ptr, key_len, *val_ptr, val_len)
```
- 等价 JS：`node.setAttribute(key, val)`
- **白名单属性**：`class` `style` `value` `placeholder` `disabled` `readonly` `checked` `type` `name` `id` `title` `hidden` `width` `height` `alt` `src`（仅 `img`）
- 超出白名单触发 Airlock 错误

```
@extern sax_dom_remove_attr(node_handle, *key_ptr, key_len)
```
- 等价 JS：`node.removeAttribute(key)`

```
@extern sax_dom_get_attr(node_handle, *key_ptr, key_len, *buf_ptr, buf_len) -> i64
```
- 等价 JS：`node.getAttribute(key)`
- 返回值写入 `buf_ptr`，返回字节数

### 3.3 CSS class 操作

```
@extern sax_dom_add_class(node_handle, *cls_ptr, cls_len)
```
- 等价 JS：`node.classList.add(cls)`

```
@extern sax_dom_remove_class(node_handle, *cls_ptr, cls_len)
```
- 等价 JS：`node.classList.remove(cls)`

```
@extern sax_dom_toggle_class(node_handle, *cls_ptr, cls_len, force_i1) -> i1
```
- 等价 JS：`node.classList.toggle(cls, force)`
- 返回切换后是否包含该 class

### 3.4 表单值

```
@extern sax_dom_get_value(node_handle, *buf_ptr, buf_len) -> i64
```
- 等价 JS：`input.value`
- 用于 `oninput` / `onchange` 事件处理函数中读取用户输入

```
@extern sax_dom_set_value(node_handle, *val_ptr, val_len)
```
- 等价 JS：`input.value = val`

---

## 4. 事件系统

### 4.1 绑定事件

```
@extern sax_dom_bind_event(node_handle, *event_ptr, event_len, handler_export_idx)
```
- 等价 JS：`node.addEventListener(event, handler)`
- `handler_export_idx`：WASM 模块导出函数的整数索引（由 Lowerer 自动填入）
- **安全**：不接受字符串形式的函数名，防止注入

支持的事件名（UTF-8 字符串）：

| 事件名 | 触发时机 |
|--------|---------|
| `click` | 鼠标点击 |
| `input` | 输入框内容变化 |
| `change` | 输入框失焦且内容变化 |
| `submit` | 表单提交（自动 preventDefault） |
| `keydown` | 键盘按下 |
| `keyup` | 键盘释放 |
| `focus` | 获得焦点 |
| `blur` | 失去焦点 |
| `mouseenter` | 鼠标进入 |
| `mouseleave` | 鼠标离开 |

### 4.2 解绑事件

```
@extern sax_dom_unbind_event(node_handle, *event_ptr, event_len, handler_export_idx)
```
- 等价 JS：`node.removeEventListener(event, handler)`
- 通常在 `@onUnmount` 中调用

### 4.3 读取事件数据

事件处理函数被调用时，Airlock 自动将事件相关数据写入 WASM 的**事件数据缓冲区**（固定地址），
处理函数通过以下 API 读取：

```
@extern sax_event_get_key() -> i32
```
- 读取 `keydown`/`keyup` 事件的按键码（等价 `e.keyCode`）

```
@extern sax_event_get_data_int(idx) -> i64
```
- 读取事件绑定时通过 `data-sax-*` 属性传入的整数数据（如行索引）

```
@extern sax_event_get_input_value(*buf_ptr, buf_len) -> i64
```
- 读取 `input`/`change` 事件的当前输入值（等价 `e.target.value`）

---

## 5. 定时器与异步

### 5.1 定时器

```
@extern sax_set_timeout(handler_export_idx, delay_ms) -> timer_id
```
- 等价 JS：`setTimeout(handler, delay)`
- 返回定时器 ID（`i64`），用于取消

```
@extern sax_set_interval(handler_export_idx, interval_ms) -> timer_id
```
- 等价 JS：`setInterval(handler, interval)`

```
@extern sax_clear_timeout(timer_id)
@extern sax_clear_interval(timer_id)
```
- 等价 JS：`clearTimeout` / `clearInterval`
- **重要**：在 `@onUnmount` 中必须清理所有活跃定时器，否则 Referee 报 `SaxStateLeak`（timer_id 是 state 变量）

### 5.2 HTTP 请求（可选扩展）

HTTP API 不在 Phase 1 白名单内，作为 Phase 2 可选扩展：

```
@extern sax_http_get(*url_ptr, url_len, *buf_ptr, buf_len) -> i64
```
- 等价 JS：`await fetch(url)` 的同步版本（在 WASM worker 中执行）
- 返回响应字节数；负值表示错误码

```
@extern sax_http_post(*url_ptr, url_len, *body_ptr, body_len, *out_ptr, out_len) -> i64
```

---

## 6. 路由（Phase 2）

```
@extern sax_router_push(*path_ptr, path_len)
```
- 等价 JS：`history.pushState(null, '', path)`
- 触发 SAX 路由更新，卸载当前 `<Page>` 并挂载新 `<Page>`

```
@extern sax_router_replace(*path_ptr, path_len)
```
- 等价 JS：`history.replaceState(...)`

```
@extern sax_router_get_path(*buf_ptr, buf_len) -> i64
```
- 读取当前路径，写入 `buf_ptr`，返回字节数

---

## 7. 工具函数

以下为 Airlock 提供的轻量工具函数，避免 WASM 代码手工实现常见格式化：

```
@extern sax_itoa(value_i64, *buf_ptr, buf_len) -> i64
```
- 将 `i64` 整数转为十进制字符串，写入 `buf_ptr`，返回字节数

```
@extern sax_ftoa(value_f64, decimal_places, *buf_ptr, buf_len) -> i64
```
- 将 `f64` 浮点数转为字符串（指定小数位数）

```
@extern sax_get_time() -> i64
```
- 返回当前时间戳（毫秒，等价 `Date.now()`）

```
@extern sax_mem_copy(*dst_ptr, *src_ptr, len)
```
- 等价 `memcpy`（WASM 线性内存内部拷贝）

---

## 8. airlock.js 结构说明

`airlock.js` 由 `saasm sax build` 自动生成，**人工不应修改**。其结构如下：

```javascript
// airlock.js — 自动生成，请勿手动修改
// 由 saasm sax build 根据 .sax 源文件生成

const SAX_AIRLOCK_VERSION = "1.0";

// ── 节点句柄映射表
const _nodeMap = new Map();   // handle(i64) → DOM Element
let _nextHandle = 1;
function _alloc_handle(el) { const h = _nextHandle++; _nodeMap.set(h, el); return h; }
function _get_node(h) { return _nodeMap.get(Number(h)); }
function _free_handle(h) { _nodeMap.delete(Number(h)); }

// ── WASM 内存读写工具
let _mem;
function _read_str(ptr, len) {
  return new TextDecoder().decode(new Uint8Array(_mem.buffer, Number(ptr), Number(len)));
}
function _write_str(ptr, len, str) {
  const bytes = new TextEncoder().encode(str);
  const n = Math.min(bytes.length, Number(len));
  new Uint8Array(_mem.buffer, Number(ptr), n).set(bytes.subarray(0, n));
  return BigInt(n);
}

// ── Airlock 导入对象（传给 WebAssembly.instantiate）
export const sax_airlock = {
  sax_dom_set_text(node_h, text_ptr, text_len) {
    _get_node(node_h).textContent = _read_str(text_ptr, text_len);
  },
  sax_dom_get_value(node_h, buf_ptr, buf_len) {
    return _write_str(buf_ptr, buf_len, _get_node(node_h).value ?? "");
  },
  sax_dom_set_value(node_h, val_ptr, val_len) {
    _get_node(node_h).value = _read_str(val_ptr, val_len);
  },
  sax_dom_query(sel_ptr, sel_len) {
    const el = document.querySelector(_read_str(sel_ptr, sel_len));
    return el ? BigInt(_alloc_handle(el)) : -1n;
  },
  sax_dom_bind_event(node_h, evt_ptr, evt_len, fn_idx) {
    const el  = _get_node(node_h);
    const evt = _read_str(evt_ptr, evt_len);
    el.addEventListener(evt, () => _wasm_call(Number(fn_idx)));
  },
  sax_get_time() { return BigInt(Date.now()); },
  sax_itoa(value, buf_ptr, buf_len) {
    return _write_str(buf_ptr, buf_len, value.toString());
  },
  // ... 其余 API 按相同模式展开
};

// ── WASM 加载入口
export async function sax_init(wasm_url) {
  const { instance } = await WebAssembly.instantiateStreaming(
    fetch(wasm_url),
    { env: sax_airlock }
  );
  _mem = instance.exports.memory;
  function _wasm_call(idx) { /* 通过导出函数表调用 */ }
  instance.exports.sax_app_init();   // 调用根组件初始化
}
```

---

## 9. 白名单 API 汇总表

| API | 类别 | Phase |
|-----|------|-------|
| `sax_dom_query` | DOM 查询 | 1 |
| `sax_dom_query_all` | DOM 查询 | 1 |
| `sax_dom_create` | 节点操作 | 1 |
| `sax_dom_append_child` | 节点操作 | 1 |
| `sax_dom_remove_child` | 节点操作 | 1 |
| `sax_dom_remove_self` | 节点操作 | 1 |
| `sax_dom_insert_before` | 节点操作 | 1 |
| `sax_dom_set_text` | 内容操作 | 1 |
| `sax_dom_get_text` | 内容操作 | 1 |
| `sax_dom_set_attr` | 属性操作 | 1 |
| `sax_dom_remove_attr` | 属性操作 | 1 |
| `sax_dom_get_attr` | 属性操作 | 1 |
| `sax_dom_add_class` | CSS class | 1 |
| `sax_dom_remove_class` | CSS class | 1 |
| `sax_dom_toggle_class` | CSS class | 1 |
| `sax_dom_get_value` | 表单 | 1 |
| `sax_dom_set_value` | 表单 | 1 |
| `sax_dom_bind_event` | 事件 | 1 |
| `sax_dom_unbind_event` | 事件 | 1 |
| `sax_event_get_key` | 事件数据 | 1 |
| `sax_event_get_data_int` | 事件数据 | 1 |
| `sax_event_get_input_value` | 事件数据 | 1 |
| `sax_get_time` | 工具 | 1 |
| `sax_itoa` | 工具 | 1 |
| `sax_ftoa` | 工具 | 1 |
| `sax_mem_copy` | 工具 | 1 |
| `sax_set_timeout` | 定时器 | 2 |
| `sax_set_interval` | 定时器 | 2 |
| `sax_clear_timeout` | 定时器 | 2 |
| `sax_clear_interval` | 定时器 | 2 |
| `sax_router_push` | 路由 | 2 |
| `sax_router_replace` | 路由 | 2 |
| `sax_router_get_path` | 路由 | 2 |
| `sax_http_get` | HTTP | 2 |
| `sax_http_post` | HTTP | 2 |

Phase 1 共 **26 个** API，airlock.js 约 200 行。
