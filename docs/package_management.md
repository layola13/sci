# SA 零信任包管理设计（Zero-Trust Package Management）

> 本文档归纳 talk.md 第 2955 行起 14 轮架构讨论，定义 SA（Symbolic Affine）从工程管理、防投毒、权限隔离到 CI/CD 流水线的完整闭环。
>
> 设计哲学：**绝对的确定性、去中心化、零隐式状态、模块级零权限默认、机器码级溯源、人肉摩擦换审计强度**。
>
> 与 R31（`sa.pkg` 包管理）、R31a–R31g（零信任扩展，本文档定义）配套使用。

---

## 0. TL;DR — 一图看懂全貌

```
┌──────────────────────────────────────────────────────────────────┐
│  SA 包管理的物理边界                                              │
└──────────────────────────────────────────────────────────────────┘

  开发者本地                                    CI / GitHub Actions
  ─────────                                    ──────────────────
  ① sa fetch <url>                              ⑥ sa build --ci
     │  HTTP/Git 哑拉取（无 postinstall）           │
     │  ↓                                          │  自动探测 isatty=false
     │  ② AST X 光扫描                              │  ↓
     │  ↓                                          │  ⑦ 双轨核验
     │  ③ 安全报告 + 信用分                         │     - 源码 SHA == sa.lock
     │  ↓                                          │     - 权限契约 == sa.mod
  ④ 默认零权限落盘 → sa_vendor/                     │  ↓
     │                                             │  ⑧ TTY → 本地强制确权
  ⑤ 触发越权？                                      │     非 TTY → 染色 / 熔断
     ├─ 是 → 强制人肉敲完整 URL（无状态、不写盘）     │
     │       生成机器码哈希钉入 sa.lock              │
     │                                             │
     └─ 否 → 直接编译                              ⑨ 全平台打包发布
                                                      （Linux/Win/Mac/WASM）
  ─────────────────────────────────────────────────────────────────
  全流程：URL 即身份 / 哈希锁死 / 默认零权限 / 源码透明 / 上下文绑定信任
```

四道架构防火墙 + 一道人肉摩擦闸门：

1. **去中心化命名**（URL = 身份）
2. **哈希锁死**（SHA-256 在 `sa.mod`）
3. **零权限默认**（`grants` 显式声明）
4. **源码透明**（拒绝预编译二进制）
5. **破窗确权**（高危包必须人肉敲完整 URL，无状态）

---

## 1. 工程管理基础（吸收 Go 的极简思想）

### 1.1 弃绝传统中心化包管理

SA **不建造** crates.io / npm registry / PyPI 这类中心化仓库。理由：

| 传统模式的原罪 | SA 的破解 |
|---|---|
| 中心化注册需运营、抢注、托管 | URL 即命名空间，由 Git host（GitHub / GitLab / 内网 Git）天然托管 |
| SemVer Resolution → SAT 求解器 → 依赖地狱 | 强制绝对哈希钉版，零依赖推导 |
| `package.json` 嵌套黑洞 + `node_modules` 几百 MB | 极简 `sa.mod` 单文件清单 + 全局或局部纯文本目录 |
| `postinstall` 隐式执行 → 投毒温床 | `sa fetch` 是图灵不完备的"哑下载器"，无生命周期钩子 |

### 1.2 命名空间即物理坐标（URL as Namespace）

源码层直接锚定互联网或内网的物理坐标：

```sa
// 在 SA 代码顶部声明依赖（语义同 @import）
@import "github.com/xiaoming/sa-ecs"
@import "gitlab.corp.local/team/sa-net"
```

**架构收益**：
- 完全去中心化：GitHub / GitLab / Bitbucket / 内网 Git 都是合法包源
- 消灭名称抢注（typosquatting）：黑客必须先黑进对应 Git 组织账号
- 没有中间商赚差价：SA 编译器内部只需调用 `git clone` 或 `curl`

---

## 2. `sa.mod` — 极简物理依赖清单

### 2.1 文件格式（扁平、单文件）

`sa.mod` **不是** `Cargo.toml` / `package.json` 的嵌套结构，是逐行声明的纯文本：

```
// sa.mod —— 极简依赖清单
require github.com/xiaoming/sa-ecs  @v1.2.0  sha256:8f4e2d...
require github.com/org/sa-net       @main    sha256:c3a1b9...  grants [net_tx, net_rx]
require gitlab.corp.local/team/util @v0.3.1  sha256:abc123...
```

每条 `require` 语句的物理字段：

