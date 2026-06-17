[简体中文](README.zh-CN.md) / [English](../README.md) / [日本語](README.ja.md) / [한국어](README.ko.md) / [繁體中文](README.zh-TW.md)

# ZeroFS Manager

ZeroFS Manager는 S3 호환 오브젝트 스토리지를 백엔드로 사용하는 외부 ZeroFS CLI 마운트를 설정하고 관리하는 macOS SwiftUI 앱입니다.

## 현재 모드: GitHub 무료/개발 빌드

기본 모드는 `github-dev` 입니다.

- Apple Developer Program이 필요하지 않습니다.
- Developer ID, notarization, stapling, Gatekeeper 공식 신뢰, 정식 `SMAppService` helper 등록은 release-only 입니다.
- 앱은 프로필 저장, 시크릿 마스킹, `zerofs` 감지, endpoint 연결 확인, 실제 마운트 테스트 안내를 지원합니다.
- 기술 사용자는 `sudo`를 수동으로 승인하여 검토된 스크립트로 launchd 파일 설치/삭제, NFS 마운트/언마운트, ZeroFS 실행, 읽기/쓰기 및 성능 테스트를 수행할 수 있습니다.
- GitHub 빌드는 profile별 sudo `LaunchDaemon` 관리를 지원합니다. 앱은 profile 매개변수를 root 소유 config/env 파일에 쓰고, 사용자가 "적용 후 LaunchDaemon 재시작"을 누르면 해당 daemon을 재시작합니다.
- `TeamIdentifier=not set`, `0 valid identities found`, `SMAppServiceErrorDomain Code=3`, `security error -67056` 는 개발 빌드의 S3/ZeroFS CLI 테스트를 막지 않습니다.

## ZeroFS 의존성

ZeroFS는 사용자가 별도로 설치하는 외부 의존성입니다. 앱은 진단을 위해 설치된 `zerofs` 버전을 감지하고 표시하지만, 특정 ZeroFS 바이너리를 포함하거나 고정하지 않습니다.

ZeroFS의 upstream은 [`Barre/ZeroFS`](https://github.com/Barre/ZeroFS) 이며, GitHub는 라이선스를 `AGPL-3.0` 으로 식별합니다. 오픈소스 또는 비영리 배포라고 해서 AGPL 의무가 사라지지는 않습니다. 따라서 이 프로젝트는 ZeroFS를 외부 의존성으로 유지합니다. GitHub Actions는 GUI만 빌드하고 게시하며, 사용자는 upstream에서 ZeroFS를 별도로 설치합니다.

이 저장소는 `zerofs 1.2.6` 으로 검증되었습니다. 이는 현재 테스트 기준일 뿐, 엄격한 런타임 의존성은 아닙니다. 향후 ZeroFS 버전이 설정 형식과 CLI 동작을 유지한다면 사용할 수 있어야 합니다.

## 언어

macOS 앱에는 창 안에서 사용할 수 있는 언어 전환 기능이 포함되어 있습니다. 첫 버전은 English, 简体中文, 繁體中文, 日本語, 한국어를 지원하며 주요 설정, 상태, 의존성 감지, 마운트 테스트 화면을 다룹니다.

## 빌드

```sh
Scripts/package-github-dev.sh
Scripts/inspect-signature.sh "dist/ZeroFS Manager.app"
```

로컬 검사:

```sh
Scripts/verify-local.sh
```

## GitHub Releases

이 저장소에는 GitHub Actions 릴리스 워크플로가 포함되어 있습니다. `v0.1.4` 같은 tag 를 push 하면 ad-hoc GitHub 패키지를 빌드하고 다음 파일을 업로드합니다.

- `ZeroFS-Manager-dev-adhoc.dmg`
- `ZeroFS-Manager-dev-adhoc.zip`

이 Release 산출물은 CI가 생성하므로 git 저장소에 커밋하지 않아야 합니다.

GitHub 개발 DMG를 설치할 때는 먼저 `ZeroFS Manager.app`을 `/Applications`로 드래그하거나 복사한 뒤 `/Applications`에서 실행하세요. 영구 sudo LaunchDaemon profile에는 안정적인 설치된 App 경로가 필요하므로 마운트된 DMG에서 직접 실행하지 마세요.

## 수동 S3 마운트 테스트

Apple 서명 없이도 수동 CLI/debug launchd 경로로 실제 S3/MinIO/R2 마운트, 읽기/쓰기, 용량 표시, 소규모 성능 테스트를 검증할 수 있습니다.

```sh
Scripts/manual-mount-test.sh --env .env.local --delete-env-on-exit
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M
Scripts/manual-install-profile-launchdaemon.sh --env .env.local --delete-env-on-exit
Scripts/manual-uninstall-profile-launchdaemon.sh --profile-id example-profile --mount-point /Volumes/ZeroFS-Example
```

이 경로는 저수준 개발 테스트용이며, 공식 macOS helper 승인 흐름과 동일하지 않습니다.

GitHub 무료 배포판에서는 수동 sudo 경로가 권한 작업을 활성화하는 의도된 방법입니다. 사용자는 macOS 프롬프트를 승인해야 하며, 첫 실행 시 Gatekeeper 경고가 표시될 수 있습니다.

영구 자동 마운트 경로는 plist를 안정적으로 유지하고, 변경되는 profile 매개변수는 `/Library/Application Support/ZeroFSManager/Profiles/<profile-id>/zerofs.toml` 및 root-only `zerofs.env`에 저장합니다. 설치 또는 업데이트 시 검토된 sudo 스크립트는 사용자가 설치한 `zerofs` 바이너리를 같은 root-owned profile runtime 디렉터리로 복사하고, LaunchDaemon은 사용자가 쓸 수 있는 PATH 항목 대신 이 고정 복사본을 실행합니다. endpoint, bucket, prefix, 마운트 디렉터리, 포트, 캐시, 할당량, 자격 증명 또는 ZeroFS 바이너리를 바꾼 뒤에는 앱의 "적용 후 LaunchDaemon 재시작"으로 launchd가 설정을 다시 읽게 합니다.

## 공식 릴리스

`official-release` 는 Developer ID 서명, hardened runtime, notarization, stapling, 공식 `SMAppService` helper 등록을 위해 예약되어 있습니다. Developer ID/notary 설정이 없으면 공식 릴리스 스크립트는 명확하게 건너뜁니다.

## 라이선스

ZeroFS Manager는 Apache License 2.0으로 제공됩니다. ZeroFS 자체는 이 저장소에서 번들링하거나 재배포하지 않으며 upstream 라이선스를 따릅니다.
