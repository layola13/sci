# npm — `@salang/sa` npm 分发（esbuild 式 7 包）

meta 包 `@salang/sa`（launcher + `bin/sa`）配 6 个平台子包。
npm 按 `os`/`cpu` 自动只装命中平台的那一个。

```
npm/
  packages/sa/                # @salang/sa：bin/sa.js launcher + 文档
  packages/sa-linux-x64/ ...  # 各平台子包：bin/sa(.exe) + package.json + README
  tools/stage-binaries.sh     # 从本地构建产物 stage 二进制
  tools/fetch-binaries.sh / .ps1  # 从 GitHub Release 拉二进制（发布机用）
  tools/check-versions.sh     # 发包前校验：二进制内嵌版本须等于 package.json
  tools/publish-all.sh / .ps1 # 一条命令发 7 个包
```

完整打包发包说明见 `docs/release_process_cn.md` §6。
SLA 的包（`@slalang/sla`）独立放在 sa_plugin_sla 仓库的 `npm/` 下。
