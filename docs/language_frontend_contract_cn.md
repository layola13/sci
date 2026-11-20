# 语言前端编译服务契约（v1）

> 本文为英文原版 [Language Frontend Compile-Service Contract (v1)](./language_frontend_contract.md) 的中文对照版。

状态：已实现（`src/cli.zig` 中的宿主路由，`src/plugins.zig` 中的扩展注册表）。设计来源：sala `05_plugins/20_system_redesign`。

*语言前端* 是一个插件，其 `sap.json` 声明如下：

```json
{
  "kind": "language",
  "language_extensions": [".sla"]
}
```

缺少 `kind` 表示 `command`（经典插件）。未知的 `kind` 值会以 `InvalidSapManifest` 拒绝；不存在回退机制。

## 宿主保证

- 宿主加载所有已安装的插件，并注册每个语言前端的扩展。如果两个前端声明同一个扩展，先注册者胜出，宿主记录一条诊断信息；解析绝不会静默地产生歧义。
- 对于消费文件的动词——`check`、`test`、`build`、`build-exe`、`build-wasm`、`build-js`、`build-c`、`build-obj`——当位置参数的源文件扩展名已注册时，宿主会在运行自身流水线之前先经由前端路由。如果扩展名没有注册前端，宿主行为与本契约之前完全一致。
- 除上述列表外还存在两个额外的路由面（2026-11-05 新增）：`run` 也经由前端路由（`routeLanguageFrontend` 中的非终端路由），`build-lib` 经由前端的 `build` 路由进入，而在**没有**源文件的情况下调用的项目动词，当项目选择了语言前端时由 `routeProjectVerb` 路由。
- v1 中每次调用最多一个语言源文件；更多会报明确的 `SA-LANGUAGE-FRONTEND` 错误，绝不会部分编译。
- 进程环境是宿主自身的环境（特别是前端通过宿主既有渠道查找标准库——先是 `SA_STD_DIR`，然后是相对于可执行文件的布局——绝不会猜测用户特定的路径）。

## 前端义务

命令通过插件 ABI `handle_command` 传递，argv 约定为 `["sa", "<frontend-name>", <subcommand>, ...]`。

- `build <source> --out <path>`：将 `<source>` 编译为 SA 文本并写入恰好 `<path>`（路径由宿主选择；v1 使用同级的 `<name>.sa`）。成功是指退出码为 0 **且** 文件出现在 `<path>`；宿主会验证是否存在，否则以 `SA-LANGUAGE-FRONTEND` 失败。失败必须是非零退出码并在 stderr 上带诊断信息；随后宿主以该码停止，绝不会回退去自行解析源文件。
- `check <source> [args...]` / `test <source> [args...]`：宿主在前端名称之后转发用户的完整参数列表，并原样返回前端的退出码。
- 未实现某个子命令的前端返回 `unknown_command`；宿主会明确报告这一点。

## 诊断与缓存键

- 诊断信息走 stderr。SA 级陷阱已使用宿主的结构化 JSON 格式；前端原生诊断（例如 SLA 类型错误）在 v1 中是纯文本，原样透传。
- 缓存键是前端对源码及其依赖图的内容哈希（SLA 新鲜度闸门）。将该闸门提升为共享的宿主缓存服务属于重设计的第二阶段；在此之前，前端拥有自己的缓存（`.sla-cache/`），宿主只拥有中间 `.sa` 的存放位置。

## 非目标（v1）

- 没有单独的编译 ABI 入口点：鉴于目前只存在一个语言前端，上述命令约定就是契约，并且它是刻意针对 SLA 的真实行为定制的，而非投机的泛化。
- 过渡期间 `sa <frontend> *` 仍然可用；独立的前端二进制仍然是一个薄别名。

## 权限确认（所有插件种类）

确认属于宿主，而不是分发渠道。一个插件到来时如果没有配套的 `permissions.lock`（手工复制、从压缩包解压、由包管理器安装），在正式模式下会被阻断，并给出三段式诊断。补救办法是：

- `sa plugin confirm <name>` — 打印权限审查并在 TTY 上提示；批准后写入与正式安装会产生的相同的 `permissions.lock`（当前目录和版本目录）。
- `sa plugin confirm <name> --yes` — 显式的非交互形式；在写入锁之前仍然会打印审查。
- 确认与清单的权限摘要绑定：之后任何声明变更都会使其失效，必须重新确认。未声明特权权限的插件不需要确认。