| 字段 | 含义 |
|---|---|
| URL | 命名空间 / 包源 |
| `@<ref>` | Git tag / branch / commit SHA |
| `sha256:...` | **源码** SHA-256 哈希（平台无关） |
| `grants [...]`（可选） | **显式权限声明**，缺省 = 零权限 |

### 2.2 编译期的"瞬时熔断"

当编译器读取 `sa.mod`：

1. 去对应 URL 拉取源码（HTTP/Git）
2. 计算源码 SHA-256
3. **逐比特对比**：差一个比特 → 立刻 `Fatal Error`，绝不重新解析或推导

**绝不复用 SemVer Resolution**：SA 编译器**根本不算依赖兼容树**，要么哈希一致放行，要么熔断。

---

## 3. 默认局部 + 可选全局（Local-first, Global-optional）

### 3.1 默认形态：物理级"绝对便携"（Local Vendoring）

```bash
sa fetch                    # 默认拉取到 ./sa_vendor/
```

**物理表现**：
- 所有依赖落到当前项目 `sa_vendor/github.com/...` 显式目录
- 项目变成"自包含的物理孤岛"——拷进 U 盘、断网编译都没问题
- 无任何隐式外部环境变量依赖，所见即所得

### 3.2 战术超载：`-g` 全局复用

```bash
sa fetch -g                 # 拉取到 ~/.sa/pkg/
```

仅当开发者明确知道在做什么（如本地同时跑 50 个微服务、共用底层库），才启用。

### 3.3 import 解析查表短路

编译器解析 `@import` 时按以下顺序探测（**不依赖任何全局配置文件**）：

```
1. 项目级 ./sa_vendor/<URL>/
2. 全局缓存 ~/.sa/pkg/<URL>/        （仅当 sa fetch -g 拉过）
3. 找不到 → Fatal Error: PackageNotResolved
```

**关键点**：开发者使用局部还是全局是**个人 CLI 习惯**，**不写进** 共享的 `sa.mod`。这保证 A 用全局缓存、B 用局部隔离时，他们提交到 Git 的代码与配置一致。

### 3.4 全局缓存的形式

`~/.sa/pkg/github.com/xiaoming/sa-ecs@v1.2.0/` 以**只读**形式解压。编译期通过 `mmap` 内存映射读取，100 个项目依赖同一个库，磁盘上也只有一份只读源码。

---

## 4. 零预编译 + 全源码编译（Source-Only Transparency）

### 4.1 拒绝二进制黑盒

SA 包管理**绝对不允许**分发：
- 编译后的静态库（`.a` / `.lib`）
- 动态库（`.so` / `.dll` / `.dylib`）
- 平台特定的 wheels / `.node` 模块

**只分发**纯文本 `.sa` 源码。

### 4.2 全程序源码编译（Whole-Program Compilation）

由于 Zig 编译器具备 32 核心瞬时并行能力，每次构建：
1. 从局部或全局缓存拉所有依赖源码
2. 与主项目一起进行**单次全源码编译**
3. 启用 AOT 跨模块死代码消除（Dead Code Elimination）

**收益**：黑客无法在二进制黑盒里藏后门，源码层一览无余。

---

## 5. 防投毒四道防火墙

### 5.1 防火墙 1：彻底斩断 `postinstall` —— 零执行的"哑拉取"

| npm 的死穴 | SA 的物理熔断 |
|---|---|
| `npm install` 自动执行 `postinstall` | `sa fetch` 是绝对图灵不完备的哑巴操作 |
| `pre/post` 系列钩子 | SA 生态系统**没有任何**生命周期钩子（Hooks） |

源码即静态文本，黑客即使把代码改成花，只要不主动塞进编译/运行管线，它就毫无杀伤力。

### 5.2 防火墙 2：绝对哈希锁死 —— 消灭隐式更新

| npm 的死穴 | SA 的物理熔断 |
|---|---|
| `^1.2.0` 范围 → 自动拉取 1.2.1（毒包） | 源码 SHA-256 死锁 |
| 黑客覆盖 v1.2.0 tag | 任何源码字节变化 → 哈希不匹配 → Fatal Error |

### 5.3 防火墙 3：URL 即身份 —— 瓦解抢注

黑客必须先攻破对应的 GitHub 组织账号。**门槛拉高几个数量级**。

### 5.4 防火墙 4：源码级透明

所有第三方包必须是纯文本 SA 源码，本地白盒编译。任何调用 `@sys_net_rx` 的企图在源码层都裸奔可见。

### 5.5 传递依赖锁定（`sa.sum`）

为防止"A 依赖 B，B 依赖 C"的传递投毒，SA 引入扁平的全树哈希记录：

