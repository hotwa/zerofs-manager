[简体中文](README.zh-CN.md) / [English](../README.md) / [日本語](README.ja.md) / [한국어](README.ko.md) / [繁體中文](README.zh-TW.md)

# ZeroFS Manager

ZeroFS Manager 是一個 macOS SwiftUI 應用程式，用於設定和管理基於 S3 相容物件儲存的外部 ZeroFS CLI 掛載。

## 目前模式：GitHub 免費/開發版

預設模式是 `github-dev`。

- 不需要 Apple Developer Program。
- Developer ID、notarization、stapling、Gatekeeper 正式信任和正式 `SMAppService` helper 註冊都屬於 release-only。
- App 可以保存掛載設定、遮蔽敏感資訊、偵測 `zerofs`、檢查 endpoint 連通性，並引導真實掛載測試。
- 技術使用者可以手動授權 `sudo`，讓免費 GitHub 版透過已審查腳本安裝/移除 launchd 檔案、掛載/卸載 NFS、執行 ZeroFS，以及執行讀寫和效能測試。
- GitHub 版支援按 profile 管理 sudo `LaunchDaemon`。App 會把參數寫入 root 擁有的 config/env 檔案，使用者點選「套用並重啟 LaunchDaemon」後重啟對應 daemon。
- `TeamIdentifier=not set`、`0 valid identities found`、`SMAppServiceErrorDomain Code=3`、`security error -67056` 不會阻塞開發版的 S3/ZeroFS CLI 測試。

## ZeroFS 依賴

ZeroFS 是使用者自行安裝的外部依賴。App 會偵測並顯示已安裝的 `zerofs` 版本用於診斷，但不會打包或鎖定某個 ZeroFS 二進位版本。

ZeroFS 上游是 [`Barre/ZeroFS`](https://github.com/Barre/ZeroFS)，GitHub 識別其授權為 `AGPL-3.0`。開源或不營利並不會免除 AGPL 義務。因此本專案繼續把 ZeroFS 作為外部依賴：GitHub Actions 只建置和發布 GUI，使用者從上游自行安裝 ZeroFS。

目前倉庫已用 `zerofs 1.2.6` 驗證；這是測試基線，不是硬性執行依賴。只要未來 ZeroFS 的設定格式和 CLI 行為相容，新版本也應該可以使用。

## 多語言

macOS App 內建視窗內語言切換。第一版支援 English、简体中文、繁體中文、日本語、한국어，覆蓋主要設定、狀態、依賴偵測和掛載測試介面。

## 建置

```sh
Scripts/package-github-dev.sh
Scripts/inspect-signature.sh "dist/ZeroFS Manager.app"
```

本機檢查：

```sh
Scripts/verify-local.sh
```

## GitHub Releases

倉庫包含 GitHub Actions 發布流程。推送 `v0.1.4` 這類 tag 後，會建置 ad-hoc GitHub 套件並上傳：

- `ZeroFS-Manager-dev-adhoc.dmg`
- `ZeroFS-Manager-dev-adhoc.zip`

這些 Release 產物由 CI 產生，不應提交進 git 倉庫。

安裝 GitHub 開發版 DMG 時，先把 `ZeroFS Manager.app` 拖曳或複製到 `/Applications`，再從 `/Applications` 啟動。不要直接從掛載的 DMG 中執行，因為持久 sudo LaunchDaemon profile 需要穩定的已安裝 App 路徑。

## 手動 S3 掛載測試

在沒有 Apple 簽名的情況下，可以透過手動 CLI/debug launchd 路徑驗證真實 S3/MinIO/R2 掛載、讀寫、容量顯示和小型效能測試。

```sh
Scripts/manual-mount-test.sh --env .env.local --delete-env-on-exit
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M
Scripts/manual-install-profile-launchdaemon.sh --env .env.local --delete-env-on-exit
Scripts/manual-uninstall-profile-launchdaemon.sh --profile-id example-profile --mount-point /Volumes/ZeroFS-Example
```

這些路徑用於底層開發測試，不等同於正式 macOS helper 授權流程。

對 GitHub 免費分發版來說，手動 sudo 路徑是啟用特權操作的預期方式。使用者仍需要批准 macOS 提示，並理解首次啟動時 Gatekeeper 可能會警告。

持久自動掛載路徑會保持 plist 穩定，把所有會變化的 profile 參數放在 `/Library/Application Support/ZeroFSManager/Profiles/<profile-id>/zerofs.toml` 和 root-only `zerofs.env`。安裝或更新時，經過審查的 sudo 腳本會把使用者安裝的 `zerofs` 二進位複製到同一個 root-owned profile runtime 目錄，LaunchDaemon 執行這個固定副本，而不是使用者可寫 PATH 裡的檔案。修改 endpoint、bucket、prefix、掛載目錄、連接埠、快取、配額、憑據或 ZeroFS 二進位後，在 App 裡點選「套用並重啟 LaunchDaemon」讓 launchd 重新讀取設定。

## 正式發布

`official-release` 預留給 Developer ID 簽名、hardened runtime、notarization、stapling 和正式 `SMAppService` helper 註冊流程。沒有 Developer ID/notary 設定時，正式發布腳本會清晰跳過。

## 授權

ZeroFS Manager 使用 Apache License 2.0。ZeroFS 本體不會被本倉庫打包或再分發，仍遵循其上游授權。
