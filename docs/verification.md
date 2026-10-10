# 验证范围

最近验证版本：**0.1.6（build 7）**，日期：2026-10-10。

## 已验证

- Apple Silicon 开发环境中的 `swift test`：51 项通过，0 失败。
- Release `.app` 打包、源/产物 `Info.plist` 检查、ad-hoc 签名 strict 验证。
- 凭据解析、身份区分、自动保存、刷新、删除排除、权限及写入失败边界。
- 假 App 下的操作顺序、拒绝退出/超时、停止后重试启动、重复操作禁用。
- AppKit 旧对象退出状态滞后、App 列表短暂为空、原 PID 仍存活及失效 PID 包装对象等回归场景。
- 原生菜单/设置控件、应用名称、版本标签布局与四种 20 pt 模板图标绘制。
- 内圈动画改变处理符号时，外框保持固定。
- 0.1.5 已在本机启动；0.1.6 的应用图标资源通过独立的已迁移 App fixture 验证，未为本次发行准备操作真实账号。
- 使用实际资源加载代码与打包资源，将测试 App 移到新目录，强制 `Bundle.module` 回退失败，仍能加载全部四种图标；证明标准 App 资源目录的显式查找有效。
- 0.1.6 应用包内的 MIT 文本与根目录 LICENSE 相同。

测试使用虚构凭据、临时目录和假 App；退出探针仅使用专用测试 bundle。
这些结果不证明真实服务端登录或计费身份，也不构成第三方安全审计。

## 尚未覆盖

- macOS 13 最低系统版本实机和 Intel 构建/运行。
- 全新用户环境、不同 Codex 版本下的完整登录与账号切换兼容矩阵。
- 刷新令牌复用、登录授权过期与服务端账号/计费归属。
- 多个共用认证的客户端之间的同步；这不属于当前支持范围。
- 实机操作过程中切换系统“减少动态效果”设置。
- Developer ID 签名、公证和公开发行流程。

用户曾在开发机手动确认账号切换行为正常；不将单次确认扩展为全部兼容性或安全保证。

## 如何复验

在 macOS 项目根目录运行 `swift test` 和 `bash scripts/build-app.sh`。
具体检查命令与真实账号操作边界见 [AGENTS.md](../AGENTS.md)。

修改行为后应更新相关测试；修改支持范围或发行流程时同步更新本文件与 README。

## CI

工作流使用 `macos-15`，执行完整测试、Release 打包、plist/签名/许可证/图标资源检查，并上传应用压缩包。官方 Actions 固定为完整提交 SHA，权限为只读，未设置发布或签名凭据。

已通过 actionlint 检查及本机等价构建步骤验证；尚未配置 GitHub remote 或执行 hosted CI，第一次推送后仍需检查实际运行结果。CI 默认工具链中的旧版 SwiftPM 资源查找差异依据 [SwiftPM 6.1.2 源码](https://github.com/swiftlang/swift-package-manager/blob/swift-6.1.2-RELEASE/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift)核对，并通过上述目录迁移测试覆盖。
