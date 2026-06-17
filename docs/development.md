# ZeroFS Manager Local Development

## Distribution Modes

### GitHub-style dev build

`github-dev` is the default mode. It is free, does not require Apple Developer Program membership, and is intended for development or technical-user testing.

In this mode:

- ad-hoc signing is allowed,
- `TeamIdentifier=not set` is expected,
- `spctl` can fail or be inconclusive,
- `SMAppService` privileged helper registration is not triggered automatically,
- release-only login auto-mount is disabled,
- real S3/MinIO/R2 testing goes through manual CLI, debug launchd scripts, or the sudo profile `LaunchDaemon` path.

### Manual CLI / debug launchd test

Manual scripts validate the lower-level ZeroFS behavior: endpoint reachability, real mount, write/read/checksum, `df`, flush/sync, cleanup, and small performance tests.

These scripts do not prove the official macOS helper authorization path.

### Official Developer ID release

`official-release` is reserved for Apple Developer Program distribution: Developer ID Application signing, hardened runtime, notarization, stapling, Gatekeeper verification, and formal `SMAppService` helper registration.

Missing Developer ID or notary configuration must not block `github-dev` builds.

## Build And Verify

```sh
cd <repo-root>
Scripts/verify-local.sh
```

This runs:

- `swift build`
- `swift run ZeroFSManagerChecks`
- app bundle assembly into `dist/ZeroFS Manager.app`
- bundle layout and strict local code-signature verification
- `openspec validate build-distributable-zerofs-manager --strict`

This machine has Apple Command Line Tools but not the full Xcode XCTest runtime, so the scaffold uses `ZeroFSManagerChecks` as the local verification executable.

## Local App Bundle

```sh
Scripts/build-app.sh
```

ZeroFS is an external dependency. The app detects `zerofs` on `PATH` and common install locations at runtime.

If ZeroFS is missing, install it with:

```sh
curl -sSfL https://sh.zerofs.net | sh
```

The current local validation baseline is `zerofs 1.2.6`. This is recorded for diagnostics only; the app does not bundle or pin that version, and compatible upstream ZeroFS releases should be detected normally.

The assembled bundle contains:

- `Contents/MacOS/ZeroFSManagerApp`
- `Contents/MacOS/ZeroFSPrivilegedHelper`
- `Contents/Library/LaunchDaemons/com.zerofs.manager.helper.plist`
- resource templates for profile launchd jobs and ZeroFS runtime config

The assembled bundle intentionally does not contain `Contents/Resources/zerofs/zerofs`.

`Scripts/build-app.sh` ad-hoc signs the assembled bundle so local verification catches broken resource seals such as `-67056`. This is only a local development signature. It is not a Developer ID signature and does not replace notarization for public distribution.

## GitHub-style Dev Package

```sh
Scripts/package-github-dev.sh
Scripts/inspect-signature.sh "dist/ZeroFS Manager.app"
```

The outputs are:

- `dist/ZeroFS Manager.app`
- `dist/ZeroFS-Manager-dev-adhoc.zip`
- `dist/ZeroFS-Manager-dev-adhoc.dmg`

This artifact is intentionally a GitHub-style development build. It contains only the GUI and helper scaffold; users install ZeroFS separately. It is not Developer ID signed and is not notarized.

## Helper Approval Flow

Production helper registration is release-only. It uses macOS ServiceManagement and can require user approval in:

`System Settings > General > Login Items & Extensions`

In `github-dev`, the app must not automatically call `SMAppService.register()`. If the user tries to install the helper or enable auto mount, the app should point to manual CLI/debug launchd testing instead of failing on Apple signing state.

## Login Auto-Mount Flow

The app-managed login-start flow is release-only. In `official-release`, when `ZeroFS Manager.app` starts and the active profile has `Auto Mount = After Login`, the app:

- detects the external `zerofs` CLI
- checks helper registration, service state, mount state, and metrics reachability
- starts the profile service when needed
- mounts when the service is running but the NFS mount is absent
- surfaces helper unavailable and mount failures through the retry/settings/logs/disable-auto-mount failure panel

