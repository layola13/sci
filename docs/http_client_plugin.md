# SA-ASM HTTP Client 插件：架构与开发指南

## 1. 架构目标与定位
`sa_http_client` 插件是 SA-ASM 的官方原生出站网络组件。它提供极速的 HTTP/HTTPS 请求能力，特别针对 **大模型 (如 OpenAI) API 调用**、**爬虫抓取** 和 **SSE 流式响应** 进行了深度优化。

由于 SA 采用“零信任沙箱”架构，HTTP 客户端被设计为可热插拔的独立动态库 (`.so` / `.dll`)，且所有出站请求均受到 `sa.pkg` 包管理器的严格审计与拦截。

## 2. 核心架构设计

### 2.1 底层依托与 FFI 边界
- **底层引擎**: 该插件的内核由 Zig 的 `std.http.Client` 提供支持，通过 FFI (C-ABI) 桥接暴露给 SA 解释器。
- **TLS 支持**: 内置 TLS/SSL 加密，无需外部 `openssl` 依赖（使用 Zig 静态编译的 TLS 库）。
- **零拷贝流水线 (Zero-Copy)**: 为了极致性能，响应体数据尽可能通过底层的 `Ticket` 机制直接透传，如果在 `sa_http_server` 的反向代理场景下，请求可以直接转发出站，绕过用户态内存拷贝。

### 2.2 序列图：请求生命周期

```mermaid
sequenceDiagram
    participant User as SA-ASM 代码
    participant Bridge as @extern 气闸舱
    participant Plugin as sa_http_client.so
    participant Net as sa_net_uring
    
    User->>Bridge: sa_http_client_new()
    Bridge->>Plugin: FFI Call
    Plugin-->>User: Client Handle (ptr)
    
    User->>Bridge: sa_http_client_req_new(url)
    Bridge->>Plugin: Parse URL & Init Request
    Plugin-->>User: Req Handle (ptr)
    
    User->>Bridge: sa_http_client_req_send()
    Bridge->>Plugin: Initiate I/O
    Plugin->>Net: io_uring submit
    Net-->>Plugin: CQE Complete
    Plugin-->>User: Resp Handle (ptr)
    
    User->>Bridge: ! client / ! req / ! resp
    Bridge->>Plugin: Free Memory
```

## 3. API 规范与 FFI 接口

插件的调用必须通过 `@extern` 声明并在安全的气闸舱中通过 `call` 调用。

### 3.1 核心句柄类型
HTTP 插件使用不透明的 C 指针 (`ptr`) 表示三种资源，所有资源在生命周期结束时必须显式调用对应的 `_free` 方法（配合 SA 的 `!` 操作符逻辑防泄漏）：
- `Client`: HTTP 连接池管理器
- `Request`: 单次 HTTP 请求上下文
- `Response`: HTTP 响应数据

### 3.2 完整接口定义 (`sa_http_client.sai`)
```sa
// 1. 初始化客户端（use_tls=1 开启 HTTPS，0 为纯 HTTP）
@extern sa_http_client_new(use_tls: u8, &out_client: ptr) -> i32!

// 2. 创建请求
// method: 1=GET, 2=POST, 3=PUT, 4=DELETE
@extern sa_http_client_req_new(client: ptr, method: u8, &url: ptr, url_len: u64, &out_req: ptr) -> i32!

// 3. 设置 Header (按需多次调用)
@extern sa_http_client_req_add_header(req: ptr, &key: ptr, key_len: u64, &val: ptr, val_len: u64) -> i32!

// 4. 发送请求 (会阻塞直到收到响应头)
@extern sa_http_client_req_send(req: ptr, &body_ptr: ptr, body_len: u64, &out_resp: ptr) -> i32!

// 5. 读取响应
@extern sa_http_client_resp_status(resp: ptr) -> u16
@extern sa_http_client_resp_header(resp: ptr, &key: ptr, key_len: u64, &out_val: ptr) -> i32
@extern sa_http_client_resp_body_reader(resp: ptr, &out_reader: ptr) -> i32!

// 6. 资源释放 (防泄漏)
@extern sa_http_client_free(^client: ptr) -> i32!
@extern sa_http_client_req_free(^req: ptr) -> i32!
@extern sa_http_client_resp_free(^resp: ptr) -> i32!
```

## 4. 实战案例：发送 POST 请求

以下是一段真实合法的 SA-ASM 代码，演示如何使用该插件发送带有 Header 的 JSON POST 请求。

```sa
@func fetch_data() -> i32! {
    // 1. 创建开启了 TLS 的客户端
    res = call @sa_http_client_new(1, &client)
    _ = ? res

    // 2. 准备 URL (硬编码字符串)
    #def URL_LEN = 30
    url = alloc URL_LEN
    // ... 将 "https://api.example.com/data" 存入 url ...
    
    // 3. 创建 POST 请求 (Method=2)
    res = call @sa_http_client_req_new(&client, 2, &url, URL_LEN, &req)
    _ = ? res
    
    // 4. 添加 Header (Content-Type: application/json)
    // ... 假设已分配 key 和 val 寄存器 ...
    res = call @sa_http_client_req_add_header(&req, &key, 12, &val, 16)
    
    // 5. 发送 Body
    // ... 假设已分配 body_data 寄存器 ...
    res = call @sa_http_client_req_send(&req, &body_data, body_len, &resp)
    _ = ? res
    
    // 6. 获取响应状态码
    status = call @sa_http_client_resp_status(&resp)
    // 打印状态码...
    
    // 7. 严格清理内存，防止 MemoryLeak Trap
    _ = call @sa_http_client_resp_free(^resp)
    _ = call @sa_http_client_req_free(^req)
    _ = call @sa_http_client_free(^client)
    
    ! url
    return 0
}
```

## 5. 安全性与零信任 (Zero-Trust) 管控

SA-ASM 是“零信任”引擎。调用 `sa_http_client_new` 并不是随时随地合法的。

### 5.1 权限声明 (`grants`)
如果你的模块试图发起 HTTP 请求，你的项目文件 (`sa.mod`) 或包配置必须明确拥有：
```json
"grants": ["net_tx:api.example.com"]
```
如果包在未授权的上下文中调用该 FFI 接口，插件运行时会立刻截断请求，并向上层抛出 `Trap: UnauthorizedPrimitive`。

### 5.2 证书锁定 (Pinning)
除了基础的 TLS 验证外，对于极高安全要求的场景，SA 支持后端服务器证书指纹绑定，抵御中间人 (MITM) 与根证书劫持。
```json
"pinning": {
    "api.example.com": "sha256/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX="
}
```
