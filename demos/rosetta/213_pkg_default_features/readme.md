# 213 - Pkg Default Features

## 目标特性 (Target Feature)
展示默认特性如何通过包内 helpers 子目录集中管理。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **树形结构**：
   ```text
   213_pkg_default_features/
   ├── sa.pkg
   ├── main.saasm
   └── src/
       ├── index.saasm
       └── defaults/
           ├── index.saasm
           └── helpers/
               ├── defaults.saasm-layout
               └── index.saasm
   ```
2. **代码组织**：默认值只在 `src/defaults/helpers/` 中定义，`src/defaults/index.saasm` 再把它们包装成包级入口。
3. **说明**：`sa.pkg` 只表示未来的包元数据，不会被当前编译器读取。

