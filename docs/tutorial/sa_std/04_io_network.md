# 4. IO 与网络 (I/O & Network)

SA 提供了高效的异步和同步 I/O 原语，特别是 `Netx` 引擎利用 `io_uring` 达到极致的网络吞吐性能。近期版本对网络的健壮性做了专门优化，大幅缓解了诸如截断、OOM、溢出类型的 DoS 攻击面。

## `IO` 基础打印与字节操作
用于处理标准输出及底层流的读取/写入。

```sa
@import "sa_std/io.sa"

@const HELLO_MSG = utf8:"Hello, IO!"

@main() -> i32:
L_ENTRY:
    // 输出常量字符串，10 表示长度
    EXPAND PRINTLN HELLO_MSG, 10
    
    // 或者可以建立更复杂的 buf_reader / buf_writer 封装来进行块读写。
    return 0
```

## `Netx` (高性能并发网络)
深度结合 Linux `io_uring`，无回调、全事件循环 (Event Loop) 驱动的极速网络引擎。必须通过 `TicketQueue` 的出列/入列机制实现。

> **安全提示**：Netx 引擎已修复大量有关数据包伪造导致的 DoS 漏洞，支持在安全切片中精准丢弃畸形的 WebSocket 载荷，并在接收 Ticket 时移除了有生命周期悬垂风险的指针，由大容量块统一进行管理。

```sa
@import "sa_std/netx.sai"

#def NetxProto_HTTP = 1
#def NetxProto_WS   = 2

@main() -> i32:
L_ENTRY:
    // 初始化 Netx 引擎 (最大并发 10000 连接，使用 4 条专用的内核通讯线程)
    res = call @sa_netx_init(10000, 4)
    !res
    
    // 监听本地端口
    host = utf8:"0.0.0.0"
    res = call @sa_netx_listen(&host, 7, 8080)
    !res

L_EVENT_LOOP:
    // 申请一块包含事件信息和载荷内存的 Ticket
    ticket = alloc Ticket_SIZE
    res = call @sa_netx_recv_ticket(0, ticket)

    op = load ticket+Ticket_op_code as u16
    slot_id = load ticket+Ticket_slot_id as u32
    
    // 根据 op_code 判断是新的请求、接受、或是断开等等
    // ...

    !ticket
    jmp L_EVENT_LOOP
```

## `Path` (路径操作)
支持系统级文件系统的安全沙箱（基于安全审计下的路径隔离）和目录操作。

```sa
@import "sa_std/path.sa"
@import "sa_std/fs.sa"

@main() -> i32:
L_ENTRY:
    // 读取文件系统，经过底层严格验证符号链接是否越狱
    file_path = utf8:"/tmp/data.txt"
    EXPAND FS_READ_TO_STRING ok, content, &file_path
    !ok
    
    !content
    return 0
```