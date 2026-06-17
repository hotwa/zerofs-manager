[简体中文](README.zh-CN.md) / [English](../README.md) / [日本語](README.ja.md) / [한국어](README.ko.md) / [繁體中文](README.zh-TW.md)

# ZeroFS Manager

ZeroFS Manager は、S3 互換オブジェクトストレージをバックエンドにした外部 ZeroFS CLI マウントを設定・管理する macOS SwiftUI アプリです。

## 現在のモード：GitHub 無料/開発版

既定のモードは `github-dev` です。

- Apple Developer Program は不要です。
- Developer ID、notarization、stapling、Gatekeeper の正式な信頼、正式な `SMAppService` helper 登録は release-only です。
- App はプロファイル保存、シークレットのマスク、`zerofs` 検出、endpoint 疎通確認、実マウントテストの案内を行えます。
- 技術ユーザーは手動で `sudo` を許可し、レビュー済みスクリプト経由で launchd ファイルのインストール/削除、NFS のマウント/アンマウント、ZeroFS の実行、読み書きと性能テストを行えます。
- `TeamIdentifier=not set`、`0 valid identities found`、`SMAppServiceErrorDomain Code=3`、`security error -67056` は、開発版の S3/ZeroFS CLI テストをブロックしません。

## ZeroFS 依存関係

ZeroFS はユーザーが別途インストールする外部依存です。App は診断用にインストール済み `zerofs` のバージョンを検出して表示しますが、特定の ZeroFS バイナリを同梱したり固定したりしません。

このリポジトリは `zerofs 1.2.6` で検証されています。これは現在のテスト基準であり、厳密な実行時依存ではありません。将来の ZeroFS が設定形式と CLI 挙動を維持していれば利用できる想定です。

## ビルド

```sh
Scripts/build-app.sh --configuration release
Scripts/sign-app-adhoc.sh "dist/ZeroFS Manager.app"
Scripts/inspect-signature.sh "dist/ZeroFS Manager.app"
Scripts/package-github-dev.sh
```

ローカルチェック：

```sh
swift build
swift run ZeroFSManagerChecks
```

## GitHub Releases

このリポジトリには GitHub Actions のリリースワークフローがあります。`v0.1.0` のような tag を push すると、ad-hoc GitHub パッケージをビルドして次のファイルをアップロードします。

- `ZeroFS-Manager-dev-adhoc.dmg`
- `ZeroFS-Manager-dev-adhoc.zip`

これらの Release 生成物は CI が作成するため、git リポジトリにはコミットしません。

## 手動 S3 マウントテスト

Apple 署名なしでも、手動 CLI/debug launchd 経路で実際の S3/MinIO/R2 マウント、読み書き、容量表示、小規模性能テストを検証できます。

```sh
Scripts/manual-mount-test.sh --env .env.local --delete-env-on-exit
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M
```

これらの経路は低レベルの開発テスト用であり、正式な macOS helper 認可フローと同等ではありません。

GitHub 無料配布版では、手動 sudo 経路が特権操作を有効にする想定の方法です。ユーザーは macOS のプロンプトを承認する必要があり、初回起動時に Gatekeeper の警告が表示される可能性があります。

## 正式リリース

`official-release` は、Developer ID 署名、hardened runtime、notarization、stapling、正式な `SMAppService` helper 登録のために予約されています。Developer ID/notary 設定がない場合、正式リリース用スクリプトは明確にスキップします。
