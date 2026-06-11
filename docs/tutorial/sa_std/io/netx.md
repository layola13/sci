# Netx (网络引擎)

SA 为底层高并发设计并内置的网络服务器引擎 `Netx`。它完全脱离传统的网络回调或者多重阻塞模型。而是围绕 Linux `io_uring` 以纯数据环状列队为形式运转的 “Event-Loop 状态机” 系统。

在最新版本中，已将许多关键攻击防线如：解析畸形帧报文边界导致的服务下溢断言崩溃、数据溢出内存涂写（Out of memory by Dos）、以及无保护指针悬垂 (Use after free) 的风险清空，使用它变得无比稳健。

## 导入
```sa
@import "sa_std/netx.sai"
```

## 初始化

```sa
@main() -> i32:
L_ENTRY:
    // 初始化池并发上限=10000，使用4个专用分发线程
    res = call @sa_netx_init(10000, 4)

    // 绑定与侦听
    host = utf8:"0.0.0.0"
    res = call @sa_netx_listen(&host, 7, 8080)
```

## 事件驱动机制

Netx 是一部源源不断发送名为 `Ticket` 的信息的收信机。你需要像水泵抽水一样源源不断提取这个信封进行状态的转移判断。最新版中 `Ticket` 的内存独立出所有权安全池，不再会有解悬挂内存的可能。

```sa
L_EVENT_LOOP:
    // 分配并接收信件
    ticket = alloc Ticket_SIZE
    res = call @sa_netx_recv_ticket(0, ticket)

    // 解包消息信封内容
    op = load ticket+Ticket_op_code as u16
    slot_id = load ticket+Ticket_slot_id as u32
    
    // 如果需要发送数据，直接在非阻塞状态推入网卡队列
    // payload 是将要回应的字节数组
    // res = call @sa_netx_push_outbound(0, slot_id, &payload, payload_len)

    // 回收信件
    !ticket
    jmp L_EVENT_LOOP
```