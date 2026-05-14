# 215 - Pkg Patch Override

## 目标特性 (Target Feature)
展示 patch/override 通过包内嵌套 helpers 与 upstream 模块组合起来的布局。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **树形结构**：
   ```text
   215_pkg_patch_override/
   ├── sa.pkg
   ├── main.saasm
   └── src/
       ├── index.saasm
       └── patches/
           ├── index.saasm
           └── helpers/
               ├── patch.saasm-layout
               ├── index.saasm
               ├── upstream.saasm
               └── override.saasm
   ```
2. **代码组织**：`override.saasm` 先调用 upstream，再用 `patch.saasm-layout` 里的常量做本地覆盖。
3. **说明**：`sa.pkg` 只是未来元数据示意，不属于当前编译输入。

