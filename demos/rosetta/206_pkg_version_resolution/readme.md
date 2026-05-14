# 206 - Package Version Resolution

## 目标特性 (Target Feature)
展示 SemVer 版本决议在两个版本化子目录中的收敛过程。

## 模块化与工程化预演 (Module & Ecosystem Architecture)
1. **纯架构展示**：本目录模拟一个 resolver 选择版本的包树，`resolver/index.saasm` 只看见两个版本子目录，而 `sa.pkg` 只是未来元数据，不参与编译。
2. **树形结构**：
   ```text
   206_pkg_version_resolution/
   ├── sa.pkg
   ├── main.saasm
   ├── resolver/index.saasm
   └── versions/
       ├── v1_2_3/
       │   ├── sa.pkg
       │   ├── index.saasm
       │   └── leaf.saasm
       └── v1_4_0/
           ├── sa.pkg
           ├── index.saasm
           └── leaf.saasm
   ```
3. **运行模型**：`main.saasm` 只依赖 resolver 的公共入口，版本选择逻辑被收束到单独模块中。

