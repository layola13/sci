# HashSet (哈希集合)

HashSet 的底层逻辑由 `HashMap` 复用演变而来，用于验证唯一性是否存在。

## 导入
```sa
@import "sa_std/hashset.sa"
```

## 核心宏与用法

### `HASHSET_NEW %out_set`
### `HASHSET_INSERT %set_reg, %key_ptr`
### `HASHSET_CONTAINS %out_bool, %set_reg, %key_ptr`

```sa
EXPAND HASHSET_NEW my_set

my_name = utf8:"alice"
EXPAND HASHSET_INSERT my_set, &my_name

EXPAND HASHSET_CONTAINS is_exists, my_set, &my_name
```

### `HASHSET_FREE %set_reg`