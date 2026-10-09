# CodeXwitch 验证记录

日期：2026-10-09。环境：Swift 6.3.3、arm64、macOS 27.0.1。最终产品代码提交：`ec7dda5`。

## 自动验证与原生 UI

- 主线程最终 `swift test`：40 项通过，0 失败；包括所有凭据、存储、切换和原生展示测试。
- 独立 tester 在 `fa1c727` 上执行完整 36 项套件与 release 打包；审阅修复后在 `ec7dda5` 上再次执行两项新增回归测试（2/2）并重新构建 release。
- `bash scripts/build-app.sh` 成功生成 `build/CodeXwitch.app`；源 plist 和产物 plist 均通过 `plutil -lint`；`codesign --verify --strict` 通过。
- Bundle：`local.codexwitch.app`、版本 `0.1.0`、`LSUIElement=true`、二进制架构 `arm64`。
- 最终二进制 SHA-256：`a20564ccd60c9c8e2312c30e5adf9e45c396165fe7e097bc4ec53f2caf52e046`。
- 所有自动测试使用虚构 JWT、临时目录和假 App，覆盖自动存档、身份区分、刷新、删除排除、操作顺序、忙碌禁用、失败停止和重试。
- 原生菜单测试覆盖外部已运行状态、备选过滤、设置入口和当前账号启动动作；原生设置控件测试覆盖删除确认、列表更新、空状态及布局。
- 测试渲染虚构 A/B 账号的实际设置窗口并人工查看，修复列表位置及按钮对齐。此项是原生控件验证，不是与真实 Codex 的完整 GUI 交互验收。

## 独立审阅

最终独立 reviewer 审阅 `056ddf4..fa1c727`，指出两项 P2，均在一个有限修复批次中完成：

1. 启动失败后当前账号被菜单过滤，无法直接重试：新增 App 未运行时的“启动 Codex”，复用现有同身份启动分支；菜单回归测试先失败后通过。
2. 转义 TOML quoted key 绕过认证后端检查：对无法解释的转义 quoted key 明确拒绝；测试证明 current/install/clearCurrent 均停止且活动文件不变，先失败后通过。

额外补充添加流程清空认证/清除排除记录失败的边界测试；没有新建同步、恢复或数据库组件。修复后整套 40 项通过；未进行重复独立复审，不声称复审结论。

## 执行决策与范围

- 在用户指定的新仓库 `~/Workspace/CodeXwitch` 的 `feat/menu-account-switcher` 分支开发，未创建第二个 worktree。后续并行编辑同一 checkout 需要协调。
- 切换和添加前先重读认证：防止两秒轮询之间发生的外部登录导致旧快照覆盖，仅增加一次小文件读取。
- 按用户明确要求保留简单方案，不加入跨客户端锁、事务日志或自动回滚；其他共用认证的客户端需自行退出，异常情况手动重试。
- 按已批准 UI 保留邮箱显示，不增加 workspace 标签；存储身份仍正确区分，但同邮箱或未知邮箱的多个账号可能不易在 UI 中区分。

没有 deferred minor code finding；上述范围限制已明确保留。

## 真实账号验收尚未进行

没有启动真实 CodeXwitch 来读取或保存本机 auth.json，没有切换真实账号，没有退出当前真实 Codex。

仍需由用户安排：在 Codex 已运行时打开 CodeXwitch，核对真实账号自动保存与菜单；准备好退出当前 App 后，验证添加 B、切回 A、原会话继续与删除。真实 App 的拒绝退出、OAuth 刷新令牌复用、启动后的身份/计费归属，以及设置窗口完整关闭再打开链路均不由假 App 测试证明。

最低支持版本 macOS 13 是工程部署目标，未在 macOS 13 实机验证，也未验证 Intel 构建。产物为本机 arm64 开发签名应用，未做公开发行 notarization。