```
// sa.sum —— 整棵依赖树的哈希拍平
github.com/xiaoming/sa-ecs   @v1.2.0   sha256:8f4e2d...
github.com/org/sa-net        @main     sha256:c3a1b9...
github.com/transitive/dep    @v0.1.0   sha256:ddee01...   // 间接依赖
```

任何子树包的源码变化 → 顶层 `sa.sum` 哈希不匹配 → 整棵树物理熔断。

---

## 6. 模块级零权限沙箱（Module-Level Capability Sandbox）

### 6.1 设计理念：从"进程级沙箱"降维到"模块级微沙箱"

Deno 的 `--allow-net` 是**进程级**的——一旦给了，所有第三方包都顺带获得网络权。SA 反其道而行：

> **每个被拉取的包，默认拥有"绝对零权限"（Zero-Permission by Default）**。即使主程序拥有全通网络/IO 权，被拉取的依赖在系统里依然是"全盲"——只能做纯数学计算。

### 6.2 显式能力声明（`grants`）

```
// sa.mod
require github.com/xiaoming/sa-ecs  @v1.2.0  sha256:8f4e2d...
                                                         # 默认 = grants []，零权限
require github.com/org/sa-net       @main    sha256:c3a1b9...  grants [net_tx, net_rx]
                                                         # 显式声明，才解锁 @sys_net_*
```

### 6.3 编译期"命名空间隔离"

Zig 编译器在多线程扫描 AST 时：
1. 通过源码物理路径反推所属包（如 `sa_vendor/github.com/org/foo/`）
2. 扫到任意 `@sys_*` 原语调用 → 立刻查 `sa.mod` 的 `grants` 列表
3. 列表为空或不含该原语 → **Permission Denied**，连机器码都不生成

### 6.4 权限不可传递（Non-transitive Primitives）

防止隐式权限提升：包 A（零权限）依赖包 B（有 `net_tx` 权限），A **绝对不能**通过调用 B 的公开方法间接联网。

转译器在控制流分析阶段强制对调用栈做边界隔离：零权限模块如果把敏感指针/控制流偷渡给高权限模块 → 直接判定为**非法调用**。

### 6.5 商业杀伤力

企业引入第三方包，安全团队不再需要扫几万行源码，**只需打开 `sa.mod` 看一眼 `grants`**：
- `grants` 为空 → "这是纯算力库，闭眼放行"
- `grants [net_tx]` → "这个包能联网，必须人肉审计 X 光扫描报告"

第三方代码被**物理超度**为最纯粹的 CPU 预热器。

---

## 7. `sa fetch` —— 出厂自带 X 光扫描

### 7.1 物理运转：拉取即审计

```bash
sa fetch github.com/org/image-parser
```

Zig 编译器的 32 核心 AST 解析器在拉取完成的几毫秒内：
1. 把源码解剖成 AST
2. 在整棵树里**搜剿**所有 `@sys_*` 原语调用
3. 直接在终端打印冰冷的"能力企图与安全评估报告"

### 7.2 信用分算法（Zero-Trust Scoring）

| 安全分 | 等级 | 触发条件 |
|---|---|---|
| **100** | 绝对安全 / Pure Compute | 无任何 `@sys_*` 调用 |
| **80** | 内存分配 | 包含 `@sys_mem_slice` |
| **50** | 本地 IO | 包含 `@sys_io_read` 或 `@sys_io_write` |
| **20 及以下** | 极度危险区 | 包含 `@sys_net_tx` / `@sys_net_rx` / 跨核心绑定 |

### 7.3 终端报告样式

```
[SA-SECURE] Fetching github.com/org/image-parser @v1.2.0 ... Done (12ms)

>> SECURITY AUDIT REPORT (image-parser)
------------------------------------------------------------
[X-Ray Scan] Found 3 capability requests in AST:
  ! @sys_mem_slice  (Used in src/decoder.sa:45)
  ! @sys_io_read    (Used in src/loader.sa:12)
  ! @sys_net_tx     (Used in src/telemetry.sa:8) -> [CRITICAL WARNING]

[Evaluation] 
  Trust Score: 15 / 100 (HIGH RISK - Network exfiltration possible)

[Status] 
  Package isolated in sa_vendor/. Zero permissions granted.
  If you trust this package, manually add to sa.mod:
  require github.com/org/image-parser @v1.2.0 \
      sha256:... grants [mem_slice, io_read, net_tx]
------------------------------------------------------------
```

### 7.4 架构威慑力

报告会**直接撕下**所有开源包的伪装：开发者只想下个本地图片解析库，结果发现里面藏着 `@sys_net_tx`（遥测代码）。这种"被点名"的视觉冲击力，会推动开发者主动 fork 净化或更换依赖。

