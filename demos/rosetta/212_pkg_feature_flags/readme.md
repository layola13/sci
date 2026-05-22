# 212 - Pkg Feature Flags

## 目标特性 (Target Feature)
展示 feature flags 放进包内嵌套 helpers 目录后的组织方式。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **树形结构**：
   ```text
   212_pkg_feature_flags/
   ├── sa.pkg
   ├── main.sa
   └── src/
       ├── index.sa
       └── flags/
           ├── index.sa
           └── helpers/
               ├── flags.sal
               └── index.sa
   ```
2. **代码组织**：`src/index.sa` 只聚合 `src/flags/index.sa`，真正的 flag 常量放在 `src/flags/helpers/flags.sal`。
3. **说明**：`sa.pkg` 仅是未来包元数据示意，不是当前编译器输入。

