# SA Std Env 修复记录

> 相关 SA-ASM 语义说明: [`sa-asm` 技能](../.codex/skills/sa-asm/SKILL.md)

## 1. 现象

- `sa_std/env.sa` 的宏层已经存在，`tests/std_smoke.zig` 也覆盖了 flatten/iface 形态。
- 真正卡住的是 `sa_std env runtime helper is usable from C` 这一条 smoke。
- 失败表现是 C demo 进程退出码 `2`，也就是 `sa_env_has("PATH")` 没有返回 `SA_STD_OK`。

## 2. 我遇到的难题

- 这不是 SA-ASM verifier 的 join / phi 问题。
- 也不是 `sa_std/env.sa` 宏本身的问题。
- 难点在于 `sa_env_has` / `sa_env_get` 要同时满足两种编译态：
  - `zig build test` 的 test 产物
  - `zig build-lib` 产出的静态库，再由 `zig cc` 链接给 C demo

## 3. 我试过的方案

- 直接用 `std.process.hasEnvVar` / `std.process.getEnvVarOwned`。
- 改成从 `std.c.getenv` 取值。
- 改成直接读 `environ`。
- 改成 `std.os.environ`。
- 这些路径各自都在某一端失效过：
  - 有的会引入 libc 依赖，导致 `zig build-lib` 直接报错。
  - 有的在 test 产物里会碰到未定义符号。
  - 有的对 C demo 里的环境读取不稳定。

## 4. 最终实现

- `builtin.is_test` 时，`sa_env_*` 走 `std.os.environ`，这样 `zig build test` 不会额外依赖 libc。
- 非 test 时，`sa_env_*` 走 C 侧 `getenv` 符号，再复制成 owned buffer 返回。
- `sa_env_get` 返回的 buffer 继续复用现有 `EnvHandle` / `sa_env_buffer_*` 生命周期模型，调用方必须显式释放。

## 5. 验证

- `zig build test`
- `zig build-lib src/runtime/sa_std.zig -O Debug -femit-bin=libsa_std.a`
- C demo 通过 `sa_env_get` 读取 `PATH`

## 6. 结论

- 这次故障的根因不是标准库宏缺失，而是 runtime 入口需要对齐两种不同的构建上下文。
- 对 SA-ASM 的经验规则是：不要把“测试时可见”和“链接时可见”混为一层。
- 只要 C ABI 依赖外部环境，就要显式区分 test 产物和静态库/最终程序的环境读取路径。

