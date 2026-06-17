[简体中文](README.zh-CN.md) / [English](../README.md) / [日本語](README.ja.md) / [한국어](README.ko.md) / [繁體中文](README.zh-TW.md)

# ZeroFS Manager

ZeroFS Manager 是一个 macOS SwiftUI 应用，用于配置和管理基于 S3 兼容对象存储的外部 ZeroFS CLI 挂载。

## 当前模式：GitHub 免费/开发版

默认模式是 `github-dev`。

- 不需要 Apple Developer Program。
- Developer ID、notarization、stapling、Gatekeeper 正式信任和正式 `SMAppService` helper 注册都属于 release-only。
- App 可以保存挂载配置、隐藏敏感信息、检测 `zerofs`、检查 endpoint 连通性，并引导真实挂载测试。
- 技术用户可以手动授权 `sudo`，让免费 GitHub 版通过已审查脚本安装/删除 launchd 文件、挂载/卸载 NFS、运行 ZeroFS，以及执行读写和性能测试。
- GitHub 版支持按 profile 管理 sudo `LaunchDaemon`。App 会把参数写入 root 拥有的 config/env 文件，用户点击“应用并重启 LaunchDaemon”后重启对应 daemon。
- `TeamIdentifier=not set`、`0 valid identities found`、`SMAppServiceErrorDomain Code=3`、`security error -67056` 不会阻塞开发版的 S3/ZeroFS CLI 测试。

## ZeroFS 依赖

ZeroFS 是用户自行安装的外部依赖。App 会检测并显示已安装的 `zerofs` 版本用于诊断，但不会打包或锁定某个 ZeroFS 二进制版本。

ZeroFS 上游是 [`Barre/ZeroFS`](https://github.com/Barre/ZeroFS)，GitHub 识别其许可证为 `AGPL-3.0`。开源或不盈利并不会免除 AGPL 义务。因此本项目继续把 ZeroFS 作为外部依赖：GitHub Actions 只构建和发布 GUI，用户从上游自行安装 ZeroFS。

当前仓库已用 `zerofs 1.2.6` 验证；这是测试基线，不是硬性运行依赖。只要未来 ZeroFS 的配置格式和 CLI 行为兼容，新版本也应该可以使用。

## 多语言

macOS App 内置窗口内语言切换。第一版支持 English、简体中文、繁體中文、日本語、한국어，覆盖主要配置、状态、依赖检测和挂载测试界面。

## 构建

```sh
Scripts/package-github-dev.sh
Scripts/inspect-signature.sh "dist/ZeroFS Manager.app"
```

本地检查：

```sh
Scripts/verify-local.sh
```

## GitHub Releases

仓库包含 GitHub Actions 发布流程。推送 `v0.1.4` 这样的 tag 后，会构建 ad-hoc GitHub 包并上传：

- `ZeroFS-Manager-dev-adhoc.dmg`
- `ZeroFS-Manager-dev-adhoc.zip`

这些 Release 产物由 CI 生成，不应该提交进 git 仓库。

安装 GitHub 开发版 DMG 时，先把 `ZeroFS Manager.app` 拖拽或复制到 `/Applications`，再从 `/Applications` 启动。不要直接从挂载的 DMG 中运行，因为持久 sudo LaunchDaemon profile 需要稳定的已安装 App 路径。

## 手动 S3 挂载测试

在没有 Apple 签名的情况下，可以通过手动 CLI/debug launchd 路径验证真实 S3/MinIO/R2 挂载、读写、容量显示和小型性能测试。

```sh
Scripts/manual-mount-test.sh --env .env.local --delete-env-on-exit
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M
Scripts/manual-install-profile-launchdaemon.sh --env .env.local --delete-env-on-exit
Scripts/manual-uninstall-profile-launchdaemon.sh --profile-id example-profile --mount-point /Volumes/ZeroFS-Example
```

这些路径用于底层开发测试，不等同于正式 macOS helper 授权流程。

对 GitHub 免费分发版来说，手动 sudo 路径是启用特权操作的预期方式。用户仍需要批准 macOS 提示，并理解首次启动时 Gatekeeper 可能会警告。

持久自动挂载路径会保持 plist 稳定，把所有会变化的 profile 参数放在 `/Library/Application Support/ZeroFSManager/Profiles/<profile-id>/zerofs.toml` 和 root-only `zerofs.env`。安装或更新时，经过审查的 sudo 脚本会把用户安装的 `zerofs` 二进制复制到同一个 root-owned profile runtime 目录，LaunchDaemon 执行这个固定副本，而不是用户可写 PATH 里的文件。修改 endpoint、bucket、prefix、挂载目录、端口、缓存、配额、凭据或 ZeroFS 二进制后，在 App 里点击“应用并重启 LaunchDaemon”让 launchd 重新读取配置。

## 正式发布

`official-release` 预留给 Developer ID 签名、hardened runtime、notarization、stapling 和正式 `SMAppService` helper 注册流程。没有 Developer ID/notary 配置时，正式发布脚本会清晰跳过。

## 许可证

ZeroFS Manager 使用 Apache License 2.0。ZeroFS 本体不会被本仓库打包或再分发，仍遵循其上游许可证。
