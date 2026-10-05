# SA 发包流程（Release Process）

本文描述从 main 分支出一个正式版本的完整步骤：构建 6 平台产物 →
GitHub 打 tag / 发 Release → npm 发 `@salang/sa`。下面 `<VER>` 一律指本次
版本号（tag 风格为裸版本号，如 `0.1.1`，无 `v` 前缀）。

## 0. 前置检查

```sh
cd sci
git status --short          # 必须干净；本地构建会改 artifacts/sa_std/libsa_std.a，
                            # 仅验证的话用 git checkout -- artifacts/sa_std/libsa_std.a 还原
git log --oneline -3
git tag --sort=-v:refname | head -5   # 确认上一个版本，定出 <VER>
zig version                 # 0.14.1（见 build.zig.zon minimum_zig_version）
```

版本号三处同改：`sci/build.zig.zon` 的 `.version`、
`sci/npm/packages/*/package.json` 的 `version`（共 7 个包），以及本次 tag 名。

## 1. 构建 6 平台产物

Linux 原生需要 LLVM 14（`sudo apt-get install -y llvm-14-dev`）：

```sh
cd sci
zig build                                            # Linux x86_64，产物 zig-out/
zig build -Dtarget=x86_64-windows-gnu -Dllvm=false -p /tmp/sa-dist/windows-x86_64
zig build -Dtarget=aarch64-linux-gnu -Dllvm=false  -p /tmp/sa-dist/arm-aarch64
zig build -Dtarget=aarch64-macos -Dllvm=false       -p /tmp/sa-dist/mac-aarch64
zig build -Dtarget=x86_64-macos -Dllvm=false        -p /tmp/sa-dist/mac-x86_64
sh tools/build_freebsd.sh --prefix /tmp/sa-dist/freebsd-x86_64   # 需 sysroot，见下
```

FreeBSD 说明：Zig 0.14.1 不自带 freebsd libc，`tools/build_freebsd.sh`
会自动下载 14.4-RELEASE `base.txz`（约 155M）做 sysroot 并生成 `-libc` 文件。
FreeBSD 主机原生替代路线：`pkg install zig` 后直接 `zig build`。

产物校验（`file` 看格式，`--version` 看可运行的那个）：

```sh
file /tmp/sa-dist/linux-x86_64/bin/sa        # ELF x86-64
file /tmp/sa-dist/arm-aarch64/bin/sa         # ELF ARM aarch64
file /tmp/sa-dist/mac-aarch64/bin/sa         # Mach-O arm64
file /tmp/sa-dist/freebsd-x86_64/bin/sa      # FreeBSD 14.4 ELF, ld-elf.so.1
ls /tmp/sa-dist/windows-x86_64/bin/sa.exe
/tmp/sa-dist/linux-x86_64/bin/sa --version
```

## 2. 最低验证门禁

```sh
cd sci
zig build core -Dllvm=false     # 跨平台核心检查（快）
zig build sa-std-unit           # 标准运行时单元测试
```

说明：`zig build test` 全量门禁在本机约 10 分钟以上；`-Dllvm=false` 下
`wasm-matrix` 与部分 `plugin-host-smoke` 会因 `LLVM-C backend is disabled`
失败，属环境限制（装好 llvm-14-dev 用默认开关重跑即过）。裸
`zig test src/runtime/sa_std.zig` 会报 posix `@bitCast` 错——那是没链 libc
走进 std 非 libc 路径所致，一律用 `zig build sa-std-unit` 代替。

## 3. 打包附件与 stage npm 二进制

```sh
# GitHub Release 附件：每平台打一个 zip（含 sa + hubproxy）
cd /tmp/sa-dist
for d in linux-x86_64 arm-aarch64 mac-aarch64 mac-x86_64 windows-x86_64 freebsd-x86_64; do
  (cd $d/bin && zip -q /tmp/sa-<VER>-$d.zip sa* hubproxy*)
done
ls /tmp/sa-<VER>-*.zip

# npm 子包二进制（二进制不进 git，约 95M；二选一）
# A. 刚构建完，在构建机上 stage：
sh sci/npm/tools/stage-binaries.sh --dist /tmp/sa-dist
# B. 在发布机（如 Windows 笔记本）上从 GitHub Release 拉取：
sh sci/npm/tools/fetch-binaries.sh --version <VER>
#   Windows PowerShell：powershell sci\npm\tools\fetch-binaries.ps1 -Version <VER>
```

## 4. Git 提交、打 tag、推送

```sh
cd sci
git add <本次文件> && git commit -m "..."
git tag -a <VER> -m "SA <VER>: <一句话说明>"
```

推送需要带写权限的 token，**不要把 token 写进命令历史或 remote URL**，
用 header 注入（shell 只展开 `$GIT_TOKEN`，日志里看不到明文）：

```sh
export GIT_TOKEN="$(cat ~/.config/sa/github_token)"   # 或由环境注入，二选一
git -c http.extraHeader="Authorization: Bearer $GIT_TOKEN" \
  push origin main <VER>
```

## 5. GitHub Release

