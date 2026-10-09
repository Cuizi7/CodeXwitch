# CodeXwitch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 CodeXwitch 菜单栏账号切换器，自动保存登录、切换时重启官方 Codex，并允许从设置删除已保存账号。

**Architecture:** 使用 SwiftPM 构建一个 AppKit 库和一个极小的应用入口。文件账号存储、操作顺序、系统 App 生命周期和菜单/设置窗口分别集中在少量文件；用两个简单协议替换文件存储与 App 生命周期，测试不接触真实凭据。沿用原目录，不引入账号数据库、临时登录目录、事务日志或跨客户端同步。

**Tech Stack:** Swift 6、Foundation、CryptoKit、AppKit、XCTest；无第三方运行时或包依赖。工程选择 Swift tools 6.0、macOS 13.0 起；首先在本机 arm64/macOS 验证，不声称已在最低版本实测。

**Spec:** [已批准设计](../specs/2026-10-09-account-switcher-design.md)，[菜单原型](../../ui/menu.png)，[设置原型](../../ui/settings.png)。实现中的应用名称和设置窗口标题使用 CodeXwitch。

## Global Constraints

- “A/B 顺序运行，共用原有配置、项目、会话和数据库。”
- “Codex 可以独立从 Dock、Finder 或终端启动。”
- “第一版支持本机原安装 App 和默认 ~/.codex 的文件认证。”
- “没有‘保存账号’按钮。”登录凭据自动采集，约每两秒检查一次；启动、打开菜单及 App 启动/退出通知也刷新。
- “不引入事务日志、崩溃恢复状态机、数据库或跨客户端锁。”不扫描或关闭 VS Code/独立 CLI。
- “目录权限 0700、凭据文件权限 0600”；不输出 token，不上传凭据，不调用 codex logout。
- “不自动回滚、不记录事务阶段、不处理复杂一致性问题。”正常退出未完成或必要保存失败时，不替换/移除活动认证。
- 删除仅移除本程序的保存记录；当前身份的自动保存排除随程序重启保留，直到身份变化或主动添加账号重新登录。
- 不复制会话、不改 config.toml、不使用第二个 CODEX_HOME；退出本程序不退出 Codex，不安装开机启动项。
- 开发及自动测试使用虚构凭据和测试目录，不退出正在承载本聊天的真实 Codex。真实切换验收另行进行。

## Review Focus

1. 外部登录时 auth.json 消失、半写或不可解析：不覆盖旧快照、不清除当前身份的排除记录；Task 1/2。
2. 相同邮箱对应不同用户或 workspace，以及普通 token 刷新：正确区分身份，刷新不新增重复账号；Task 1。
3. 删除当前账号后遇到刷新、切换和小程序重启：不立即保存回来；主动添加后可重新保存；Task 1/2/3。
4. App 拒绝退出、保存失败、写入失败或重复点击：在失败步骤停止后续副作用，恢复可操作状态；Task 2。
5. App 启动失败或设置关闭后再次打开：账号快照仍可重试，UI 不保留过期账号列表、不把 Launch Services 完成当服务端身份确认；Task 2/3/4。

---

## 文件与边界

所有路径相对 `/Users/cuiziqi/Workspace/CodeXwitch`。

| 文件 | 责任 |
| --- | --- |
| `Package.swift` | 一个 CodeXwitchKit 库、CodeXwitch 可执行入口和测试 target |
| `Sources/CodeXwitchKit/Credentials.swift` | 本地 JSON/JWT 身份解析、公开给 UI 的邮箱和不含原始标识的账号 key |
| `Sources/CodeXwitchKit/AccountStore.swift` | 活动 auth.json、私有快照、删除排除记录、文件认证配置检查 |
| `Sources/CodeXwitchKit/Switcher.swift` | 刷新、切换、添加、删除的顺序和忙碌/错误状态 |
| `Sources/CodeXwitchKit/CodexApplication.swift` | 按 bundle ID 枚举、正常退出、等待、启动和显示官方 App |
| `Sources/CodeXwitchKit/MenuController.swift` | 菜单内容和动作绑定 |
| `Sources/CodeXwitchKit/SettingsWindowController.swift` | 保存账号列表、原生删除确认和设置窗口复用 |
| `Sources/CodeXwitchKit/AppDelegate.swift` | 依赖组装、两秒 timer、Workspace 通知、UI 刷新及入口 |
| `Sources/CodeXwitch/main.swift` | 调用 `runCodeXwitch()`，没有业务逻辑 |
| `Tests/CodeXwitchKitTests/{CredentialsTests,AccountStoreTests,SwitcherTests,PresentationTests,TestSupport}.swift` | 临时目录、虚构 token、记录调用的假对象和针对性测试 |
| `Resources/Info.plist`、`scripts/build-app.sh` | 构建原生菜单栏 .app，产物放 `build/` |
| `README.md`、`docs/verification.md` | 用法、支持范围与实际验收证据 |

