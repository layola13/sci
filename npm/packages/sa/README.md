# @salang/sa

SA (Safe ASM) toolchain for the SLA language: compiler, runtime and package manager.

## Install

```sh
npm install -g @salang/sa
sa --version
```

The installer pulls exactly one platform package via `optionalDependencies`
(esbuild-style distribution):

| Platform | Package |
|---|---|
| Linux x86_64 | `@salang/sa-linux-x64` |
| Linux ARM64 | `@salang/sa-linux-arm64` |
| macOS ARM64 | `@salang/sa-darwin-arm64` |
| macOS x86_64 | `@salang/sa-darwin-x64` |
| Windows x86_64 | `@salang/sa-win32-x64` |
| FreeBSD x86_64 | `@salang/sa-freebsd-x64` |

## 0.0.1 scope

Ships the `sa` compiler binary only (`sa --help` for subcommands).
`hubproxy` and plugin SDKs follow in later versions.

## Source & license

Built from https://github.com/layola13/sci (see `sala/` doc chapter
“多平台编译” for the per-target build matrix). Apache-2.0.
