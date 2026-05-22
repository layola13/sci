# HashMap / HashSet 修复记录

> 相关 SA-ASM 语义说明: [`sa-asm` 技能](../.codex/skills/sa-asm/SKILL.md)

## 1. 现象

- `hashmap` 和 `hashset` 的原生 smoke test 在 `run` / `build-exe` 场景下崩溃。
- 表面上看像是所有权释放错误，容易误判成 verifier 或控制流合流问题。
- 实际上，问题出在标准库 helper 的 SA-ASM 签名，不在底层哈希算法本身。

## 2. 根因

- `@map_hash_ptr` 只负责读取 `key` 指针的数值并计算哈希，不应该接管 `key` 的所有权。
- 旧签名写成了 `key: ptr`，函数末尾还有 `!key`。
- 在 SA-ASM 里，这种写法会把参数当成“拥有者”语义来处理，于是 `!key` 可能被降低成真实释放，而不是单纯释放借用状态。
- `hashset` 复用 `hashmap` 的探测、插入和删除逻辑，所以这个边界错误会同时影响两个模块。

## 3. 修复

- 把 helper 签名改为 `@map_hash_ptr(&key: ptr) -> u64`。
- 所有调用点统一改成 `call @map_hash_ptr(&key)`。
- 保留函数末尾的 `!key`，但它现在只是释放借用，不再代表释放被借用对象本身。

## 4. 验证

- `zig build test --summary all`
- 结果：`208/208 tests passed`
- `hashmap` / `hashset` 的 `run` 和 `build-exe` smoke test 恢复通过。

## 5. 结论

- 这次故障不是 verifier 的 join / phi 问题，也不是哈希探针逻辑的问题。
- 真正的问题是 SA-ASM API 边界上的所有权注解错误。
- 经验规则很简单: 只读 helper 用 `&ptr`，只有真的要接管资源时才用 `ptr` / `^ptr`。

## 6. 相关文件

- [`sa_std/hashmap.sa`](sa_std/hashmap.sa)
- [`sa_std/hashset.sa`](sa_std/hashset.sa)
- [`tests/std_smoke.zig`](../tests/std_smoke.zig)
