# 08. SAX: 声明式组件开发

SAX (Symbolic Affine XML) 是 SA 的 UI 方言。`.sax` 文件把结构、状态和事件逻辑放在一起，最后编译成浏览器可直接加载的 `app.wasm`、`airlock.js`、`index.html` 和对应的 `.sa`。

## 文件结构

一个 `.sax` 文件通常包含：
1. 一个或多个 `<Component>` 块。
2. 可选的 `<state>` 块。
3. DOM 树。
4. 一个或多个 `@handler:` 函数和末尾的 `!` 释放语句。

## 示例：计数器

```sax
<Component name="Counter">

  <state>
    count = 0
    last = 0
  </state>

  <div class="counter">
    <h1>{count}</h1>
    <p>Last updated: {last} ms ago</p>
    <button onclick={^inc}>+1</button>
    <button onclick={^dec}>-1</button>
    <button onclick={^reset}>Reset</button>
  </div>

  @inc:
  L_ENTRY:
    count = load state+Counter_count as i64
    count = add count, 1
    store state+Counter_count, count as i64
    last  = call @sax_get_time()
    store state+Counter_last, last as i64
    call @render()
    ret

  @dec:
  L_ENTRY:
    count = load state+Counter_count as i64
    count = sub count, 1
    store state+Counter_count, count as i64
    last  = call @sax_get_time()
    store state+Counter_last, last as i64
    call @render()
    ret

  @reset:
  L_ENTRY:
    store state+Counter_count, 0 as i64
    last  = call @sax_get_time()
    store state+Counter_last, last as i64
    call @render()
    ret

  !count !last
</Component>
```

## 编译

使用 `sa sax build` 构建浏览器包：

```bash
sa sax build counter.sax
```

默认输出目录是 `dist/`。对于 `counter.sax`，会生成：

```text
dist/app.wasm
dist/airlock.js
dist/index.html
dist/counter.sa
```

如果输入文件叫 `app.sax`，对应的 `.sa` 文件名也会变成 `app.sa`。

## 关键点

1. `<state>` 变量在 handler 里通过 `state+Component_var` 访问。
2. 文本插值 `{count}` 是只读读取。
3. `call @render()` 只应出现在 `@handler` 中。
4. 浏览器运行时只依赖 `app.wasm` 和轻量的 `airlock.js` 桥接层。

## 练习

1. 给计数器增加一个重置按钮的确认提示。
2. 再加一个 `ticks = 0` 状态，并在视图里显示它。
