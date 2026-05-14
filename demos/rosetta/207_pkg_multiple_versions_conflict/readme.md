# 207 - Package Multiple Versions Conflict

## 目标特性 (Target Feature)
展示同一个包的多个不兼容版本在依赖树中引发的冲突机制。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **纯架构展示**：`resolver/index.saasm` 同时导入 `packages/v1_0_0` 与 `packages/v2_0_0`，两个版本都定义了同名 `@dep_value()`，因此编译应在符号合并阶段失败。
2. **树形结构**：
   ```text
   207_pkg_multiple_versions_conflict/
   ├── sa.pkg
   ├── main.saasm
   ├── resolver/index.saasm
   └── packages/
       ├── v1_0_0/
       │   ├── sa.pkg
       │   ├── index.saasm
       │   └── leaf.saasm
       └── v2_0_0/
           ├── sa.pkg
           ├── index.saasm
           └── leaf.saasm
   ```
3. **预期结果**：这个 demo 不应该产出可执行文件，它的价值在于展示真实的版本冲突，而不是单文件伪错误。

