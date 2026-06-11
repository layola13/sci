# BTreeMap / BTreeSet

提供自动有序树（基于 B 树实现）的存储，适合对键值进行范围查询或者需要数据持久维持顺序的场景。

## 导入
```sa
@import "sa_std/btree_map.sa"
@import "sa_std/btree_set.sa"
```

这部分提供与 HashMap / HashSet 雷同的 `BTREEMAP_INSERT` 等系列 API。底层会在节点发生拆分分裂时使用 `NUM_U64_CHECKED_*` 防止计算分配时崩溃。