私有存储使用 `~/Library/Application Support/CodeXwitch/accounts/<account-key>.json`，每个文件原样保存一份有效 auth.json；无需账号索引，列举时解析这些快照。AccountStore 的 directory 参数指向 CodeXwitch 根目录，内部创建 accounts 子目录。删除当前身份时，用根目录的 `suppressed-account.json` 保存一个账号 key。它们均不进入 Git。`account-key` 为 SHA-256 的十六进制，不用 email 或原始 ID 作路径。

## Task 1: 本地身份解析、自动存档与删除

**Files:** Create `Package.swift`、`Sources/CodeXwitchKit/Credentials.swift`、`Sources/CodeXwitchKit/AccountStore.swift`；Test `Tests/CodeXwitchKitTests/CredentialsTests.swift`、`AccountStoreTests.swift`、`TestSupport.swift`。

**Interfaces:**

- `struct Account: Equatable, Sendable { let id: String; let email: String? }`；`id` 是账号 key，缺少邮箱时统一显示“账号（邮箱未知）”。
- `struct Credentials: Equatable, Sendable { let account: Account; let data: Data; static func parse(_ data: Data) throws -> Credentials }`。
- `protocol AccountRepository` 和实现 `final class AccountStore` 都在 `AccountStore.swift`，方法如下：
  `current() throws -> Credentials?`、`accounts() throws -> [Account]`、`credential(for id: String) throws -> Credentials`、`capture(_ credential: Credentials) throws`、`remove(_ id: String, currentID: String?) throws`、`forgetSuppression() throws`、`install(_ credential: Credentials) throws`、`clearCurrent() throws`。
- `AccountStore.init(authURL: URL, directory: URL, configURL: URL)`；`current/install/clearCurrent` 先检查文件认证配置。不存在的 config 或未配置 store 按 file；显式非 file 或无法确定时抛出不含配置内容的错误。
- 测试 helper：`fixture(email: String = "a@example.com", user: String = "user-a", workspace: String = "workspace-a", access: String = "fake-access-a", tokenAccountID: String? = nil) -> Data`，生成虚构三段 JWT；`TestDirectory.init() throws` 提供 `url: URL` 并在销毁时清理。所有错误说明均不包含原始 JSON/token。

- [ ] **Step 1: 建立 SwiftPM 库/测试 target，并写失败测试。** 为使库 target 存在，Credentials.swift 暂时仅含 `import Foundation`；此阶段不创建应用入口或启动 UI。测试覆盖以下确切断言：

```swift
// CredentialsTests.testSameEmailDifferentWorkspaces
XCTAssertNotEqual(try Credentials.parse(fixture(workspace: "workspace-a")).account.id,
                  try Credentials.parse(fixture(workspace: "workspace-b")).account.id)
// testSameWorkspaceDifferentUsers
XCTAssertNotEqual(try Credentials.parse(fixture(user: "user-a")).account.id,
                  try Credentials.parse(fixture(user: "user-b")).account.id)
// testRefreshKeepsIdentity
XCTAssertEqual(try Credentials.parse(fixture()).account.id,
               try Credentials.parse(fixture(access: "fake-access-refreshed")).account.id)
```

`testAccountIDOverrideAndEmailFallback`：tokens.account_id 优先于 JWT workspace；顶层 email 优先，缺失时读 profile namespace.email。`testInvalidCredentialDoesNotLeakTokens`：API-key-only、缺少必要 token、无效 JWT、缺少用户/workspace 身份均失败，错误文本不含 `fake-access-a`。

