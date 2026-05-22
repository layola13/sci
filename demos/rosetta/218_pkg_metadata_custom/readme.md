# 218 - Pkg Metadata Custom

## 目标特性 (Target Feature)
展示自定义 metadata 如何在包树里对应到单独的 helpers 子目录。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **树形结构**：
   ```text
   218_pkg_metadata_custom/
   ├── sa.pkg
   ├── main.sa
   └── src/
       ├── index.sa
       └── metadata/
           ├── index.sa
           └── helpers/
               ├── metadata.sal
               └── index.sa
   ```
2. **代码组织**：`src/metadata/helpers/metadata.sal` 只放 layout 常量，包级入口再把它包装为统一值。
3. **说明**：`sa.pkg` 只是未来元数据示意，不参与当前 SA-ASM 编译。

