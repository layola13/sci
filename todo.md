# 未完成 TODO

## Verifier
- [ ] 修复 `interior ptr` 回归测试
  - `verifier.test.interior pointers are consumed when their parent borrow is released`
  - `verifier.test.interior ptr PBT traps on use after releasing parent borrow`
- [ ] 再确认 `take view+offset` / `!view` 的父子 interior 释放语义，避免把子指针误判成 `memory_leak` 或 `use_after_move`

## 标准库
- [ ] `sa_std/collections/vec_deque.saasm`
- [ ] `sa_std/collections/binary_heap.saasm`
- [ ] `sa_std/collections/btree_map.saasm`
- [ ] HashMap 开放寻址恢复

## I/O
- [ ] `sa_std/io/buf_reader.saasm`
- [ ] `sa_std/io/buf_writer.saasm`
- [ ] `sa_std/path.saasm`

## 运行时 / 辅助
- [ ] `sa_std/env.saasm`
- [ ] `sa_std/math.saasm`
- [ ] `sa_std/string_format.saasm`
- [ ] `sa_std/sa.pkg`
