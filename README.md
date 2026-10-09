# CodeXwitch

Codex 账号切换器，一个简单的 macOS 菜单栏程序。

- 识别已经独立启动的官方 Codex，自动保存登录账号与更新后的凭据。
- 点击备选账号，正常退出 Codex，切换 `auth.json`，再启动原 App。
- 添加账号时，在原 App、原目录中进入未登录状态，直接完成官方登录。
- 设置窗口支持删除已保存账号，包括当前账号的保存记录。
- 继续使用原配置、项目、会话与数据库。退出 CodeXwitch 不退出 Codex。

## 构建与运行

需要 macOS 13+、Swift 6 / Xcode Command Line Tools；无第三方依赖。

```sh
swift test
bash scripts/build-app.sh
open build/CodeXwitch.app
```

脚本仅构建 `build/CodeXwitch.app`，不会自动启动或安装。产物是本机架构，使用本地 ad-hoc 签名；可将 `.app` 拖入 Applications 后自行打开。

## 使用

1. 正常打开官方 Codex 并登录，再打开 CodeXwitch；菜单中自动显示当前账号。
2. 点击“添加账号…”。Codex 会退出并重新启动进入登录流程；登录完成后账号自动加入列表。
3. 菜单列出当前账号以外的已保存账号，点击即可切换。添加过程中放弃登录，可以选择之前保存的账号切回。
4. “设置…”中每行的“删除”仅移除本程序的保存记录，不退出当前 Codex、不删除会话。删除当前账号后，凭据刷新和小程序重启不会立即保存回来；切到其他账号后或主动走“添加账号”流程重新登录，可再次保存。

切换和添加会正常退出官方 App，请先完成正在运行的任务。等待期间菜单显示“等待退出”和确认提示；如果 Codex 弹出退出确认，请在 Codex 中处理。Codex 拒绝退出或等待超过 60 秒时，操作停止，活动认证不会修改；确认并退出后可重试。提前退出就立即继续，无需等满 60 秒。读写或启动失败时菜单/原生提示显示失败步骤；账号快照保留，可重试，没有自动回滚。App 未运行而磁盘仍有当前账号时，菜单提供“启动 Codex”，可直接重试启动而不回放旧凭据。

操作时菜单首行显示当前阶段：准备账号、等待 Codex 退出、保存账号、切换账号或准备登录、正在启动 Codex。等待退出期间附带确认提示，操作完成或失败后恢复运行状态。

## 支持范围与本地数据

第一版针对默认 `~/.codex`、文件认证、原安装 App（bundle ID `com.openai.codex`）。支持普通配置中根级 `cli_auth_credentials_store = "file"` 或默认值；keyring、auto、ephemeral、无法判断的配置会报错，不修改 `config.toml`。自定义 CODEX_HOME、启动参数、复杂/托管配置和 API-key 认证不在本版范围内。

菜单运行状态来自系统 App 列表，账号来自磁盘认证；不读取官方 App 的私有内存状态。正常外部启动/退出/登录无需由 CodeXwitch 发起。VS Code、独立 Codex CLI 或其他客户端如果共用认证，需要用户自行退出；程序不扫描或关闭它们，也不保证它们同步切换。

账号快照保存在 `~/Library/Application Support/CodeXwitch/accounts/`，排除记录是同目录上级的 `suppressed-account.json`。私有目录 0700、文件 0600；凭据只保存在本机，不输出 token、不上传数据，不使用 `codex logout` 撤销保存凭据。该目录含登录凭据，不要提交或公开它。

## 诊断日志

0.1.1 起使用 macOS 系统统一日志，Console 中按 subsystem `local.codexwitch.app` 过滤，或运行：

```sh
/usr/bin/log show --last 30m --info --style compact --predicate 'subsystem == "local.codexwitch.app"'
```

退出相关日志包含随机 attempt ID、PID、terminate 请求结果、耗时、原对象 captured 与重新枚举 fresh 的退出状态、仍存在的原主进程 alive_pids、完成或超时判定；启动完成记录系统实际返回的 returned_pid。等待时状态变化或约每秒记录一次；系统 launch/terminate 通知即使在切换忙碌期间也记录。操作日志包含类型、失败阶段和错误类型，不包含邮箱、账号 ID、token 或认证文件内容。

更新后需重新启动 CodeXwitch 才会启用新版。0.1.3 同时检查最新系统 App 列表和退出前捕获的主进程 PID，避免旧对象状态未更新造成超时，也避免列表短暂为空时过早重启。PID 检查不发送信号、不强制结束进程，不扫描 VS Code 或 CLI；退出等待上限仍为 60 秒。

## 设计与验证

- [已批准设计](docs/superpowers/specs/2026-10-09-account-switcher-design.md)
- [实现计划](docs/superpowers/plans/2026-10-09-codexwitch-implementation.md)
- [验证记录与尚未实测的项目](docs/verification.md)
- [下拉菜单原型](docs/ui/menu.png)
- [设置窗口原型](docs/ui/settings.png)

CodeXwitch 是独立的第三方工具。只提供手动切换，不自动按额度轮换。