`AccountStoreTests.testCaptureUpdatesOneSnapshot`：capture 两个版本后 `accounts().count == 1`，`credential(for: id).data == refreshed.data`。`testPartialCurrentPreservesSnapshot`：活动文件改成 `{` 后 `current()` 抛错，已存数据保持原字节。

`testDeleteCurrentSurvivesRefreshAndRestart`：删除当前 A，重建同路径 AccountStore，再 capture 刷新后的 A，`accounts().isEmpty == true`；临时缺失 auth 不解除排除。`testIdentityChangeOrExplicitAddAllowsCapture`：capture B 或调用 forgetSuppression 后 capture A，A 可保存。`testDeleteAlternativeKeepsCurrent`：删除 B，活动文件字节仍等于 A。

`testPrivatePermissionsAndRestrictedWrites`：目录 POSIX 权限等于 `0o700`，快照、排除记录与新活动认证等于 `0o600`；在测试 home 写入哨兵 config/session/数据库文件，存档/安装/清空后它们逐字节相同。`testCredentialBackendPolicy`：未配置/file 可读，keyring/auto/ephemeral/未知值拒绝，注释中的示例不改变判断。

- [ ] **Step 2: 确认测试失败。** Run `swift test --filter CredentialsTests`、`swift test --filter AccountStoreTests`；Expected：缺少上述类型或功能造成编译/断言失败，记录为 RED，不把构建环境错误算作 RED。
- [ ] **Step 3: 实现上述接口。** JWT 只解码本地元数据，不验证签名或宣称登录有效；要求非空 id/access/refresh token。用户取 auth namespace.chatgpt_user_id，缺失时取 sub；workspace 取 tokens.account_id，缺失时取 auth namespace.chatgpt_account_id；key 为用户和 workspace 用 NUL 分隔后 SHA-256。保留完整原始文件，不重建 auth JSON、不依据过期 access token 丢弃可刷新的账号。
- [ ] **Step 4: 完成最小文件存储。** `capture` 尊重当前排除，另一有效身份才解除；成功写完才算保存。原子写入使用同目录临时文件，创建时即 0600，rename 替换；这里只是避免半份文件，没有日志或恢复流程。`accounts()` 按邮箱/id 稳定排序；损坏快照不作为切换目标，合法快照继续可列出；`credential(for:)` 对损坏目标报错。配置检查只支持普通配置中的根级 store 字段、单双引号和注释；字段出现在不支持的配置结构或有矛盾定义时明确拒绝，不复刻完整 TOML/managed 配置优先级。
- [ ] **Step 5: 确认通过。** Run `swift test --filter CredentialsTests`、`swift test --filter AccountStoreTests`；Expected：上述测试全部 PASS。补 `testCorruptSavedFileDoesNotHideValidAccounts`：一份损坏快照不使合法 A 消失。
- [ ] **Step 6: Commit。** `git add Package.swift Sources/CodeXwitchKit/Credentials.swift Sources/CodeXwitchKit/AccountStore.swift Tests/CodeXwitchKitTests`，`git commit -m "feat: manage local account credentials"`。

## Task 2: 简单切换、添加与删除操作

**Files:** Create `Sources/CodeXwitchKit/Switcher.swift`；Test `Tests/CodeXwitchKitTests/SwitcherTests.swift`；Modify `TestSupport.swift` 加入假仓库和假 App。

**Interfaces:**

- Consumes：Task 1 的 AccountRepository 和 Credentials。
- Produces：`@MainActor protocol AppLifecycle { var isRunning: Bool { get }; func quit() async throws; func launch() async throws; func show() async throws }`。
- `struct SwitcherState: Equatable { var isRunning: Bool; var current: Account?; var accounts: [Account]; var isBusy: Bool; var error: String? }`。
- `@MainActor final class Switcher`：`init(repository: any AccountRepository, app: any AppLifecycle)`；`private(set) var state: SwitcherState`；`var onChange: ((SwitcherState) -> Void)?`；`refresh()`；`switchTo(_ id: String) async`；`addAccount() async`；`deleteAccount(_ id: String, confirmed: Bool)`。操作错误收敛为状态，不向 UI 抛 token/内部身份。