```sh
export GH_TOKEN="$GIT_TOKEN"   # gh 认 GH_TOKEN
gh release create <VER> /tmp/sa-<VER>-*.zip \
  --repo layola13/sci \
  --title "SA <VER>" \
  --notes "<更新说明：合并内容 / 平台矩阵 / 已知限制>"
```

发完检查 Release 页附件 6 个 zip 齐全。

## 6. npm 打包发包（`@salang/sa`，esbuild 式 7 包）

### 6.1 包结构

`sci/npm/`（已进仓库；二进制不进 git，见 `npm/.gitignore`）：

| 包 | 内容 | 说明 |
|---|---|---|
| `@salang/sa` | `bin/sa.js` launcher + README + LICENSE | `bin: {sa: bin/sa.js}`，零依赖；按 `platform-arch` 查表定位平台子包后 `spawnSync` 继承 stdio，退出码穿透 |
| `@salang/sa-<os>-<arch>` ×6 | `bin/sa`（或 `sa.exe`）+ README | 带 `os`/`cpu` 字段，npm 安装时只下载命中平台的那一个 |

launcher 解析失败时给明确报错（平台不支持 / 平台包缺失），不静默吞错。
0.0.x 阶段只装 `sa` 主二进制；`hubproxy` 与插件 SDK 后续版本再加。

版本规则：`optionalDependencies` 精确 pin 同版本号（不加 `^`），7 个包同升同发。

### 6.2 二进制来源（二选一）

```sh
# A. 构建机 stage（刚编完 6 平台产物时用）
sh sci/npm/tools/stage-binaries.sh --dist /tmp/sa-dist
# B. 发布机拉取（Windows 笔记本等不重编的机器，版本号须与 Release tag 一致）
sh sci/npm/tools/fetch-binaries.sh --version <VER>
#   Windows PowerShell：powershell sci\npm\tools\fetch-binaries.ps1 -Version <VER>
```

拉取后校验：`strings` 查二进制内嵌版本（如 `0.1.2`），旧版字符串不得残留；
Linux 包可直接跑 `bin/sa --version`。注意 `sa --version` 是编译时烤进二进制的
（`latestGitTag()` 取当时 `git tag` 第一行）——打完 tag 必须重编，否则报旧版。

### 6.3 发布

顺序不能反（先 6 个平台包，再 meta 包），scope 包必须 `--access public`：

```sh
npm login   # 有 salang 组织发布权限的账号
cd sci/npm/packages
for p in sa-linux-x64 sa-linux-arm64 sa-darwin-arm64 sa-darwin-x64 \
         sa-win32-x64 sa-freebsd-x64; do
  (cd "$p" && npm publish --access public)
done
cd sa && npm publish --access public
```
或一条命令（Linux：`sh sci/npm/tools/publish-all.sh`；
Windows：`powershell sci\npm\tools\publish-all.ps1`，支持 `--dry-run` 预演）。

发完验证：`npm install -g @salang/sa && sa --version`。

### 6.4 已知坑

- 仓库根 `.gitignore` 的 `bin` / `bin/` 曾是全局匹配，会吞掉
  `npm/packages/sa/bin/sa.js` 导致 launcher 漏提交。已收窄为根目录限定
  （`/bin/`）。新增含 `bin` 目录的 npm 包结构后，务必 `git status` 确认
  launcher 在列、`npm pack --dry-run` 核对文件清单。

### 6.5 Windows 发布机注意事项

Windows 笔记本 pull 下仓库可直接发包，无需处理 Linux 权限——以下两处已兜底：

- 可执行位：zip/tar 在 Windows 解压会丢 Unix exec 位（`bin/sa` 落盘 0644）。
  launcher（`packages/sa/bin/sa.js`）在 `spawnSync` 前对二进制做
  `fs.chmodSync(binPath, 0o755)`，运行时自动恢复；`bin` 声明的 `sa.js`
  本身由 npm 在安装时强制 +x。直接执行 `.../bin/sa` 的旁路不在支持范围，
  一律走 `sa` 命令。
- 换行符：`.gitattributes` 已把 `*.sh`、workflow yml 和
  `npm/packages/sa/bin/sa.js` 钉为 `text eol=lf`。Windows 签出（autocrlf）
  也不会把 launcher 写成 CRLF——否则首行 shebang 在 Linux/macOS 上失效。
  新增发版物内的可执行脚本时，记得同步加一行。

Windows 发包流程（fetch 二进制，不重编）：

```powershell
powershell sci\npm\tools\fetch-binaries.ps1 -Version <VER>
powershell sci\npm\tools\publish-all.ps1 --dry-run   # 先预演
powershell sci\npm\tools\publish-all.ps1             # 6 平台包 + meta 包
```

mac 原生完整版（LLVM 后端）需在 mac 机上 `zig build` 后把产物放到
`/tmp/sa-dist` 对应目录再 `stage-binaries.sh`（`llvm@14` 的 dylib 会自动
捆绑）；Windows 同理（`LLVM-C.dll` 自动捆绑）。可先发 bootstrap 版，
完整版随后补。

## 7. 文档同步

- sala 新增/更新 `content/13_build/`「多平台编译」章节后跑 `python build.py`
  确认 115+ 主题构建通过；
- 本文件与 sala 章节的命令、版本号保持一致。
