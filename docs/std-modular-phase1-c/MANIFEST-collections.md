# 模块边界清单 — collections 域

## 公共模块

| 模块（规范路径） | 内容 | 行数 | 公共入口 |
|---|---|---|---|
| `collections/vec/vec.sa` | `VEC_*` 宏 facade（759 个宏），调 `alloc/vec.sa` 的 `sa_vec_*` 运行时 | 5784 | `collections/prelude.sa`、`sa_std/prelude.sa` |
| `collections/vec/vec.sal` | `Vec_data = +0`（1 条布局常量） | 1 | 同胞自动注入（随 `vec.sa`） |
| `collections/vec/vec_grow.sla` | 几何增长 facade + scratch rewind（SLA） | 86 | 直接导入 |
| `collections/vec/vec_packed.sla` | packed 导出辅助（SLA） | 282 | 直接导入（`vec_grow.sla` 引用） |
| `collections/vec/vec_runtime_macros.sa` | `ITER_VEC_*` 宏 | 11 | `core/iter.sa`（经 shim，待 core 域规范化） |
| `collections/hashmap/hashmap.sa` | HashMap 实现 | 2736 | prelude |
| `collections/hashmap/hashmap.sal` | HashMap/HashMapSlot 布局常量 | 20 | 同胞自动注入 |
| `collections/hashset/hashset.sa` | HashSet 实现（包 HashMap） | 1059 | prelude |
| `collections/hashset/hashset.sal` | HashSet 布局常量 | 18 | 同胞自动注入 |
| `collections/btree/btree_map.sa` | BTreeMap 实现 | 2320 | prelude |
| `collections/btree/btree_map.sal` | BTreeMap 布局常量 | 11 | 同胞自动注入 |
| `collections/btree/btree_set.sa` | BTreeSet 实现（包 BTreeMap） | 1072 | prelude |
| `collections/btree/btree_set.sal` | BTreeSet 布局常量 | 6 | 同胞自动注入 |
| `collections/heap/binary_heap.sa` | BinaryHeap 实现 | 3004 | prelude |
| `collections/heap/binary_heap.sal` | BinaryHeap 布局常量 | 7 | 同胞自动注入 |
| `collections/deque/vec_deque.sa` | VecDeque 实现 | 4925 | prelude |
| `collections/deque/vec_deque.sal` | VecDeque 布局常量 | 8 | 同胞自动注入 |
| `collections/growvec/growvec.sa` | `GROWVEC_*` 宏 facade | 325 | 直接导入（**未入 prelude**，见 DEF-17） |
| `collections/growvec/growvec.sai` | `sa_growvec_*` extern 声明 | 15 | 同胞自动注入 |
| `collections/linked_list.sa` | LinkedList<u64> facade | 1146 | prelude（平铺，未建子目录，见 REPORT §2.2） |
| `collections/linked_list.sal` | LinkedList 布局常量 | 10 | 同胞自动注入 |
| `collections/collections.sal` | `TryReserveError` 布局常量 | 13 | `collections/prelude.sal` |

聚合入口：`collections/prelude.sa`（7 个模块：heap、btree×2、hashmap、hashset、linked_list、deque；growvec 不在内）、`collections/prelude.sal`（→ `collections.sal`）。

## 职责

- 提供值语义容器：`Vec`（`VEC_*` 宏 + `sa_vec_*` 运行时）、`HashMap`、`HashSet`、`BTreeMap`、`BTreeSet`、`BinaryHeap`、`VecDeque`、`LinkedList<u64>`、`GrowVec`（只增不搬的 mmap 预留缓冲）。
- 不含 I/O、不含网络、不含持久化、不含序列化（序列化属 encoding 域）。

## 允许的依赖方向

- ✅ `core/*`：`core/slice.*`、`core/mem.sa`、`core/iter.sa`（及各 `.sal`）。
- ✅ `alloc/*`：`alloc/vec.sa`、`alloc/vec.sal`、`alloc/growvec.sa`、`alloc/growvec.sal`、`alloc/layout.sal`——分配运行时层，collections 与 string 共用。
- ✅ `num.sa`：数值原语（实测 7 处引用；名义上在 core 外，承认为事实上的允许方向，见 DEF-03）。
- ✅ 顶层 `hash.sa`：哈希器实现（`BUILD_HASHER_DEFAULT_*`），归属待 Phase 2 定（DEF-09）。
- ✅ 域内互引：`hashset → hashmap`、`btree_set → btree_map`、各模块 → `vec`。
- ❌ 禁止：`io`、`net`、`db`、`http`、`fs`、`ffi`（实现代码）、`text`、`encoding`、`string`（`string.sa` 不得被 collections 引用）。
- ⚠️ 已知例外（登记未修）：`core/hash.sa` 反向依赖 `../hashmap.sa`（DEF-01）；`core/iter.sa` 依赖 `vec_runtime_macros.sa`（DEF-04）。

## 与 alloc/ 的分工

- `alloc/` = 分配运行时（`sa_vec_*`、`sa_growvec_*`、`AllocLayout`）：无宏 facade 层之外的公共容器语义。
- `collections/` = 容器语义层（宏 facade + 容器实现）：不直接 `mmap`/`alloc` 裸内存（除经由 `alloc/` 运行时与 `core/mem.sa`）。
- `string.sal` 与 `collections.sal` 引用 `alloc/*.sal` 是被允许的布局层依赖。