- [ ] **Step 1: 写失败测试。** `@MainActor` 的测试使用记录调用顺序的假仓库/FakeApp；按以下断言分别测试，不产生真实进程：

```swift
// testSwitchOrder
XCTAssertEqual(events, ["read-target", "quit", "read-current", "capture-current", "install-target", "launch"])
// testAddOrder
XCTAssertEqual(events, ["quit", "read-current", "capture-current", "clear-current", "forget-suppression", "launch"])
// testCancelledDelete
XCTAssertEqual(events, [])
// testBusyOperationIgnoresSecondClick
XCTAssertEqual(launchCount, 1)
```

顺序断言只截取操作副作用，末尾刷新读列表另行断言。`testRefreshDiscoversExternalAppAndLogin`：假 App 已运行，仓库有未保存 A，刷新后运行中、current == A、A 自动保存且 quit/launch 均未调用。`testSameAccountNeverInstallsStaleSnapshot`：选择当前 A 时只更新最新凭据并 show；App 未运行则 launch，不 install。

`testQuitFailureStopsMutation`、`testCaptureFailureStopsMutation`、`testInstallFailureStopsLaunch`：分别注入错误，后续写入/清空/launch 不发生，`state.isBusy == false` 且错误说明指出步骤。`testLaunchFailureRetainsSavedAccountsAndAllowsRetry`：一次失败后重试可以 launch，原快照未删，无自动回滚。`testMissingAuthAfterCancelledAddCanSwitchBack`：current == nil 时切回已保存 A 可完成。

`testDeletedCurrentIsNotRecapturedDuringSwitch`：实际临时 AccountStore 删除 A 后切 B，A 不重新保存；`testAddReenablesCaptureAfterRemoval`：添加流程完成清空后解除排除，随后登录 A 并 refresh 可以保存。`testMalformedRefreshDoesNotRemoveSavedAccounts`：部分 JSON 时 current 不显示旧身份为确切新状态，error 有说明、原列表保留、timer 不触发重启。

- [ ] **Step 2: 确认失败。** Run `swift test --filter SwitcherTests`；Expected：接口缺失或行为断言 FAIL。
- [ ] **Step 3: 实现 Switcher。** 操作开始同步设置 isBusy，`defer` 恢复；所有刷新及删除在 busy 时跳过，避免同一程序内重入。按上述顺序工作，quit 后重读当前凭据；未登录时无需保存。capture 尊重排除规则。失败只报告，不回滚；refresh 不立即抹掉未处理的操作错误。current/运行状态只来自本次磁盘读和 App 枚举，不依赖启动指针。
- [ ] **Step 4: 确认通过。** Run `swift test --filter SwitcherTests`；Expected：所有顺序、失败、外部启动和删除测试 PASS。
- [ ] **Step 5: Commit。** `git add Sources/CodeXwitchKit/Switcher.swift Tests/CodeXwitchKitTests`，`git commit -m "feat: switch and add accounts through the original app"`。

## Task 3: 官方 App 生命周期、菜单及设置窗口

**Files:** Create `Sources/CodeXwitchKit/{CodexApplication,MenuController,SettingsWindowController,AppDelegate}.swift`、`Sources/CodeXwitch/main.swift`；Modify `Package.swift` 增加 executable target；Test `Tests/CodeXwitchKitTests/PresentationTests.swift`。

**Interfaces:**

- Consumes：Task 2 的 Switcher/State/AppLifecycle；UI 只调用这些业务入口。
- `@MainActor final class CodexApplication: AppLifecycle`，`init(bundleIdentifier: String = "com.openai.codex", quitTimeout: TimeInterval = 10)`。
- `@MainActor final class MenuController: NSObject, NSMenuDelegate`：`init(switcher: Switcher, openSettings: @escaping () -> Void, quitManager: @escaping () -> Void)`、`let menu: NSMenu`、`rebuild()`。
- `@MainActor final class SettingsWindowController: NSWindowController`：`init(switcher: Switcher, confirmDeletion: @escaping (Account) -> Bool)`、`reload()`；标准 showWindow 方法显示同一个窗口。
- `@MainActor final class AppDelegate: NSObject, NSApplicationDelegate` 组装真实依赖；`@MainActor public func runCodeXwitch()` 创建并持有 delegate，设置 accessory 激活策略，然后运行 NSApplication。

