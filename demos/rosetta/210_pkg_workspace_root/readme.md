# 210 - Package Workspace Root

## 目标特性 (Target Feature)
展示 workspace 根目录汇总多个 member package 的布局。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **workspace 根目录**：`main.sa` 依赖 `workspace/index.sa`，后者汇总 `workspace/members/alpha` 和 `workspace/members/beta` 两个成员包。
2. **树形结构**：
   ```text
   210_pkg_workspace_root/
   ├── sa.pkg
   ├── main.sa
   └── workspace/
       ├── index.sa
       └── members/
           ├── alpha/
           │   ├── sa.pkg
           │   ├── index.sa
           │   └── helpers/index.sa
           └── beta/
               ├── sa.pkg
               ├── index.sa
               └── helpers/index.sa
   ```
3. **说明**：根 `sa.pkg` 描述 workspace，成员包自己的 `sa.pkg` 仅是未来元数据示意。

