# npm-sa — `@salang/sa` npm 分发（位于 sci 仓库 `npm/` 下）

esbuild 式二进制分发：meta 包 `@salang/sa`（launcher + `bin/sa`）配 6 个
平台子包（纯二进制），npm 按 `os`/`cpu` 自动只装命中平台的那一个。

```
npm-sa/
  packages/sa/                # @salang/sa 0.0.1：bin/sa.js launcher + 文档
  packages/sa-linux-x64/      # 各平台子包：bin/sa(.exe) + package.json + README
  packages/sa-linux-arm64/
  packages/sa-darwin-arm64/
  packages/sa-darwin-x64/
  packages/sa-win32-x64/
  packages/sa-freebsd-x64/
  tools/stage-binaries.sh     # 把 sci 构建产物拷贝进各子包 bin/
```

## 设计要点

- `optionalDependencies` 精确 pin `0.0.1`（不加 `^`），保证 7 个包同版本成套。
- 子包带 `os`/`cpu` 字段：不匹配平台的包 npm 直接跳过，不下载不报错。
- launcher（`bin/sa.js`，零依赖，Node ≥ 16）：按
  `process.platform-process.arch` 查表 → `require.resolve` 定位子包 →
  `spawnSync` 继承 stdio，退出码原样穿透。不支持的平台/子包缺失时给明确报错。
- 0.0.1 只装 `sa` 主二进制；`hubproxy` 与插件 SDK 后续版本再加。
- 二进制是构建产物：sci 升级后重跑 `sh tools/stage-binaries.sh`
  （默认从 `/tmp/sa-dist` 取各目标产物；重编见 sala「多平台编译」章节）。
  二进制不进 git（见 `.gitignore`，约 95M）。

## 在 Windows 发布机上发包（无需交叉编译）

```powershell
# 克隆后先装 Node.js 20+ 与 Zig（仅备用），然后：
cd sci\npm
powershell tools/fetch-binaries.ps1        # 从 GitHub Release 拉 6 平台二进制
npm login                                   # 有 salang 组织发布权限的账号
powershell tools/publish-all.ps1            # 依次发布 7 个包
npm install -g @salang/sa; sa --version     # 验证
```

Linux 发布机等价流程：`sh tools/fetch-binaries.sh` + `sh tools/publish-all.sh`。

## 发布（需 salang org 发布权限）

```sh
npm login   # 登录有 salang 组织发布权限的账号
cd npm-sa/packages
for p in sa-linux-x64 sa-linux-arm64 sa-darwin-arm64 sa-darwin-x64 \
         sa-win32-x64 sa-freebsd-x64; do
  (cd "$p" && npm publish --access public)   # 先发平台包
done
cd sa && npm publish --access public         # 再发 meta 包
```

scope 包默认 restricted，必须带 `--access public`。发完验证：
`npm install -g @salang/sa && sa --version`。