- [ ] **Step 1: 写失败展示测试。** 初始化 NSApplication 仅用于 AppKit 控件，不使用真实 AppLifecycle 或真实 home。`testMenuUsesExternalStatusAndAlternatives` 断言菜单首项为 `Codex：运行中`，包含 `当前：a@example.com` 和 B，不重复把 A 列为目标；尾部顺序为 `添加账号…`、`刷新状态`、`设置…`、`退出菜单栏程序`，没有“保存账号”。`testBusyMenuDisablesMutation` 断言切换、添加和设置删除动作禁用。

`testSettingsRowsRefreshOnReopen`：显示 A/B 后删除 B，再 reload，窗口只显示 A；title == `CodeXwitch 设置`。`testDeleteConfirmationFalseHasNoSideEffect`：注入返回 false 的确认 closure，列表与认证不变；true 时只有私有快照删除。`testUnknownEmailAndReadErrorAreDisplayable`：缺邮箱使用统一文案；坏认证显示读取错误而非伪造 A；空列表提供“暂无已保存账号”。`testQuitManagerDoesNotQuitCodex`：注入 quitManager 假动作，只记录程序退出请求，不调用 AppLifecycle.quit。

- [ ] **Step 2: 确认失败。** Run `swift test --filter PresentationTests`；Expected：展示接口或断言 FAIL，不启动真实 Codex。
- [ ] **Step 3: 实现 CodexApplication。** 使用 NSRunningApplication.runningApplications(withBundleIdentifier:) 枚举当前原 App，不依赖本程序启动记录。quit 对匹配实例请求 terminate，最多等待 10 秒并检查 isTerminated/重新枚举；请求返回 true 不是退出证据，拒绝/超时抛错，不 forceTerminate。App 路径优先来自匹配实例 bundleURL，否则 NSWorkspace.urlForApplication；异步 openApplication 的 completion 回到 MainActor。show 激活现有 App，未运行时 launch。不读取其他进程环境、不扫描 CLI/IDE占用。
- [ ] **Step 4: 实现菜单和设置。** 原生 NSStatusItem + NSMenu，图标使用 SF Symbol `person.2`；邮箱和身份都来自 state。设置窗口采用原生控件、约 570×390 pt、两行列表视觉参照已批准图片。每行“删除”触发 NSAlert，按钮“取消”“删除”，使用 spec 中的完整确认文字；帮助文案沿用原型。不加入其他设置、保存按钮或配额图表。错误使用不含凭据的原生提示。
- [ ] **Step 5: 接入刷新和入口。** AppDelegate 创建默认 auth/config URL 和 Application Support 目录；立即 refresh。使用约 2 秒 Timer，Workspace 自身 notificationCenter 的 didLaunch/didTerminateApplicationNotification，menuWillOpen 时 refresh。一个 onChange 回调同时更新菜单和已打开设置；退出时取消 timer/observer，不向 Codex 发退出请求。自动保存失败保留可见错误，并在下次轮询重试，不仅按 mtime 判定成功。
- [ ] **Step 6: 确认通过。** Run `swift test --filter PresentationTests`、`swift build`；Expected：展示测试全部 PASS、应用入口编译成功。新增 `testMissingOfficialAppReportsError` 使用不存在的测试 bundle ID，报未找到 App，绝不启动当前 Codex。
- [ ] **Step 7: Commit。** `git add Package.swift Sources Tests/CodeXwitchKitTests/PresentationTests.swift`，`git commit -m "feat: add native menu and account settings"`。

## Task 4: 打包、集成验证与交付

**Files:** Create `Resources/Info.plist`、`scripts/build-app.sh`、`docs/verification.md`；Modify `README.md`。

**Interfaces:** Consumes `swift build -c release --product CodeXwitch` 的可执行文件；Produces `build/CodeXwitch.app`，运行方式 `open build/CodeXwitch.app`。脚本仅打包，不自动安装/启动；bundle identifier `local.codexwitch.app`、CFBundleName/DisplayName `CodeXwitch`、LSUIElement true、最低系统版本 13.0。

