# `sa layout` — 结构体布局计算

## 用途

`sa layout` 计算并打印结构体（struct）的内存布局信息，包括字段偏移量、对齐和总大小。这是 SA 汇编层手动管理内存偏移量的关键工具。

## 命令签名

```
sa layout --name <TypeName> --fields <name:ty,...>
sa layout --name <TypeName> --fields <name:ty,...> --format text|json|debug|dict
sa layout --name <TypeName> --fields <name:ty,...> --target 32|64
```

## 参数

| 参数 | 说明 | 必填 |
|---|---|---|
| `--name <TypeName>` | 结构体/类型名称（用于显示） | 是 |
| `--fields <name:ty,...>` | 逗号分隔的字段列表，每个字段 `name:type` | 是 |
| `--format text\|json\|debug\|dict` | 输出格式 | 否，默认 text |
| `--target 32\|64` | 指针宽度（32 或 64 位） | 否，默认 64 |

### 支持的字段类型

| 类型 | 描述 | 大小 |
|---|---|---|
| `i8` / `u8` | 有符号/无符号 8-bit 整数 | 1 字节 |
| `i16` / `u16` | 有符号/无符号 16-bit 整数 | 2 字节 |
| `i32` / `u32` | 有符号/无符号 32-bit 整数 | 4 字节 |
| `i64` / `u64` | 有符号/无符号 64-bit 整数 | 8 字节 |
| `ptr` | 指针（宽度取决于 target） | 4 或 8 字节 |
| `f32` / `f64` | 浮点数 | 4 / 8 字节 |
| `bool` | 布尔 | 1 字节 |

## 示例

### 文本模式

```bash
$ sa layout --name Point --fields x:i32,y:i32
Point (8 bytes)
  x:  +0 (offset 0, size 4, align 4)
  y:  +4 (offset 4, size 4, align 4)
```

```bash
$ sa layout --name Msg --fields tag:u32,data:ptr,count:i32
Msg (24 bytes, align 8)
  tag:   +0 (offset 0, size 4, align 4)
  data:  +8 (offset 8, size 8, align 8)
  count: +20 (offset 20, size 4, align 4)
```

### JSON 模式

```bash
$ sa layout --name Msg --fields tag:u32,data:ptr,count:i32 --format json
{"name":"Msg","size":24,"alignment":8,"fields":[{"name":"tag","offset":0,"size":4,"alignment":4,"type":"u32"},{"name":"data","offset":8,"size":8,"alignment":8,"type":"ptr"},{"name":"count","offset":20,"size":4,"alignment":4,"type":"i32"}]}
```

### Debug 模式

```bash
$ sa layout --name Msg --fields tag:u32,data:ptr,count:i32 --format debug
#def Msg_SIZE = 24
#def Msg_TAG = +0
#def Msg_DATA = +8
#def Msg_COUNT = +20
```

这个模式直接输出 `#def` 常量定义，可以复制粘贴到 `.sa` 源文件中使用。

### Dict 模式

```bash
$ sa layout --name Msg --fields tag:u32,data:ptr,count:i32 --format dict
#def Msg_SIZE = 24
Tag       ptr     size 4  align 4  offset +0    Msg_TAG  = +0
Data      ptr     size 8  align 8  offset +8    MEG_DATA = +8
Count     i32     size 4  align 4  offset +20   MEG_COUNT = +20
```

### 32 位目标

```bash
$ sa layout --name Msg --fields tag:u32,data:ptr,count:i32 --target 32
Msg (12 bytes, align 4)
  tag:   +0 (offset 0, size 4, align 4)
  data:  +4 (offset 4, size 4, align 4)
  count: +8 (offset 8, size 4, align 4)
```

## Agent 使用模式

```bash
# 1. 在设计结构体之前计算布局
$ sa layout --name MyStruct --fields a:i32,b:ptr,c:u64

# 2. 用 --format debug 输出 #def 常量
$ sa layout --name MyStruct --fields a:i32,b:ptr,c:u64 --format debug >> src/types.sa

# 3. 在 .sa 文件中使用生成的宏
# #def MyStruct_SIZE = 24
# #def MyStruct_A = +0
# #def MyStruct_B = +8
# #def MyStruct_C = +16
```
