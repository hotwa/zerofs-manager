[简体中文](README.zh-CN.md) / [English](../README.md) / [日本語](README.ja.md) / [한국어](README.ko.md) / [繁體中文](README.zh-TW.md)

# ZeroFS Manager

ZeroFS Manager 是一個 macOS SwiftUI 應用程式，用於設定和管理基於 S3 相容物件儲存的外部 ZeroFS CLI 掛載。

## 目前模式：GitHub 免費/開發版

預設模式是 `github-dev`。

- 不需要 Apple Developer Program。
- Developer ID、notarization、stapling、Gatekeeper 正式信任和正式 `SMAppService` helper 註冊都屬於 release-only。
- App 可以保存掛載設定、遮蔽敏感資訊、偵測 `zerofs`、檢查 endpoint 連通性，並引導真實掛載測試。
- 技術使用者可以手動授權 `sudo`，讓免費 GitHub 版透過已審查腳本安裝/移除 launchd 檔案、掛載/卸載 NFS、執行 ZeroFS，以及執行讀寫和效能測試。
- `TeamIdentifier=not set`、`0 valid identities found`、`SMAppServiceErrorDomain Code=3`、`security error -67056` 不會阻塞開發版的 S3/ZeroFS CLI 測試。

## ZeroFS 依賴

ZeroFS 是使用者自行安裝的外部依賴。App 會偵測並顯示已安裝的 `zerofs` 版本用於診斷，但不會打包或鎖定某個 ZeroFS 二進位版本。

ZeroFS 上游是 [`Barre/ZeroFS`](https://github.com/Barre/ZeroFS)，GitHub 識別其授權為 `AGPL-3.0`。開源或不營利並不會免除 AGPL 義務。因此本專案繼續把 ZeroFS 作為外部依賴：GitHub Actions 只建置和發布 GUI，使用者從上游自行安裝 ZeroFS。

目前倉庫已用 `zerofs 1.2.6` 驗證；這是測試基線，不是硬性執行依賴。只要未來 ZeroFS 的設定格式和 CLI 行為相容，新版本也應該可以使用。

## 多語言

macOS App 內建視窗內語言切換。第一版支援 English、简体中文、繁體中文、日本語、한국어，覆蓋主要設定、狀態、依賴偵測和掛載測試介面。

## 建置

```sh
Scripts/build-app.sh --configuration release
Scripts/sign-app-adhoc.sh "dist/ZeroFS Manager.app"
Scripts/inspect-signature.sh "dist/ZeroFS Manager.app"
Scripts/package-github-dev.sh
```

本機檢查：

```sh
swift build
swift run ZeroFSManagerChecks
```

## GitHub Releases

倉庫包含 GitHub Actions 發布流程。推送 `v0.1.0` 這類 tag 後，會建置 ad-hoc GitHub 套件並上傳：

- `ZeroFS-Manager-dev-adhoc.dmg`
- `ZeroFS-Manager-dev-adhoc.zip`

這些 Release 產物由 CI 產生，不應提交進 git 倉庫。

## 手動 S3 掛載測試

在沒有 Apple 簽名的情況下，可以透過手動 CLI/debug launchd 路徑驗證真實 S3/MinIO/R2 掛載、讀寫、容量顯示和小型效能測試。

```sh
Scripts/manual-mount-test.sh --env .env.local --delete-env-on-exit
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M
```

這些路徑用於底層開發測試，不等同於正式 macOS helper 授權流程。

對 GitHub 免費分發版來說，手動 sudo 路徑是啟用特權操作的預期方式。使用者仍需要批准 macOS 提示，並理解首次啟動時 Gatekeeper 可能會警告。

## 正式發布

`official-release` 預留給 Developer ID 簽名、hardened runtime、notarization、stapling 和正式 `SMAppService` helper 註冊流程。沒有 Developer ID/notary 設定時，正式發布腳本會清晰跳過。
