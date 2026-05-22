# 214 - Pkg Target Specific Deps

## 目标特性 (Target Feature)
展示目标相关依赖拆进 helpers 目录后，如何在包内分流到 native/portable 两条路径。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **树形结构**：
   ```text
   214_pkg_target_specific_deps/
   ├── sa.pkg
   ├── main.sa
   └── src/
       ├── index.sa
       └── targets/
           ├── index.sa
           └── helpers/
               ├── target.sal
               ├── index.sa
               ├── native.sa
               └── portable.sa
   ```
2. **代码组织**：`helpers/index.sa` 在运行时选择 native 或 portable helper，布局常量只放在 `target.sal`。
3. **说明**：`sa.pkg` 只示意未来 metadata；当前编译仍只看 `.sa` / `.sal`。

