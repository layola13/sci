# 212 - Pkg Feature Flags

## 目标特性 (Target Feature)
展示 feature flags 放进包内嵌套 helpers 目录后的组织方式。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **树形结构**：
   ```text
   212_pkg_feature_flags/
   ├── sa.pkg
   ├── main.saasm
   └── src/
       ├── index.saasm
       └── flags/
           ├── index.saasm
           └── helpers/
               ├── flags.saasm-layout
               └── index.saasm
   ```
2. **代码组织**：`src/index.saasm` 只聚合 `src/flags/index.saasm`，真正的 flag 常量放在 `src/flags/helpers/flags.saasm-layout`。
3. **说明**：`sa.pkg` 仅是未来包元数据示意，不是当前编译器输入。

