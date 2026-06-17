[简体中文](README.zh-CN.md) / [English](../README.md) / [日本語](README.ja.md) / [한국어](README.ko.md) / [繁體中文](README.zh-TW.md)

# ZeroFS Manager

ZeroFS Manager は、S3 互換オブジェクトストレージをバックエンドにした外部 ZeroFS CLI マウントを設定・管理する macOS SwiftUI アプリです。

## 現在のモード：GitHub 無料/開発版

既定のモードは `github-dev` です。

- Apple Developer Program は不要です。
- Developer ID、notarization、stapling、Gatekeeper の正式な信頼、正式な `SMAppService` helper 登録は release-only です。
- App はプロファイル保存、シークレットのマスク、`zerofs` 検出、endpoint 疎通確認、実マウントテストの案内を行えます。
- 技術ユーザーは手動で `sudo` を許可し、レビュー済みスクリプト経由で launchd ファイルのインストール/削除、NFS のマウント/アンマウント、ZeroFS の実行、読み書きと性能テストを行えます。
- GitHub ビルドは profile ごとの sudo `LaunchDaemon` 管理に対応します。App は profile パラメータを root 所有の config/env に書き込み、ユーザーが「適用して LaunchDaemon を再起動」を押すと対応する daemon を再起動します。
- `TeamIdentifier=not set`、`0 valid identities found`、`SMAppServiceErrorDomain Code=3`、`security error -67056` は、開発版の S3/ZeroFS CLI テストをブロックしません。

## ZeroFS 依存関係

ZeroFS はユーザーが別途インストールする外部依存です。App は診断用にインストール済み `zerofs` のバージョンを検出して表示しますが、特定の ZeroFS バイナリを同梱したり固定したりしません。

ZeroFS の上流は [`Barre/ZeroFS`](https://github.com/Barre/ZeroFS) で、GitHub はライセンスを `AGPL-3.0` と識別しています。オープンソースまたは非営利の配布でも AGPL の義務はなくなりません。そのため、このプロジェクトでは ZeroFS を外部依存のままにし、GitHub Actions は GUI のみをビルドして公開します。ユーザーは ZeroFS を上流から別途インストールします。

このリポジトリは `zerofs 1.2.6` で検証されています。これは現在のテスト基準であり、厳密な実行時依存ではありません。将来の ZeroFS が設定形式と CLI 挙動を維持していれば利用できる想定です。

## 言語

macOS App はウィンドウ内の言語切り替えを備えています。最初の版では English、简体中文、繁體中文、日本語、한국어 をサポートし、主要な設定、状態、依存関係検出、マウントテスト画面をカバーします。

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
Scripts/manual-install-profile-launchdaemon.sh --env .env.local --delete-env-on-exit
Scripts/manual-uninstall-profile-launchdaemon.sh --profile-id example-profile --mount-point /Volumes/ZeroFS-Example
```

これらの経路は低レベルの開発テスト用であり、正式な macOS helper 認可フローと同等ではありません。

GitHub 無料配布版では、手動 sudo 経路が特権操作を有効にする想定の方法です。ユーザーは macOS のプロンプトを承認する必要があり、初回起動時に Gatekeeper の警告が表示される可能性があります。

永続的な自動マウント経路では plist を安定させ、変更される profile パラメータは `/Library/Application Support/ZeroFSManager/Profiles/<profile-id>/zerofs.toml` と root-only `zerofs.env` に保存します。endpoint、bucket、prefix、マウント先、ポート、キャッシュ、クォータ、認証情報を変更した後は、App の「適用して LaunchDaemon を再起動」で launchd に設定を再読み込みさせます。

## 正式リリース

`official-release` は、Developer ID 署名、hardened runtime、notarization、stapling、正式な `SMAppService` helper 登録のために予約されています。Developer ID/notary 設定がない場合、正式リリース用スクリプトは明確にスキップします。

## ライセンス

ZeroFS Manager は Apache License 2.0 の下で提供されます。ZeroFS 自体はこのリポジトリでは同梱または再配布されず、上流のライセンスに従います。
