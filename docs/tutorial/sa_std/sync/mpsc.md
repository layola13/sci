# Mpsc (多生产者单消费者通道)

提供异步与跨线程通讯的主流方案——基于 Channel 管道。

`Mpsc` 的底层内存已经全部进行了防内存溢出的修改，在使用 `NUM_U64_CHECKED_ADD` / `MUL` 防护下，极端大容量初始化将不会再导致越界与段错误崩溃。

## 导入
```sa
@import "sa_std/sync/mpsc.sa"
```

## 核心宏与用法

### `MPSC_NEW %out_chan, %cap`
根据 `%cap` 的容量创建通讯管道。如果 `%cap` 为乘法上溢数字（例如 `U64_MAX`），会被截获并 Panic 阻断安全面。

```sa
// 容量为 500
EXPAND MPSC_NEW my_chan, 500
```

### `MPSC_SEND %out_ok, %chan_reg, %message`
多方并发压入数据：

```sa
EXPAND MPSC_SEND ok, my_chan, 2048
```

### `MPSC_TRY_RECV %out_ok, %out_value, %chan_reg`
单方取出数据（非阻塞拉取）：

```sa
EXPAND MPSC_TRY_RECV ok, msg, my_chan
br ok -> L_HAS_MSG, L_NO_MSG
L_HAS_MSG:
    // 取出了来自其他线程发送过来的 msg=2048
    !msg
    !ok
```

### `MPSC_FREE %chan_reg`