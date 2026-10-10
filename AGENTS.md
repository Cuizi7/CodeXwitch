# CodeXwitch 开发约定

CodeXwitch 是一个 SwiftPM / AppKit 原生 macOS 菜单栏程序。保持实现简单，修改以用户请求为边界；不要顺手改写账号流程或增加通用基础设施。

## 项目结构

- `Sources/CodeXwitch/main.swift`：入口。
- `Sources/CodeXwitchKit/Credentials.swift`：本地身份元数据解析与账号匹配。
- `AccountStore.swift`：凭据快照、私有文件写入及删除排除记录。
- `Switcher.swift`：串行账号操作及 UI 状态。
- `CodexApplication.swift`：官方 Codex 的正常退出、进程结束检查及启动。
- `AppDelegate.swift`、`MenuController.swift`、`SettingsWindowController.swift`：AppKit 展示与生命周期。
- `MenuBarIcons.swift`：单色模板资源和内圈绘制。
- `Resources/Icons/`：图标矢量源；运行用 PDF 在库 target 的 `Resources/Icons/` 中。
- `Tests/CodeXwitchKitTests/`：测试；`TestSupport.swift` 提供虚构凭据、临时目录和假 App。

## 操作与数据边界

1. 默认只支持官方桌面 App、`~/.codex` 和文件认证。遇到不受支持的配置应明确停止，不修改用户配置或猜测后端。
2. 正常退出官方 App 并确认退出完成后，重新读取并保存最新凭据，成功后才切换或移除活动认证。退出拒绝、超时或保存失败时，不继续修改认证；当前账号已被删除保存记录时尊重其排除规则。
3. 退出完成必须同时满足：最新 App 列表为空，以及退出前固定捕获的主进程 PID 已不存在。不要重新依赖旧 AppKit 对象的 `isTerminated`，也不要在退出后重新读取可能失效的 PID。
4. `kill(pid, 0)` 只用于检查这些固定 PID，不发送退出信号。不得按进程名扫描或强杀 Codex、VS Code、CLI 或其他客户端。
5. 保持 60 秒退出等待及确认提示；忙碌期间禁止重复操作。UI 更新必须在主线程进行。
6. 当前账号已被用户删除保存记录时，尊重排除记录，包括凭据刷新和程序重启。选择当前账号不得回放旧快照。
7. 保留完整原始凭据文件、同目录原子替换及目录 `0700` / 文件 `0600` 权限。不删除会话、项目或数据库，不调用 `codex logout`。
8. 不增加双开、独立配置目录、自动按额度换号、跨客户端锁或自动回滚；这类改变需要单独讨论。

## 凭据与日志

- 不读取真实认证或账号快照来编写测试，不将其复制到工作区。
- 不在代码、日志、截图、Issue、测试输出中暴露 token、真实邮箱、账号 ID 或原始认证内容。
- JWT 解码只用于本地标签和快照匹配，不是签名验证，也不能证明登录、额度或计费状态。
- 日志使用现有 `Diagnostics` 分类，仅记录生命周期、阶段、PID、耗时与错误类型。
- 启动真实 CodeXwitch 会自动保存当前登录凭据；退出/重启真实 Codex 或切换真实账号应有用户授权。普通构建和测试不应执行这些动作。

## 验证与提交

```sh
swift test
bash scripts/build-app.sh
plutil -lint Resources/Info.plist build/CodeXwitch.app/Contents/Info.plist
codesign --verify --strict build/CodeXwitch.app
git diff --check
```

- 从最小相关测试开始。行为修改添加有意义的回归测试；纯文档或简单样式修改检查链接、布局或格式即可，不要求重复完整测试。
- 存储测试使用 `TestDirectory`；生命周期测试注入假 App、查询与 PID 探针，绝不使用真实账号或终止真实 Codex。
- 需要原生 UI 测试截图时，可指定 `CODEXWITCH_RENDER_DIR`；图标测试使用 `CODEXWITCH_ICON_RENDER_DIR`。输出放在仓库外或被忽略的临时目录。
- 测试验证自动行为与假 App，不等于真实登录、刷新令牌、服务端身份或计费验收；如实说明尚未验证的范围。
- 不把环境权限、Xcode 许可或缓存错误当作产品回归；先确认错误发生阶段。
- 保持改动集中，按风险决定是否需要独立审阅。多人或多 agent 协作时明确所有权，不覆盖其他人的改动。

## 资源与发布

- 保持图标的统一几何：正六边形边长 300、相切圆角半径 160、外框 −15°。App 与运行态菜单共用箭头路径。
- 菜单图标为 20 pt 模板 PDF；处理中只旋转内圈，外框固定，遵循系统“减少动态效果”。
- 修改资源时同步矢量源与生成的 PDF / ICNS，并检查打包后的 SwiftPM resource bundle。生成资源是运行所需文件，不应当作临时产物删除。
- `scripts/build-app.sh` 仅构建和打包，不自动安装、启动或操作真实 Codex。
- 发布版本更新 `Resources/Info.plist` 中的短版本和 build 号。当前脚本仅生成本机架构、ad-hoc 签名产物，不宣称完成 Developer ID 签名、公证或其他系统实测。
- 不提交 `.build/`、`build/`、本机工作流缓存、账号数据或排障现场；不擅自推送、公开发布或重写 Git 历史。