---

## 8. 破窗确权 —— 强制人肉审判台

### 8.1 核心原则：不剥夺自由，但极限提高忽略成本

SA **绝不**为了安全偷偷删源码（剥夺开发者的数字主权），但通过**摩擦即安全（Security via Friction）**机制，让"忽略风险"的代价大到可怕。

### 8.2 状态：`BLOCKED_RISK`（仅存在于内存）

当 `sa fetch` 扫描到极低分包：
- 源码**照常**落盘到 `sa_vendor/`
- 编译器**绝不**把豁免状态写进任何文件（`sa.mod` / `sa.lock` / 全局 / 项目级配置）
- 在**当前进程内存**中标记为 `BLOCKED_RISK`

### 8.3 编译期熔断与审判台

```
======================================================================
[SA-CRITICAL WARNING] RISK ACKNOWLEDGMENT REQUIRED
======================================================================
The dependency tree contains a HIGH-RISK package that violates safety bounds.
Package: github.com/hacker/bad-lib
Risk   : Requesting ungranted [@sys_net_tx] primitive (Potential Exfiltration)
Score  : 12 / 100

该组件在源码中企图解锁以下系统原语（权限列表）:
  x  @sys_net_tx    (发送网络数据包) -> src/telemetry.sa:14
  x  @sys_io_write  (修改宿主机文件) -> src/payload.sa:89

SA has paused the compilation pipeline to protect your environment.
If you deliberately choose to ignore this risk and force execution, 
you must manually confirm your intent.

[PROMPT] Please type the FULL repository name to bypass this restriction:
> _
```

### 8.4 校验规则（极致摩擦）

| 规则 | 物理实现 |
|---|---|
| 不接受 y/n 简写 | 必须完整输入 `github.com/hacker/bad-lib` 字符串 |
| 阻断脚本绕过 | `std.os.isatty` 探测 stdin，非 TTY → Fatal Error 退出 |
| 输入错误立即死 | 字符串不完全匹配 → 进程退出，不留任何编译残渣 |
| `Ctrl+C` 中断 | 进程当场物理死亡 |
| **每次都要重新输入** | 豁免**只活在当前进程内存**，进程退出 → 状态消失 |

### 8.5 为什么不允许写入 `sa.mod`？

允许写入 = 给系统留了一个"合法的后门"，会通过 Git 横向传播：

```
  开发者 A 本地敲下确认 → 写入 sa.mod
       ↓
  push 到 GitHub
       ↓
  开发者 B、CI/CD 拉代码 → 自动继承高危豁免
       ↓
  毒包在生产环境无声运行
```

**SA 的解法**：风险只属于**当前终端、此时此刻、那一个人**。豁免无法被序列化、无法被写入硬盘、无法通过 Git 传播。任何其他人/机器想跑这段代码，都必须**自己**面对一次审判。

---

## 9. 指令级哈希钉版（Instruction-Level Hash Pinning）

### 9.1 信任锚点：从"易变源码"转移到"机器码物理指纹"

当开发者完成审判台确认后：
1. Zig 编译器把这个包**单独**送入编译管线
2. 降维成底层 SA-ASM 机器码 / WASM 二进制块
3. 对生成的机器码计算 SHA-256
4. **写入项目本地** `sa.lock`：

```
// sa.lock —— 项目本地的物理执行契约
dependency "github.com/hacker/bad-lib" {
    version: "v1.2.0"
    source_sha:                "8f4e2d..."   // 源码哈希
    approved_machine_code_hash: "a1b2c3..."  // 机器码哈希（开发者确权过的）
}
```

### 9.2 防变异：无视源码层障眼法

| 黑客手段 | SA 的物理熔断 |
|---|---|
| 添加几行隐蔽的 `@sys_net_tx` | 机器码序列变化 → 哈希不匹配 → 重弹审判台 |
| 用复杂宏混淆恶意逻辑 | 宏展开后机器码必然变化 → 熔断 |
| 改变执行逻辑但保持源码字节相似 | 即使源码 SHA 偶然碰撞，机器码 SHA 也会变 → 熔断 |

### 9.3 增量编译红利

机器码已被人工确认 → 直接缓存为本地二进制 → 下次主项目编译时**无需**重新走 AST 解析，直接链接。**逼近物理极限的增量速度**。

---

## 10. 上下文绑定信任 —— 禁止跨项目复用

### 10.1 核心原则：禁止全局缓存机器码

> 同一段机器码，在不同项目里的危险程度完全不同。

