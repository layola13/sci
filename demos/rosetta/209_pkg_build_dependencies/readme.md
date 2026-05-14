# 209 - Package Build Dependencies

## 目标特性 (Target Feature)
展示构建阶段生成的 SA 文件如何作为 build artifact 进入依赖图。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **构建产物入图**：`build/generated/index.saasm` 模拟构建脚本生成的源码，`src/index.saasm` 将它和常规源码一起组合起来。
2. **树形结构**：
   ```text
   209_pkg_build_dependencies/
   ├── sa.pkg
   ├── main.saasm
   ├── src/
   │   ├── index.saasm
   │   └── helpers/index.saasm
   └── build/
       └── generated/
           ├── generated.saasm-layout
           └── index.saasm
   ```
3. **说明**：`build/generated` 表示未来的生成物目录，`sa.pkg` 只是文本示意，不参与编译。

