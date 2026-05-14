# 211 - Pkg Workspace Inheritance

## 目标特性 (Target Feature)
展示成员包如何继承 workspace 的共享配置目录。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **共享配置**：`workspace/shared/` 作为共享配置目录，成员包的 helpers 会导入其 layout 常量和公共入口。
2. **树形结构**：
   ```text
   211_pkg_workspace_inheritance/
   ├── sa.pkg
   ├── main.saasm
   └── workspace/
       ├── index.saasm
       ├── shared/
       │   ├── sa.pkg
       │   ├── config.saasm-layout
       │   └── index.saasm
       └── members/
           ├── app/
           │   ├── sa.pkg
           │   ├── index.saasm
           │   └── helpers/
           │       ├── app.saasm-layout
           │       └── index.saasm
           └── tool/
               ├── sa.pkg
               ├── index.saasm
               └── helpers/
                   ├── index.saasm
                   └── tool.saasm-layout
   ```
3. **说明**：共享目录里的 `sa.pkg` 和 layout 文件都是未来包系统的元数据示意，不是编译器输入。
