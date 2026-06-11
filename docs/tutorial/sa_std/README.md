# SA 标准库 (sa_std) 参考手册

本手册包含了 `sa_std` 中每个模块的详细用法和示例。在实际开发中，大量应用这些宏来保障内存与逻辑安全。

## 目录结构
### 1. 核心与内存管理 (`core`)
- [`Arc` 线程安全引用计数](core/arc.md)
- [`Rc` 引用计数](core/rc.md)
- [`RefCell` 与 `Cell` 内部可变性](core/cell.md)
- [`Box` 堆分配](core/box.md)
- [`Option` 与 `Result`](core/option_result.md)
- [`Slice` 内存切片](core/slice.md)
- [`Mem` 内存操作](core/mem.md)

### 2. 动态数据结构 (`collections`)
- [`Vec` 动态数组](collections/vec.md)
- [`HashMap` 哈希表](collections/hashmap.md)
- [`HashSet` 哈希集合](collections/hashset.md)
- [`BTreeMap` 与 `BTreeSet` 有序树](collections/btree.md)
- [`VecDeque` 双端队列](collections/vec_deque.md)
- [`BinaryHeap` 优先队列](collections/binary_heap.md)

### 3. 并发与同步 (`sync`)
- [`Mutex` 互斥锁](sync/mutex.md)
- [`RwLock` 读写锁](sync/rwlock.md)
- [`Atomic` 原子操作](sync/atomic.md)
- [`Mpsc` 多生产者单消费者通道](sync/mpsc.md)
- [`Once` 单次初始化](sync/once.md)

### 4. 字符串与格式化
- [`String` 动态字符串](string.md)
- [`Fmt` 格式化工具](fmt.md)
- [`Char` 与 `Ascii` 字符操作](char.md)

### 5. IO、网络与系统
- [`IO` 读写流](io/io.md)
- [`Fs` 文件系统](os/fs.md)
- [`Path` 路径处理](os/path.md)
- [`Env` 与 `Process` 系统环境](os/process.md)
- [`Net` 原生网络](io/net.md)
- [`Netx` 高性能事件网络](io/netx.md)
- [`Time` 时间](os/time.md)

### 6. 核心算术与比较
- [`Num` 安全算术运算](math/num.md)
- [`Cmp` 与 `Sort` 排序比较](math/cmp.md)
- [`Math` 高级数学函数](math/math.md)
- [`Hash` 散列算法](math/hash.md)