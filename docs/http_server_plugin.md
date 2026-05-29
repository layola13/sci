# SA-ASM HTTP Server 插件：架构与开发指南

> 状态说明：本文描述 HTTP Server 插件的目标架构和 SA-facing ABI 方向。当前独立工程位于 `/home/vscode/projects/sa_plugins/sa_plugin_http_server`，真实实现以该工程源码和 smoke tests 为准。与 `sa_net_uring` 的深度零拷贝、权限阻断、路由 ABI 完整性需要通过独立测试确认。

## 1. 架构目标与定位
`sa_http_server` 是建立在 `sa_net_uring` 极速网络基座之上的高层级网络组件，负责提供 HTTP 路由分发、中间件流水线（Middleware Pipeline）和多租户转发（Proxying）。

与传统像 Node.js / Python 的 Web 框架不同，SA 的服务器插件强调**零抽象成本**与**零系统调用开销**。在高负载情况下（比如作为大模型的 API 网关），它可以实现惊人的吞吐量。

## 2. 核心架构设计

### 2.1 依赖层级与零拷贝机制 (Zero-Copy Proxy)
- **底层 Reactor**: `sa_net_uring` 是目标网络驱动。当前插件文档中的 reactor/zero-copy 描述是设计方向，实际能力必须以插件工程源码和验证脚本为准。
- **语义层**: `sa_http_server` 只负责 HTTP 协议的解析（请求头、体、路径提取）。
- **零拷贝代理转发**: 如果你用 SA 做网关，`sa_http_server` 接受到的入站数据块可以被**直接指针映射**给 `sa_http_client` 插件的发送环，不经过任何用户态的内存复制。

### 2.2 架构层级图

```mermaid
graph TD
    subgraph 内核层 (Kernel)
        io_uring[Linux io_uring / eBPF]
    end

    subgraph SA 极速基座 (sa_net_uring)
        Reactor[Reactor 事件循环]
        SlotPool[全局预分配连接池]
    end

    subgraph 语义插件 (Plugins)
        HTTPServer[sa_http_server (路由与解包)]
        HTTPClient[sa_http_client (出站请求)]
    end

    subgraph 用户态代码 (SA-ASM 业务)
        Router[静态路由表]
        Middleware[鉴权 / 速率限制]
        Logic[业务处理]
    end

    io_uring <--> Reactor
    Reactor <--> HTTPServer
    HTTPServer --> Router
    Router --> Middleware
    Middleware --> Logic
    Logic --> HTTPClient
    HTTPClient --> io_uring
```

## 3. API 规范与 FFI 接口

和客户端插件一样，服务端的全套 API 也作为外部依赖桥接（通过 `@extern` 和 `ptr` 句柄）。公开接口应由插件工程自带 `.sai` / `.sal` 发布，并用 symbol smoke 防止 ABI 漂移。

### 3.1 完整接口定义 (`sa_http_server.sai`)
```sa
// 1. 初始化 HTTP 服务
@extern sa_http_server_new(&out_server: ptr) -> i32!

// 2. 注册静态路由
// handler: 接收一个请求并进行处理的 SA 函数指针
@extern sa_http_server_route(server: ptr, &path: ptr, path_len: u64, ^handler: ptr) -> i32!

// 3. 启动服务 (绑定 IP 和端口)
@extern sa_http_server_start(server: ptr, &host: ptr, host_len: u64, port: u16) -> i32!

// 4. 请求对象操作 (供 handler 内部使用)
@extern sa_http_req_from_ticket(ticket: ptr, &out_req: ptr) -> i32!
@extern sa_http_req_get_path(req: ptr, &out_path_ptr: ptr, &out_len: u64) -> i32
@extern sa_http_req_get_header(req: ptr, &key: ptr, key_len: u64, &out_val_ptr: ptr, &out_val_len: u64) -> i32

// 5. 响应对象生成与发送
@extern sa_http_server_resp_new(req: ptr, status: u16, &out_resp: ptr) -> i32!
@extern sa_http_server_resp_send(resp: ptr, &body_ptr: ptr, body_len: u64) -> i32!
```

## 4. 实战案例：搭建一个 Echo 服务器

下面是一个基于 `sa_http_server` 的完整服务端启动及请求处理示例：

### 4.1 启动服务器的主函数
```sa
@main() -> i32!:
L_ENTRY:
    res = call @sa_http_server_new(&server)
    _ = ? res

    #def PATH_LEN = 5
    path = alloc PATH_LEN

    res = call @sa_http_server_route(server, &path, PATH_LEN, ^handle_echo)

    #def HOST_LEN = 9
    host = alloc HOST_LEN

    res = call @sa_http_server_start(server, &host, HOST_LEN, 8080)

    !path
    !host
    return 0
```

### 4.2 路由处理器 (Handler)
处理器的签名必须符合插件约定的 ABI：接受一个代表请求的 `ticket`。

```sa
@ffi_wrapper handle_echo(ticket: ptr) -> i32!:
L_ENTRY:
    res = call @sa_http_req_from_ticket(ticket, &req)
    _ = ? res

    res = call @sa_http_server_resp_new(req, 200, &resp)
    _ = ? res

    #def BODY_LEN = 11
    body = alloc BODY_LEN

    res = call @sa_http_server_resp_send(resp, &body, BODY_LEN)
    _ = ? res

    _ = call @sa_http_server_resp_free(^resp)
    _ = call @sa_http_req_free(^req)
    !body
    return 0
```

## 5. 性能与安全性考量
1. **静态路由表**: SA 不使用昂贵的运行时正则表达式进行路由匹配，所有前缀匹配基于 AOT 编译的字典树。
2. **连接池复用**: 在 `sa_net_uring` 的支持下，并发 10 万个连接不会导致套接字分配开销，因为全部在启动时预分配 (Connection Slot Pool)。
3. **入站防火墙**: 如果需要限制来源，建议在插件之前引入 `sa_net_uring` 层级的 eBPF 或 iptables 防御模块，降低主线程被攻击面。
