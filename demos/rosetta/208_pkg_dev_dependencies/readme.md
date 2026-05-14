# 208 - Package Dev Dependencies

## 目标特性 (Target Feature)
展示 dev/test 辅助代码和主发布路径分离的包布局。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **主路径与开发路径分离**：`src/` 里的代码参与主入口，`dev/` 里的 helpers 和 tests 只作为开发辅助目录存在，不会被 `main.saasm` 直接引入。
2. **树形结构**：
   ```text
   208_pkg_dev_dependencies/
   ├── sa.pkg
   ├── main.saasm
   ├── src/
   │   ├── index.saasm
   │   └── helpers/
   │       ├── flags.saasm-layout
   │       └── index.saasm
   └── dev/
       ├── helpers/index.saasm
       └── tests/index.saasm
   ```
3. **说明**：`sa.pkg` 只作为未来包元数据示意，不是当前编译器输入。