| 场景 | 风险评估 |
|---|---|
| 爬虫项目引入网络库 → `@sys_net_tx` 合理 | 可放行 |
| 加密钱包项目引入**同一个**网络库 | 物理防线被无声击穿（信任污染） |

### 10.2 物理落地：项目级孤岛

| 状态 | 必须保存在 |
|---|---|
| `approved_machine_code_hash` | **当前项目根**的 `sa.lock`（绝不全局） |
| 已确权的 `.samx` 机器码缓存 | **当前项目** `.sa_cache/` 或 `sa_vendor/` 内部 |
| 临时审判通过的内存标记 | **当前进程内存**（进程退出即消失） |

哪怕两个项目在同一个父目录、同一硬盘，只要分属不同主项目，开发者必须**各自**面对审判，**各自**输入 URL，**各自**生成物理隔离的机器码。

### 10.3 物理气隙（Air-Gap）

机器上跑 100 个 SA 项目 → 它们之间的依赖状态、权限许可、机器码缓存**老死不相往来**。

---

## 11. CI/CD 流水线集成（GitHub Actions）

### 11.1 痛点：CI 没有 TTY，无法人肉确权

GitHub Actions 是**完全非交互**的，编译器如果死等输入 → 流水线超时爆红。

### 11.2 双轨制（Dual-Track）执行

#### 轨迹 A：本地终端开发（TTY 激活）
- 强制阻塞 → 必须完整输入 URL → 通过则继续
- 内存即生即灭

#### 轨迹 B：CI 模式（非 TTY，自动探测）
SA 编译器探测以下信号自动切 CI 模式：
- 环境变量 `CI=true` / `GITHUB_ACTIONS=true`
- `std.os.isatty(stdin) == false`
- 显式 flag `sa build --ci`

CI 模式有两种策略（可由参数选择）：

##### 选项 A1：冷酷熔断制（默认 Fail-Safe）
- 发现未审计的高危依赖 → 打印权限列表 → 退出码 1 → 流水线爆红
- 黑客 PR 第一秒被拒
- 正常开发者必须显式加 `sa build --allow-unaudited-risks` 才能让 CI 通过

##### 选项 A2：染色放行制（Tainted Pass）
- 不卡死流水线，照常输出二进制 / WASM
- 但产物的元数据段被注入 `TAINTED_UNAUDITED_CODE` 标记
- 编译日志疯狂输出 ASCII 警告 Banner
- GitHub Actions 的 `$GITHUB_STEP_SUMMARY` 自动钉一张"高风险资产看板"

### 11.3 双轨哈希审计管线（Dual-Track Hash Audit）

CI 模式的核心：**不依赖人工签名，靠源码 SHA 与权限的强绑定**。

#### 物理流程

```
  GitHub Actions 启动
       ↓
  ① 拉取代码 + sa_vendor/
       ↓
  ② 编译器 32 核心扫描所有依赖 AST
       ↓
  ③ 发现某依赖 X 调用 @sys_net_tx
       ↓
  ④ 双轨核验
       ├─ 第一轨：X 在 sa.mod 中 grants 是否含 net_tx？
       │           否 → Trap: UnauthorizedPrimitive，熔断
       │           是 → 进入第二轨
       │
       └─ 第二轨：当前 X 源码的 SHA == sa.mod 里的 sha256:...？
                   否 → Trap: UpstreamShaMismatch，熔断
                   是 → 放行
       ↓
  ⑤ 全平台并行编译（Linux/Windows/macOS/WASM）
       ↓
  ⑥ 输出干净二进制
```

#### 黑客攻击路径的物理破解

| 攻击 | 防御 |
|---|---|
| 伪造 `sa.lock`，哈希对得上 | CI 不信本地哈希，直接重算源码 SHA |
| 修改 `sa_vendor/` 注入恶意网络代码 | 源码 SHA 变化 → 与 `sa.mod` 锁定不符 → 熔断 |
| 在零权限包里偷加 `@sys_net_tx` | 编译器扫到 token 直接报 `UnauthorizedPrimitive` |
| 提交伪造的 `grants` | PR Diff 中赫然出现，由 Code Review 拦截 |

### 11.4 GitHub Actions 警告 Banner（未审计自动构建）

```
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
[SA-SECURITY WARNING] UNAUDITED COMPILATION IN PROGRESS
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Package 'github.com/hacker/bad-lib' contains network primitives [@sys_net_tx]
but has NO human audit record in sa.mod.

Capability list requested by this package:
  - @sys_net_tx     (NETWORK SEND)
  - @sys_io_write   (FILE WRITE)

>> THIS BUILD IS IN A 'TAINTED' STATE.
>> DO NOT DEPLOY THIS ARTIFACT TO PRODUCTION ENVIRONMENT.
>> Run `sa audit github.com/hacker/bad-lib` locally to clear this warning.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
```

