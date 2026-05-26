# 07. 极速网络：Netx 引擎

SA 专为高并发服务器设计。`sa_std.netx` 是其核心网络引擎，基于 Linux 的 `io_uring` 架构，旨在消灭每请求的系统调用开销。

## Netx 的核心哲学
1.  **Ticket 机制**：网络事件（连接、数据到达）不直接通过回调处理，而是生成一个紧凑的 `Ticket` 放入环形缓冲区。
2.  **零拷贝**：数据直接从网卡驱动写入预分配的连接槽缓冲区。
3.  **SIMD 加速**：WebSocket 掩码处理和 HTTP 拆包在运行时层通过向量指令加速，SA-ASM 只负责业务逻辑。

## 初始化网络引擎
在开始监听前，必须初始化引擎池：

```sa
@import "sa_std/netx.sai"

L_START:
    res = call @sa_netx_init(10000, 4)
    host = utf8:"0.0.0.0"
    res = call @sa_netx_listen(&host, 7, 8080)
```

## 处理 Ticket
Netx 就像一个生产 Ticket 的工厂，你的程序是一个消费 Ticket 的循环：

```sa
#def NetxProto_HTTP = 1
#def NetxProto_WS   = 2

L_EVENT_LOOP:
    ticket = alloc Ticket_SIZE
    res = call @sa_netx_recv_ticket(0, ticket)

    op = load ticket+Ticket_op_code as u16
    slot_id = load ticket+Ticket_slot_id as u32

    !ticket
    jmp L_EVENT_LOOP
```

## 发送数据
Netx 提供极速的出站路径：

```sa
msg = utf8:"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"
res = call @sa_netx_push_outbound(0, slot_id, &msg, 38)
```

## 性能对标
Netx 的设计目标是在同样的硬件上，吞吐量达到 Bun 的 1.2x - 1.5x，广播性能（如推送售罄消息）利用内核级 DMA 扇出，可达传统 Node.js 的 10 倍以上。

## 注意事项
- **Linux 专用**：Netx 深度依赖 io_uring，目前仅在 Linux 内核 5.10+ 上提供完整性能。
- **背压控制**：如果出站环满了，`push_outbound` 会返回 `EAGAIN`，此时业务层应当实施降级策略。

## 练习
1. 参照 `sa_std/netx.sal` 完善一个最小的 HTTP Echo 服务。
2. 思考为什么 Ticket 机制比传统的 `epoll` 回调更适合 SA 的所有权系统。
