# HashMap (哈希映射表)

哈希表支持任意指针与 u64 作为字典的结构数据。底层基于容量倍增方案扩展，具备完整防溢出的重新散列机制保护。

## 导入
```sa
@import "sa_std/hashmap.sa"
```

## 核心宏与用法

### `HASHMAP_NEW %out_map`
初始化容器。

```sa
EXPAND HASHMAP_NEW my_map
```

### `HASHMAP_INSERT %map_reg, %key_ptr, %value`
插入数据，自动检查碰撞并执行底层 `map_rehash` 动作。

```sa
key_name = utf8:"host"
EXPAND HASHMAP_INSERT my_map, &key_name, 1024
```

### `HASHMAP_GET %out_ok, %out_value, %map_reg, %key_ptr`
安全的边界和命中检测获取方案。

```sa
EXPAND HASHMAP_GET ok, val, my_map, &key_name
br ok -> L_FOUND, L_MISS
L_FOUND:
    // 存在数据
    !val
    !ok
    jmp L_DONE
```

### `HASHMAP_REMOVE %out_ok, %map_reg, %key_ptr`
成功移除后 `ok` 会等于 `1`。

### `HASHMAP_FREE %map_reg`
释放字典内存空间。