### 11.5 运行时染色（Artifact Tainting）

未审计依赖被链入最终产物时：
- 在可执行文件 / WASM 的元数据段写入 `TAINTED_UNAUDITED_CODE` 标记
- Referee runtime 探测到标记 → `main()` 第一行前 → **stderr 强行打印三行红字警告**
- 警告无法被 `--release` 移除，是物理染色

---

## 12. 单机开发者的全平台编译

### 12.1 痛点

军工/金融场景常要求开发者本地生成 Linux/Windows/macOS 全平台机器码哈希并签名。但同一份源码在三个平台编译出的机器码不同，开发者手里通常只有一台 Mac 或 Windows。

### 12.2 解法 1：信任锚点降维到平台无关的源码 SHA

`sa.mod` / `sa.lock` 里**不锁机器码**，锁**源码哈希**：

```
require github.com/org/sa-net @v1.2.0 sha256:8f4e2d... grants [net_tx]
```

源码是纯文本、平台无关。三个平台的 CI Runner **各自**算源码 SHA，与 `sa.mod` 比对一致即放行。**开发者审的是逻辑，CI 负责翻译，两者在源码 SHA 处完美交接**。

### 12.3 解法 2：Zig 全平台交叉编译挂

开高密级场景下，加上：

```bash
sa build --all-targets --lock-only
```

Zig 编译器在轻薄笔记本上几秒内推导出：
- `x86_64-linux-musl`
- `x86_64-windows-gnu`
- `aarch64-macos`
- `wasm32-wasi`

把三个平台机器码哈希同时写入 `sa.lock`。无需虚拟机，无需多台机器。

---

## 13. 内网 / 断网企业（Air-Gapped Environment）

### 13.1 痛点

军工 / 金融 / 国密企业的 CI/CD 服务器是**物理拔网线**的。SA 编译器如果硬编码连 GitHub 验 SHA，根本进不了大门。

### 13.2 解法 1：全源码入库（Vendor Committal）

```bash
# 在桥接机（有外网）
sa fetch                       # 拉到 ./sa_vendor/

# 把 sa_vendor/ + sa.mod + sa.lock 全部提交到内网私有 Git
git add sa_vendor sa.mod sa.lock
git commit -m "vendor deps for offline build"
```

**SA 的物理优势**：所有依赖都是极简纯文本，提交到 Git 无压力（对比 `node_modules` 几 GB 的二进制黑洞）。

### 13.3 内网 CI 离线编译

```bash
sa build --offline
```

编译器**完全切断**网络模块，直接读硬盘 `sa_vendor/`，算哈希，与 `sa.lock` 物理比对。**全程零外网请求，安全强度丝毫未减**。

### 13.4 解法 2：URL 镜像劫持（Path Hijacking）

企业内网搭私有镜像（如 `gitlab.corp.local`）。但**严禁**改源码里的 `import` 语句（开源时会全报错）。

#### 13.4.1 严禁全局配置文件（Zero Hidden State）

> ❌ 禁止 `~/.sa/mirror.toml`
> 
> 全局配置 = 隐式宿主机状态污染。"在我机器上能跑" = 部署到 CI 时崩溃。

#### 13.4.2 唯一允许的两条路径

##### A. 进程级环境变量（CI/Docker 一等公民）

```dockerfile
# Dockerfile / Kubernetes / GitHub Actions
ENV SA_MIRROR_GITHUB_COM=gitlab.corp.local/mirror
ENV SA_MIRROR_GITLAB_COM=gitlab.corp.local/proxy
```

编译器调用 `std.os.getenv()` 探测 `SA_MIRROR_<HOST_UPPER>`。容器销毁 → 规则灰飞烟灭，硬盘无任何垃圾。

##### B. 项目本地配置（自包含）

```
# 项目根目录 / .sa_env 或 sa.mod 的 [mirrors] 块
[mirrors]
github.com = gitlab.corp.local/mirror
```

10 个项目可拥有 10 套互不干扰的镜像规则。

### 13.5 编译器的运行上下文（绝对纯洁）

```
执行结果 = 源码 AST + 局部 sa.mod + 局部 sa.lock + 进程环境变量
```

除此之外，编译器对宿主机系统**一无所求、一无所知**。这就是**真正的绿色软件**与**零信任编译**。

---

## 14. CLI 命令集

### 14.1 核心命令（极简 Unix 风格）

