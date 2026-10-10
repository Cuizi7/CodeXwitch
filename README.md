<p align="center">
  <img src="Resources/Icons/app-icon-final.svg" width="104" height="104" alt="CodeXwitch 图标">
</p>

# CodeXwitch

**在同一个 Codex App 中，手动切换登录账号。**

CodeXwitch 是一个原生 macOS 菜单栏工具。它保存本机已登录账号的凭据，在你选择另一个账号时，正常退出 Codex、替换认证文件，然后重新打开原来的 App。配置、项目和会话继续使用原目录。

CodeXwitch 是独立的第三方项目，与 OpenAI 没有隶属或背书关系。它不自动按额度轮换账号，也不显示剩余额度。

<p align="center">
  <img src="docs/images/menu.png" width="360" alt="CodeXwitch 下拉菜单，展示当前账号与备选账号">
</p>

截图已移除其他菜单栏图标，邮箱替换为示例地址。

## 功能

- 自动识别从 Dock、Finder 等其他入口启动的 Codex。
- 登录后自动保存账号，并跟随磁盘中的凭据刷新更新保存记录。
- 在下拉菜单中查看当前账号、选择备选账号，或启动已停止的 Codex。
- 添加账号时在原 Codex App 中完成官方登录。
- 在设置窗口中删除已保存账号，查看程序版本。
- 显示准备、等待退出、切换和启动等操作阶段。

| 菜单栏图标 | 状态 |
|---|---|
| 交叉箭头 | Codex 运行中 |
| 空心圆 | Codex 未运行 |
| 分段圆环 | 处理中，包括等待退出确认 |
| 感叹号 | 操作或读取发生错误，打开菜单查看详情 |

处理时只旋转内圈，六边形外框保持固定；系统开启“减少动态效果”时停止旋转。

## 安装

### 从源码安装

需要 macOS、包含 Swift 6 工具链的 Xcode，以及已经安装的官方 Codex App。项目使用 SwiftPM 和 AppKit，没有第三方运行依赖。

下载或克隆源码后，在项目根目录运行：

```sh
swift test
bash scripts/build-app.sh
open build/CodeXwitch.app
```

也可以将 `build/CodeXwitch.app` 移到 Applications 后打开。构建脚本只生成应用，不自动安装或启动；产物使用本机架构和 ad-hoc 签名，尚未完成公开发行的 Developer ID 签名与公证。

CodeXwitch 的部署目标为 macOS 13+，目前仅在 Apple Silicon 开发环境验证。最低系统版本和 Intel 尚未实机验证；官方 Codex 也必须能在你的系统中运行。当前还没有正式公开的预编译 Release。

### 使用预编译包

仓库启用 GitHub Actions 后，每次 CI 成功运行都会在运行页面提供 `CodeXwitch-版本-macos-架构.zip` 构建产物；正式发行包将放在仓库的 Releases 页面。

1. 选择与你的 Mac 架构一致的压缩包：Apple Silicon 使用 `arm64`，Intel 使用 `x86_64`；目前 CI 构建 Apple Silicon 版本。
2. 解压后将 `CodeXwitch.app` 拖入 Applications，再打开应用。它常驻菜单栏，不显示 Dock 图标。
3. 更新时先从下拉菜单退出旧 CodeXwitch，替换 `.app` 后重新打开。账号保存记录会保留。

