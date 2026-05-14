# 216 - Pkg Profile Release

## 目标特性 (Target Feature)
展示 release profile 在包内独立 helpers 目录中的组织方式。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **树形结构**：
   ```text
   216_pkg_profile_release/
   ├── sa.pkg
   ├── main.saasm
   └── src/
       ├── index.saasm
       └── profiles/
           └── release/
               ├── index.saasm
               └── helpers/
                   ├── profile.saasm-layout
                   └── index.saasm
   ```
2. **代码组织**：release 配置只暴露给 `src/profiles/release/helpers/`，包级入口只拿到包装后的值。
3. **说明**：`sa.pkg` 仅表示未来的包元数据，不是当前编译器输入。

