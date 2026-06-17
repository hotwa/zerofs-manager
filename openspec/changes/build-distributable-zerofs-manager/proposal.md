## Why

ZeroFS can already be configured manually on this Mac, but the current workflow requires terminal commands, root-owned files, launchd setup, and hand-written performance tests. This change turns that proven workflow into a highest-spec macOS product: a SwiftUI DMG app with profile-based configuration, Keychain-backed secrets, a privileged helper, login auto-mount, failure alerts, performance reports, and a distribution-ready signing/notarization path.

This is intentionally not a throwaway sudo-script MVP. The first implementation should establish the product architecture that can later support multiple S3/ZeroFS mounts without rewriting the permission model or UI shell.

## What Changes

- Create a SwiftPM-first macOS project for `ZeroFS Manager.app`.
- Add a Dashboard + Mount/Profile list UI where v1 shows profile concepts while enforcing one active profile.
- Ship a GUI-only DMG, detect a user-installed external `zerofs` CLI, and show the official install command when missing.
- Store profile secrets primarily in macOS Keychain and generate root-only runtime secret files only through the helper.
- Add a privileged helper boundary for root operations, launchd management, mount/unmount, flush, bounded log access, and runtime file generation.
- Add login-after-start auto-mount and app-visible failure alerts for mount/service errors.
- Add a UI-driven performance test runner with write/read/checksum/cleanup/report behavior.
- Add local DMG packaging and a Developer ID signing, notarization, stapling, and Gatekeeper verification path.
- Add tests for domain validation, profile-scoped path derivation, helper protocol consumers, launchd plist generation, performance cleanup, and report generation.

## Capabilities

### New Capabilities

- `profile-management`: Mount profile modeling, one-active-profile v1 policy, validation, profile-scoped runtime names, and UI-visible configuration fields.
- `secret-storage`: Keychain-backed secret storage and safe synchronization to root-only runtime secret files.
- `privileged-helper`: ServiceManagement/XPC helper boundary for privileged ZeroFS runtime, launchd, mount, unmount, flush, and logs.
- `login-auto-mount`: Login-after-start service check, automatic mount, status monitoring, and failure alert behavior.
- `performance-testing`: UI-driven performance tests with throughput, checksum, cleanup, metrics, and report export.
- `packaging-distribution`: GUI-only app bundle assembly, external ZeroFS dependency verification, DMG creation, Developer ID signing, notarization, stapling, and local fallback behavior.

### Modified Capabilities

None. This is a new project with no existing OpenSpec capabilities.

## Impact

- Adds SwiftPM package structure for app, domain, helper client, privileged helper, launchd generation, secrets, performance testing, UI, and packaging support.
- Adds app bundle and DMG build scripts.
- Introduces macOS-specific dependencies: SwiftUI, AppKit where required, Security/Keychain, ServiceManagement, XPC, launchd, and Apple signing/notarization tooling.
- Requires manual macOS approval for helper registration and Developer ID credentials for distributable signed/notarized DMGs.
- Security constraints: no secrets in logs, reports, OpenSpec files, command arguments, or world-readable files; the UI process must never be trusted for privileged filesystem paths or command execution.

## Non-Goals

- Do not implement simultaneous multi-profile mounting in v1, even though the model and UI are profile-ready.
- Do not download, embed, or redistribute ZeroFS in the GUI DMG.
- Do not expose real MinIO bucket capacity unless a future admin API integration is added.
- Do not rely on raw interactive `sudo` prompts as the production permission model.
- Do not add a generic privileged “run command” API.