当前预编译包同样只有 ad-hoc 签名，未公证，下载后可能被 macOS Gatekeeper 阻止。仅在确认来源可信时，按系统“隐私与安全性”中的提示处理；不要对未知来源的应用关闭系统保护。系统说明见 [Apple：安全地打开 Mac 上的 App](https://support.apple.com/102445)。

### 卸载

退出 CodeXwitch 并删除 `.app` 即可。若也要移除保存的账号，在应用设置中删除记录，或自行移除 `~/Library/Application Support/CodeXwitch/`；该目录包含完整凭据。不要为卸载 CodeXwitch 删除 `~/.codex`，其中有 Codex 的认证、配置与会话。

## 使用

1. 正常打开 Codex 并登录，再打开 CodeXwitch。当前账号会自动加入已保存列表。
2. 点击“添加账号…”。CodeXwitch 会正常退出 Codex、保存当前凭据，并重新打开 Codex 的登录界面。在官方 App 中登录另一个账号即可。
3. 打开下拉菜单，点击备选账号完成切换。添加过程中放弃登录时，可以选择已保存账号切回。
4. 打开“设置…”移除不再需要的账号保存记录。删除当前账号的记录不会退出 Codex，也不会立即被自动保存回来。

切换前请完成 Codex 中正在执行的任务。如果 Codex 弹出退出确认，请在其窗口中确认；CodeXwitch 最多等待 60 秒。拒绝退出或超时会停止操作，认证文件不会被替换。

保存、写入或启动失败时会显示失败阶段。程序不会自动回滚；已保存记录保留，修正问题后可重试。Codex 未运行且仍有当前账号时，菜单中的“启动 Codex”可直接重试启动。

## 支持范围

- 官方桌面 App，bundle ID 为 `com.openai.codex`。
- 默认 `~/.codex` 目录，ChatGPT 登录方式与文件认证。
- 普通配置中的根级 `cli_auth_credentials_store = "file"`，或未设置该字段的情况。

暂不支持自定义 `CODEX_HOME`、API-key 认证、keyring/auto/ephemeral 认证后端、复杂或托管配置，以及自定义启动参数。不受支持或无法确定的认证配置会报错，程序不会修改 `config.toml`。

VS Code 扩展和独立 Codex CLI 如果共用认证，需要你自行退出；CodeXwitch 只管理官方桌面 App，不保证其他客户端同步切换。菜单账号反映磁盘认证，不能据此独立证明服务端登录有效或计费归属。

## 本地数据与隐私

| 路径 | 用途 |
|---|---|
| `~/.codex/auth.json` | Codex 当前认证；切换时替换，添加账号时移除 |
| `~/Library/Application Support/CodeXwitch/accounts/` | 已保存账号的完整凭据快照 |
| `~/Library/Application Support/CodeXwitch/suppressed-account.json` | 防止已删除的当前账号立即被重新保存 |

凭据保存在本机文件中，**包含 token，未额外加密，也未存入钥匙串**。程序设置私有目录权限为 `0700`、凭据文件权限为 `0600`；有相应本机访问权限的软件仍可能读取它们。CodeXwitch 不上传凭据，不记录 token、邮箱或账号 ID，也不调用 `codex logout` 撤销已保存凭据。

请勿将认证文件、账号快照、token 或含真实账号的截图提交到仓库或公开 Issue。删除保存记录只移除本机副本，不等于撤销登录授权。

## 排查问题

在 macOS Console 中按 subsystem `local.codexwitch.app` 过滤，或运行：

```sh
/usr/bin/log show --last 30m --info --style compact \
  --predicate 'subsystem == "local.codexwitch.app"'
```

日志包含操作阶段、退出等待、主进程 PID、耗时和启动结果，可用于区分退出超时与重新启动失败。报告问题时附上 macOS、Codex 与 CodeXwitch 版本、复现步骤和经过检查的相关日志；不要附上认证文件。

## 开发与贡献

| 目录 | 内容 |
|---|---|
| `Sources/CodeXwitch/` | 应用入口 |
| `Sources/CodeXwitchKit/` | 账号存储、切换流程、App 生命周期和原生 UI |
| `Tests/CodeXwitchKitTests/` | 虚构凭据、临时目录、假 App 与原生绘制测试 |
| `Resources/` | 应用元数据、App 图标和图标矢量源 |
| `scripts/build-app.sh` | 构建并打包 `.app` |

提交行为变更时，请描述复现方式和预期行为，加入相关回归测试，并运行 `swift test`。涉及退出和凭据写入时，应使用假 App 与临时认证目录，不以真实账号切换代替自动测试。开发约定见 [AGENTS.md](AGENTS.md)，验证范围见 [docs/verification.md](docs/verification.md)，图标说明见 [Resources/Icons/README.md](Resources/Icons/README.md)。

CI 在 macOS runner 上执行完整测试、Release 打包、plist 与签名验证，并上传应用压缩包。工作流见 [.github/workflows/ci.yml](.github/workflows/ci.yml)。CI 不自动发布 Release，不使用真实账号，不包含 Developer ID 签名密钥。

## 更新日志

### 0.1.6

- 修复旧版 SwiftPM 构建的应用在移动目录后可能找不到图标资源的问题。
- 采用 MIT 许可证，应用包附带许可证文本。
- 增加 macOS CI、匿名化 UI 截图与安装说明。

### 0.1.5

- 下拉菜单顶部显示 CodeXwitch 名称。
- 设置窗口右下角显示当前程序版本。

### 0.1.4

- 接入统一的圆角六边形 App 图标和四种菜单栏状态图标。
- 等待退出与其他处理中共用内圈动画，外框固定，响应系统“减少动态效果”。

### 0.1.3

- 等待原 Codex 主进程实际结束后再重新启动，避免打开仍在退出的旧实例。
- 下拉菜单显示准备、退出、保存、切换和启动阶段。

### 0.1.2

- 修复 AppKit 旧对象退出状态未更新导致的误判。
- 退出等待延长至 60 秒，并提示在 Codex 中确认退出。

### 0.1.1

- 增加不包含凭据的 macOS 统一诊断日志。

### 0.1.0

- 首个版本：自动保存账号、顺序切换、添加账号和删除保存记录。
- 识别外部启动的 Codex，共用原有配置、项目与会话。

## 许可证

采用 [MIT License](LICENSE)。
