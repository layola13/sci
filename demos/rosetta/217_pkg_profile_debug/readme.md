# 217 - Pkg Profile Debug

## 目标特性 (Target Feature)
展示 debug profile 在包内独立 helpers 目录中的组织方式。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **树形结构**：
   ```text
   217_pkg_profile_debug/
   ├── sa.pkg
   ├── main.sa
   └── src/
       ├── index.sa
       └── profiles/
           └── debug/
               ├── index.sa
               └── helpers/
                   ├── profile.sal
                   └── index.sa
   ```
2. **代码组织**：debug 配置与 release 一样被包成单独子树，只是 helper 常量不同。
3. **说明**：`sa.pkg` 只作为未来 metadata 的文本示意。

