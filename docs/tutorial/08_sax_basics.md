# 08. SAX: 声明式组件开发

SAX (Safe Architecture XML) 是 SA 生态中用于构建视图和交互逻辑的高级 DSL。它允许你用类 HTML 的语法描述结构，同时嵌入原生的 SA-ASM 代码处理逻辑。

## SAX 文件结构
一个 `.sax` 文件通常由三部分组成：
1.  **`<state>`**：定义组件的私有状态。
2.  **`<view>`**：定义 UI 布局。
3.  **`<script>`**：编写底层的 SA-ASM 逻辑。

## 示例：计数器 (Counter)
```sax
<component name="Counter">
    <!-- 状态定义：100% 对应 SA 内存布局 -->
    <state>
        count: i32 = 0;
    </state>

    <!-- 视图：声明式绑定 -->
    <view>
        <div class="container">
            <h1>当前计数: {this.count}</h1>
            <button onclick="increment">增加</button>
            <button onclick="decrement">减少</button>
        </div>
    </view>

    <!-- 逻辑：内联 SA-ASM -->
    <script type="sa-asm">
        @increment(this: ptr) -> void:
        L_ENTRY:
            v = load this+Counter_count as i32
            new_v = add v, 1
            store this+Counter_count, new_v as i32
            return

        @decrement(this: ptr) -> void:
        L_ENTRY:
            v = load this+Counter_count as i32
            new_v = sub v, 1
            store this+Counter_count, new_v as i32
            return
    </script>
</component>
```

## 核心机制：Airlock
SAX 并不是直接操作 DOM。它通过名为 **Airlock** 的气闸舱机制：
- **逻辑层 (SA-ASM)**：运行在高性能沙箱中，处理纯数据。
- **视图层 (Renderer)**：运行在浏览器或原生窗口中。
- 当 `this.count` 发生变化时，SA 编译器会自动生成增量更新补丁（Delta Patch），通过 Airlock 发往视图层。

## 为什么使用 SAX？
1.  **极致响应**：数据变动到视图更新的延迟在微秒级，远超 React/Vue。
2.  **类型安全**：从 XML 属性到内联汇编的全链路类型检查。
3.  **轻量级**：生成的二进制极小，适合嵌入式设备或高性能 Web 应用。

## 编译 SAX
使用 `saasm sax` 子命令进行构建：

```bash
saasm sax build counter.sax -o counter.wasm
```

## 练习
1. 给计数器增加一个 "重置" 按钮。
2. 尝试在 `<state>` 中增加一个字符串类型的状态，并在视图中显示。