```bash
sa run main.sa                 # 隐式构建并执行（内存解释器）
sa build [-o out]                 # 生成原生二进制 / WASM
sa build --ci                     # CI 模式（非交互、可选熔断/染色）
sa build --offline                # 断网模式（完全切断网络）
sa build --all-targets            # 全平台交叉编译
sa build --release-fast           # LLVM O3（默认 O1）

sa fetch [URL]                    # 拉到局部 ./sa_vendor/
sa fetch -g [URL]                 # 拉到全局 ~/.sa/pkg/
sa fetch --offline                # 仅校验现有 sa_vendor/，不联网

sa audit [URL]                    # 重新跑 X 光扫描 + 生成报告
sa audit --update-lock            # 把当前机器码 hash 写入 sa.lock
```

### 14.2 子命令的语义不变性

| 命令 | 失败时是否修改文件 |
|---|---|
| `sa fetch` | 仅落盘源码到 `sa_vendor/`，**绝不**修改 `sa.mod` / `sa.lock` |
| `sa build` 触发审判台 | **绝不**写盘，仅内存豁免 |
| `sa audit --update-lock` | **唯一**允许写 `sa.lock` 的命令；显式动作 |
| `sa run` | 与 `sa build` 行为完全一致，只是不输出文件 |

---

## 15. 完整的工程闭环（架构总结）

### 15.1 SA 生态管理哲学

| 原则 | 含义 |
|---|---|
| **URL 即命名空间** | 去中心化，消灭抢注 |
| **绝对哈希钉版** | 零依赖推导，零 SAT 求解 |
| **默认零权限** | 包拉下来就是哑巴 |
| **出厂 X 光机** | 拉取瞬间扫描 AST，亮出冰冷信用分 |
| **破窗确权，每次必输** | 不剥夺自由，但通过零状态摩擦让侥幸付出代价 |
| **指令级哈希钉版** | 信任锚点是机器码，不是源码也不是版本号 |
| **上下文绑定信任** | 项目级孤岛，禁止跨项目复用 |
| **零隐式状态** | 禁止全局配置文件，仅环境变量 / 项目本地 |
| **源码透明** | 拒绝预编译二进制，全源码 AOT 编译 |

### 15.2 完整流水线

```
开发者 ──┬──► sa fetch <URL>
         │      ├─► HTTP/Git 哑下载 → sa_vendor/
         │      ├─► AST X 光扫描 → 信用分报告
         │      └─► 默认零权限落盘
         │
         ├──► （高危依赖时） sa build → 审判台
         │      ├─► 强制人肉敲完整 URL
         │      ├─► 内存即生即灭的豁免
         │      └─► 计算机器码 SHA → 钉入 sa.lock（仅本项目）
         │
         └──► git push ──► CI（GitHub Actions / 内网 CI）
                              ├─► sa build --ci
                              ├─► 双轨核验（源码 SHA + grants）
                              ├─► TTY 探测 → 自动选择熔断 / 染色
                              ├─► 未审计 → 警告 Banner + Job Summary 看板
                              ├─► 未审计 → 产物物理染色 TAINTED
                              └─► 通过 → 全平台并行编译输出
```

### 15.3 商业杀伤力

这套体系拿去给银行、国防、高密级数据中心：

- ✅ 无法被员工失误带进生产环境的刚性壁垒
- ✅ 不依赖中心化注册，绕过供应链单点故障
- ✅ 安全审计成本：从扫几万行源码 → 看一眼 `sa.mod` 的 `grants`
- ✅ 不可抵赖签字：`sa.mod` 中 `ACKNOWLEDGED_BY_OPERATOR_AT_[TIMESTAMP]` 永久留痕
- ✅ 完全兼容内网断网部署、云原生 Docker / K8s / GitHub Actions

---

## 16. 与现有需求/设计的对应关系

| 本文档 § | 需求/设计落点 |
|---|---|
| §1–§4（工程基础） | R31（已存在，扩展） / R31a（新） |
| §5（防投毒四道墙） | R31b（新） |
| §6（零权限沙箱） | R31c（新） + R17 `@sys_*` 原语 |
| §7（X 光扫描） | R31d（新） |
| §8–§10（破窗 + 机器码 + 项目级孤岛） | R31e（新） + R31f（新） |
| §11（CI/CD 双轨） | R31g（新） |
| §12（全平台交叉编译） | R14 / R15 / R16 增量 |
| §13（断网 / 镜像） | R31g 子项 |
| §14（CLI 命令集） | R16（CLI 四模驱动）扩展 |