- [ ] **Step 1: 增加可检查的打包约定。** README 写明 `swift test` 和 `bash scripts/build-app.sh`，本机使用方法和支持范围。打包用后续 bundle/plist/签名检查验证，不为复制文件编写镜像实现的测试，也不把脚本尚不存在当功能失败测试。
- [ ] **Step 2: 实现脚本和 Info.plist。** 用 `swift build --show-bin-path -c release` 获取路径，创建 Contents/MacOS、Contents/Resources，复制二进制与 plist，ad-hoc 签署本程序；不改签官方 Codex，不增加 sandbox entitlement、登录项或安装器。版本起始 0.1.0；脚本遇到错误停止。
- [ ] **Step 3: 验证已集成结果。** 按用户 AGENTS 委托一名 tester 执行 `swift test`、`bash scripts/build-app.sh`、`plutil -lint Resources/Info.plist`、`codesign --verify --strict build/CodeXwitch.app`；Expected：测试全 PASS、plist OK、原生 bundle 存在且本地签名检查通过。打包成功不等于登录/切换验收成功；不重复运行无新增变更的测试。
- [ ] **Step 4: 独立审阅。** 按用户 AGENTS 调用一名 reviewer 检查整个最终改动的凭据保护、删除语义、失败顺序及 scope；不重复 quick review，不给每个小文件另建任务。修复 approved scope 内发现后重跑受影响检查。
- [ ] **Step 5: 写验收记录。** `docs/verification.md` 分开列自动测试、原生 UI 检查、真实账号检查及未验证项。README 说明仅管理默认文件认证、外部客户端需自行退出、删除当前保存记录不退出 App、取消添加后选择原账号恢复、无自动回滚和源码构建用法。真实 UI/账号验收尚未做时明确写未验证，不把 mock 的 PASS 当实际登录成功。
- [ ] **Step 6: 做经用户安排的真实验收。** 先在真实 Codex 已运行时启动 CodeXwitch，核对菜单状态、自动保存和设置；这会保存真实凭据，必须在用户安排的验收环节进行。再在用户准备好退出本聊天所在 App 时验证添加 B、切回 A、原会话继续和已保存账号删除。不得在自动执行中为验收突然终止本聊天；不能协调这一步时保留待验收说明。
- [ ] **Step 7: Commit。** `git add Resources scripts README.md docs/verification.md`，`git commit -m "build: package and document CodeXwitch"`。交付源码、.app 和实际验证记录；不推送远端或发布。

## 已核实的接口事实

本机 Swift 6.3.3、arm64、macOS 27.0.1；官方 App bundle ID `com.openai.codex`。AppKit SDK 的 terminate 只提交请求，openApplication completion 只表示 Launch Services 的打开结果；没有公开接口读取正在运行 App 的内存账号，当前账号展示遵循 spec 的磁盘认证范围。

身份/认证事实参考 OpenAI Codex 源码提交 `2351d9e1b608e6f9d9a3699b71d7eb39ee41cfa4` 的 [token_data.rs](https://github.com/openai/codex/blob/2351d9e1b608e6f9d9a3699b71d7eb39ee41cfa4/codex-rs/login/src/token_data.rs)、[manager.rs](https://github.com/openai/codex/blob/2351d9e1b608e6f9d9a3699b71d7eb39ee41cfa4/codex-rs/login/src/auth/manager.rs)、[types.rs](https://github.com/openai/codex/blob/2351d9e1b608e6f9d9a3699b71d7eb39ee41cfa4/codex-rs/config/src/types.rs)。这些字段是当前实现事实，不是对所有未来认证模式的兼容承诺；本次规划没有读取真实 auth.json。

## 自检与执行交接

设计的自动保存、外部启动、两秒刷新、删除排除、单 App 添加/切换、失败提示、设置 UI、权限及交付分别由 Task 1–4 覆盖。Review Focus 五项均已落实到具名测试；接口在相邻任务保持一致。没有产品实现、真实账号导入或 App 退出发生。

建议选择 Native：由主线程依次实现这四项，最终由独立 reviewer/tester 审阅和验证；任务共享同一套很小的接口，逐项新上下文实现收益较低。也可选择 Subagent-driven，由独立实现者和审阅者逐项交付。待用户审阅计划并选择执行方式后才进入实现。
