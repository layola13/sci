# Netx (网络引擎)

SA 为高并发服务器设计了其内置的网络引擎 `Netx`。它完全脱离传统的网络回调或者多重阻塞模型。围绕 Linux 的 `io_uring` 以纯数据环状列队形式运转，这是一个“极速 Event-Loop 状态机”引擎。

在最新版本中，已将许多关键的安全攻击防线补齐：解析畸形帧报文的边界溢出下溢拦截，控制数据溢出内存的防御，以及从 `ConnectionSlot` 到 `TicketQueue` 完全重写从而隔离无保护指针导致的大面积 Use-After-Free 风险。这一切都为网络服务的坚若磐石提供了保障。

## 导入
```sa
@import "sa_std/netx.sai"
```

## 核心宏与完整用法示例

下面的示例程序呈现了初始化 `Netx` 引擎并启动事件循环来消化接入的 HTTP 或者 WebSocket 票据（Ticket）的原语用法，由于其使用专门底层轮询线程和 `mmap` 的特性，这比裸调内核插槽快好几个量级。

```sa
@import "sa_std/netx.sai"

#def NetxProto_HTTP = 1
#def NetxProto_WS   = 2

@main() -> i32:
L_ENTRY:
    // 1. 初始化 Netx 引擎池 (例如：最大并发 10000 槽位，使用 4 条专用内核环读取线程)
    res_init = call @sa_netx_init(10000, 4)
    !res_init
    
    // 2. 绑定主机进行侦听
    host = utf8:"0.0.0.0"
    res_listen = call @sa_netx_listen(&host, 7, 8080)
    !res_listen

L_EVENT_LOOP:
    // 3. 开启无尽死循环消费系统产出的 Ticket 信息
    ticket = alloc Ticket_SIZE
    
    // 从底层收取一张事件票据信息（阻塞或者利用状态机模型在此点停留）
    res_recv = call @sa_netx_recv_ticket(0, ticket)

    // 4. 解析 Ticket 的事件协议内容
    op = load ticket+Ticket_op_code as u16
    slot_id = load ticket+Ticket_slot_id as u32
    proto = load ticket+Ticket_proto as u8
    
    // payload 会独立携带被 TicketQueue 安全剥离分配内存的所有权数据
    // ... 在此处根据 op 进行业务转发 ...

    // 发送回应报文数据示例（通常用于在其它子函数内执行）：
    // my_res_str = utf8:"HTTP/1.1 200 OK\r\n\r\nHello"
    // res_send = call @sa_netx_push_outbound(0, slot_id, &my_res_str, 25)

    !proto
    !slot_id
    !op
    !res_recv
    !ticket
    jmp L_EVENT_LOOP
```

## 核心 API 索引说明

由于此为与内建 C 级别接口映射绑定的系统功能（暴露于 `netx.sai` 的 `@extern` 定义中），通常你调用原生支持的方法处理：

### `@sa_netx_init(capacity: u32, threads: u32) -> i32`
启动并拉起 `io_uring` 及底层系统。该方法也会内部按参数执行安全防越界的内存空间分配检查。返回 `0` 成功，错误为系统级分配拒收。

### `@sa_netx_listen(host: ptr, host_len: u32, port: u16) -> i32`
指示该 Reactor 环境进行 TCP 的非阻塞绑定。

### `@sa_netx_recv_ticket(reactor_id: u32, ticket: ptr) -> i32`
最为核心的状态读取轮询函数，当系统在底层通过硬件触发中断解析到诸如客户端上线、载荷进入、客户端强制断开时，底层会自动生产装填到内存安全的缓冲池并发放这封含有明确生命周期的票件（Ticket）供你消费。

### `@sa_netx_push_outbound(reactor_id: u32, slot_id: u32, payload: ptr, len: u32) -> i32`
全非阻塞且避免应用层拷贝的发出回应。如果底层通讯发送环超载将返回如 `EAGAIN` 类型的标识码以启动背压流控防止堆积爆发。