新增 Trap 类型（详见 design.md §7.1）：
- `UnauthorizedPrimitive`
- `UpstreamShaMismatch`
- `UnaudtedHighRiskPackage`
- `MachineCodeHashMismatch`
- `BlockedRiskUnconfirmed`
- `MissingTtyForConfirmation`
- `PackageNotResolved`
- `ForbiddenGlobalConfig`

---

## 17. Non-Goals（刻意不做）

| 不做 | 理由 |
|---|---|
| 中心化 registry（crates.io 风格） | 运营成本 + 抢注风险 + 单点故障 |
| SemVer 自动求解 | 依赖地狱根源；SA 强制哈希钉版 |
| `postinstall` / 生命周期钩子 | 投毒温床；SA fetch 必须图灵不完备 |
| 预编译二进制分发 | 黑盒后门；SA 拒绝任何 `.so` / `.dll` / `.a` 包 |
| 全局豁免配置文件 | 隐式宿主机状态污染 |
| 跨项目机器码缓存复用 | 信任污染（爬虫项目的网络权 → 钱包项目被击穿） |
| 写盘的"永久豁免" | 通过 Git 横向传播的安全后门 |
| 进程级权限（`--allow-net`） | 太粗粒度；SA 走模块级零权限 |

---

## 18. 后续议题（待 v0.6+ 决策）

- **GPG/SSH 私钥签章**：是否在 `sa.lock` 引入开发者数字签名 + CI 白名单核验？已讨论但暂时保留意见，因门槛较高；可设计"严格模式（企业用）"vs"宽容模式（个人玩具用）"开关。
- **SARIF 输出**：CI 熔断时是否生成结构化 SARIF 报告，集成到 GitHub Security Tab？
- **编译器自签名**（Self-Signed Binary Hash）：防止黑客通过修改编译器本身绕过 SHA 校验。
- **审计日志归档**：长期保留 `sa fetch` 时的 X 光报告（默认仅打印到 stdout，不归档）。

---

## 19. 实战教程：怎么拉取与审计一个 SA 包

如果你是第一次使用 SA-ASM 的包管理，请跟随本教程感受真正的“零信任”体验。

### 第一步：声明依赖
在你的 `sa.mod` 文件中，加入你想要的包。注意：此时你**不需要**给它任何权限。
```text
require github.com/user/sa-http-utils @v1.0.0
```

### 第二步：拉取源码与 X 光扫描
在终端运行：
```bash
sa fetch
```
由于没有任何 `postinstall` 钩子，下载绝对安全。此时 SA 编译器会对源码进行 AST X光扫描，并在终端打印一份震撼的安全体检报告：
```text
[X-Ray Scan] github.com/user/sa-http-utils
⚠️ 发现 @sys_read_file 调用 (1 处)
⚠️ 发现 @sys_net_connect 调用 (2 处)
⚠️ 发现 @ffi_wrapper 气闸舱开启 (1 处)
综合 Trust Score: 50/100 (高危)
结论：此包具有网络与磁盘读取能力。当前 sa.mod 授予权限：[无]。
```

### 第三步：人工赋权 (Grants)
既然扫描出了网络能力，你必须在 `sa.mod` 中显式为其授予权限，否则编译会直接报错（`Trap: UnauthorizedPrimitive`）。

打开 `sa.mod` 修改：
```text
require github.com/user/sa-http-utils @v1.0.0 grants [net_tx:api.example.com]
```
此时你只给了它往 `api.example.com` 发数据的权限。如果这个包内部悄悄尝试读取你的 SSH 密钥文件（`fs_read`）或连向恶意服务器，SA 会在运行时立刻切断并抛出异常。

### 第四步：锁定机器码 (Locking)
当你完成开发后，运行：
```bash
sa audit --update-lock
```
这不仅会锁定源码的 SHA-256，还会把这个包最终编译出的底层机器码哈希记录进 `sa.lock`。未来在 CI 服务器上，只要机器码发生了1个 bit 的漂移（例如黑客通过 LLVM 后门注入），CI 会直接冷酷熔断。

---

**附录：相关文件清单（v0.5 落地后）**

```
项目根/
├── sa.mod              # 极简依赖清单（手写 + sa fetch 增量补全）
├── sa.lock             # 项目级哈希锁（sa audit --update-lock 写入）
├── sa.sum              # 全树哈希拍平（自动生成，不手编辑）
├── .sa_env             # 可选项目本地镜像/环境配置
├── sa_vendor/          # 局部依赖源码（默认拉取目标）
│   └── github.com/...
├── .sa_cache/          # 项目本地编译缓存（.samx 机器码 / .o）
└── src/
    └── main.sa
~/.sa/                  # 仅 sa fetch -g 时使用，不存豁免状态
└── pkg/
    └── github.com/...
```