In `github-dev`, app startup only performs non-privileged checks: ZeroFS detection, endpoint reachability, profile validation state, and signing/mode display.

## GitHub Free Manual Sudo Flow

The GitHub free/dev build can support most practical features when the user manually authorizes `sudo` for reviewed scripts:

- install or remove launchd plist files for a ZeroFS profile
- create and validate mount directories under `/Volumes`
- start or stop the external `zerofs` process
- mount or unmount the local NFS export
- run write/read/checksum and performance tests
- inspect `df`, mount table state, and bounded logs

This path is intended for technical users. It is not equivalent to Developer ID notarization or formal `SMAppService` helper registration, and macOS may still show Gatekeeper or administrator-password prompts.

For persistent auto-mount without Developer ID, use the profile daemon scripts:

```sh
Scripts/manual-install-profile-launchdaemon.sh --env .env.local --delete-env-on-exit
Scripts/manual-uninstall-profile-launchdaemon.sh --profile-id example-profile --mount-point /Volumes/ZeroFS-Example
```

The best-practice layout is a stable pair of plist files under `/Library/LaunchDaemons` plus dynamic profile config under `/Library/Application Support/ZeroFSManager/Profiles/<profile-id>`. The runtime plist runs `run-zerofs.sh`; the mount plist runs `mount-zerofs.sh`. All user-adjustable values such as endpoint, bucket, prefix, mount directory, ports, cache, quota, and credentials are written to `zerofs.toml` and root-only `zerofs.env`. During install/update, the sudo script stages the user-installed `zerofs` binary into the root-owned profile runtime directory and LaunchDaemon jobs execute that fixed copy. After a profile parameter or the ZeroFS binary changes, the app opens Terminal for the sudo installer again, which rewrites config/env, bootouts existing jobs by plist path and label, bootstraps them, and kickstarts the matching profile.

If background reliability probes are enabled, the same sudo installer also stages `ZeroFSProbeTool`, writes `probe-zerofs.sh`, and manages `com.zerofs.manager.profile.<profile-id>.probe`. Probe results are sanitized JSON under `/Library/Application Support/ZeroFSManager/ProbeResults/<profile-id>/`; secrets remain only in the root-only runtime env file.

## Reliability Probe Testing

Reliability probes are default-off. App-open scheduling runs only while the GUI is open and never queues missed runs after sleep. Background scheduling requires the sudo LaunchDaemon flow.

Each probe writes a small hidden temporary file through the mounted ZeroFS filesystem, reads it back, verifies SHA-256, captures `df` and optional metrics, and removes the temporary files. This creates real object-storage/network traffic proportional to the configured size and interval. Green means small-file write/read/checksum succeeded; yellow indicates degraded or slow behavior; red indicates failure, checksum mismatch, cleanup failure, or missing mount. It does not report real provider-side remaining capacity.

## Manual Real Mount Testing

Create a local env file:

```sh
ZEROFS_BIN=/usr/local/bin/zerofs
ZEROFS_MOUNT_POINT=/Volumes/ZeroFS-Test
S3_ENDPOINT=https://example-s3.local
S3_BUCKET=example-bucket
S3_REGION=us-east-1
S3_ACCESS_KEY=...
S3_SECRET_KEY=...
ZEROFS_PASSWORD=...
```

Then run:

```sh
Scripts/manual-mount-test.sh --env .env.local --delete-env-on-exit
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M
```

Use `--confirm-large-test` for large tests such as `--size 1024M`.
Use `--allow-non-zerofs-mount` only for an intentional scratch volume that is safe to write, clean up, and unmount.

## Rollback During Development

Use the diagnostic script first:

```sh
Scripts/diagnose-helper.sh
```

Manual cleanup during development may include:

- stop any generated ZeroFS launchd job
- unmount the selected mount path
- remove generated runtime files under `/Library/Application Support/ZeroFSManager`
- remove generated logs under `/Library/Logs/ZeroFSManager`
- delete local build artifacts under `dist/`

Do not delete object-store data unless the user explicitly requests it.
