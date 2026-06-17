## Context

The current ZeroFS setup proves the operational flow: the installed ZeroFS test baseline (`zerofs 1.2.6` on this Mac) can use the MinIO-compatible endpoint, expose NFS on loopback, mount under `/Volumes`, report a configured 1024 GB quota as about `954Gi`, and pass write/read/checksum/cleanup tests. This version is the validation baseline, not a hard product dependency.

The product goal is to turn that manual setup into a distributable macOS app. The current market-validation phase uses a lower-cost distribution model: the DMG ships only the GUI and management layer, while users install ZeroFS separately from the upstream project. The app detects `zerofs` on `PATH` or common macOS locations, shows the official install command when missing, and calls the external CLI for ZeroFS/NFS management flows.

The project is SwiftPM-first. Apple examples for `SMAppService` commonly assume Xcode targets and copy phases, so this project will need deterministic bundle assembly scripts. That is an explicit design choice, not an accident.

## Goals / Non-Goals

**Goals:**

- Build a SwiftPM-first macOS codebase that can assemble `ZeroFS Manager.app`.
- Model profiles from day one, while v1 enforces one active profile through UI and policy.
- Store user-managed secrets in Keychain and generate root-only runtime secrets only through a privileged helper.
- Use ServiceManagement/`SMAppService` for the production helper registration path where privileged NFS mount operations are required.
- Use a bundled LaunchDaemon plist and helper executable layout compatible with `SMAppService.daemon(plistName:)`, but do not bundle the ZeroFS binary itself.
- Detect external ZeroFS and surface `curl -sSfL https://sh.zerofs.net | sh` when missing.
- Support a GitHub free/dev mode where technical users manually authorize `sudo` for reviewed launchd, mount, unmount, and performance-test scripts without requiring Apple Developer ID.
- Support login-after-start auto-mount and app-visible failure alerts.
- Provide a UI-driven performance test runner and reports.
- Produce local DMG artifacts and a scripted Developer ID signing, notarization, stapling, and verification path.

**Non-Goals:**

- v1 does not support simultaneous multi-profile mounting.
- v1 does not support pre-login boot-time mounting.
- v1 does not download, embed, or redistribute ZeroFS during install.
- v1 does not expose object-store real capacity through MinIO admin APIs.
- v1 does not use legacy `SMJobBless` as the production helper strategy.
- v1 does not expose a generic privileged command execution API.
- GitHub free/dev artifacts do not promise frictionless Gatekeeper acceptance, no-prompt privileged operations, or formal `SMAppService` registration.

## Decisions

### Decision: SwiftPM-first with deterministic bundle scripts

Use SwiftPM for libraries, executables, and tests. Add scripts that assemble `.build` outputs into `ZeroFS Manager.app`, copy resources, embed the helper, embed the LaunchDaemon plist, sign nested app/helper code in the right order, and create GUI-only DMGs.

Alternative considered: use an Xcode project as packaging authority. Xcode is smoother for app bundles, entitlements, ServiceManagement resources, and signing, but the requested workflow explicitly names SwiftPM. Keeping SwiftPM as the source of truth also makes unit tests and CI-like validation simpler.

### Decision: Profile-ready model with one active profile policy

Define `MountProfile` and profile-derived runtime identifiers in the domain layer. The UI shows a Mount/Profile list, but v1 permits only one active editable profile.

Alternative considered: a single global configuration. That would be faster, but it would force later migration when multiple S3 object stores are added.

### Decision: Keychain as primary secret store

The UI stores S3 credentials and the ZeroFS encryption password in Keychain by `ProfileID` and secret kind. The helper can generate root-only runtime env files as derived state when installing or updating the service.

Alternative considered: root-only env files as the source of truth. That matches the manual setup but weakens the app UX and makes secret lifecycle harder to audit from the UI.

### Decision: External ZeroFS dependency

The GUI does not redistribute ZeroFS. It detects an installed `zerofs` binary through `PATH`, `/opt/homebrew/bin`, `/usr/local/bin`, and user-local bin directories. If missing, the UI displays the upstream install command and a re-detect action. The detected ZeroFS version is displayed for diagnostics and compatibility notes, but the app does not pin a specific binary version.

Alternative considered: embed the currently tested ZeroFS binary (`1.2.6`) in the DMG. That lowers install friction but increases licensing, redistribution, update, signing, and support risk. The external-dependency phase is better for market validation.

### Decision: GitHub free mode uses user-authorized sudo workflows

The free GitHub build is allowed to guide users through manual `sudo` authorization for privileged operations. The app can copy commands, open Terminal, and run reviewed scripts for installing/removing launchd files, creating mount directories, mounting/unmounting NFS, starting ZeroFS, flushing, reading logs, and running performance tests.

This covers the practical feature set needed by technical users without Apple Developer ID: real S3 mounting, status detection, capacity display from `df`, read/write validation, performance testing, and manual or semi-automatic launchd startup. It does not remove macOS prompts, Gatekeeper warnings, or the need for user understanding of privileged changes.

Alternative considered: make Developer ID mandatory even for free GitHub distribution. That would improve first-run trust and helper registration but blocks market validation and is unnecessary for technical users who can approve `sudo` manually.

### Decision: Narrow privileged helper protocol for official release

The official-release helper owns privileged operations: generated configs, launchd interaction, mount/unmount, flush, status, and bounded logs. It revalidates all profile IDs, generated paths, ports, labels, mount paths, and external ZeroFS binary paths. It never accepts arbitrary shell commands.

Alternative considered: app-side `sudo` shell execution as the only product path. This is acceptable for the GitHub free/dev track when commands are reviewed, narrow, visible, and user-authorized, but it is not suitable as the long-term official-release helper strategy because authorization, logging, status, and error handling are harder to control.

### Decision: SMAppService bundled LaunchDaemon path is release-only

The official release path uses `SMAppService.daemon(plistName:)` with the LaunchDaemon plist in `ZeroFS Manager.app/Contents/Library/LaunchDaemons/` and the helper executable bundled inside the app. The plist must include a profile-independent helper label, `BundleProgram`, `MachServices` for XPC, and `AssociatedBundleIdentifiers` for System Settings attribution. GitHub free/dev builds must not block real S3 testing on this path.

Alternative considered: directly writing plist files into `/Library/LaunchDaemons`. That remains useful for manual diagnostics but is not the production app install path.

### Decision: Login-after-start auto-mount

v1 auto-mounts after user login. The Login Item starts the app or agent, checks enabled profiles, and calls the helper. If the mount fails, the app shows an alert and notification with structured error details and remediation actions.

Alternative considered: pre-login boot mounting. That would require a system-side secret strategy and a more complex UX for failures that happen before the user session exists.

### Decision: Explicit GitHub free vs official release packaging modes

Packaging supports GitHub free/dev artifacts without Developer ID credentials. Official release mode requires Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper verification. Scripts skip or fail clearly when official credentials are missing, but they must not block github-dev packaging or real S3/ZeroFS validation.

Alternative considered: one packaging script that tries best-effort signing. That hides release failures and makes the artifact's trust level ambiguous.

## Risks / Trade-offs

- [Risk] SwiftPM app bundle assembly can drift from Apple's Xcode-oriented ServiceManagement expectations. -> Mitigation: add tests and script checks for bundle paths, plist names, `BundleProgram`, `MachServices`, embedded helper presence, and absence of embedded ZeroFS.
- [Risk] External ZeroFS installation increases onboarding friction. -> Mitigation: show the official install command, copy button, re-detect button, and clear missing-dependency state in the UI.
- [Risk] SMAppService registration can require user approval or appear disabled in System Settings. -> Mitigation: model helper states explicitly and add UI remediation text for Login Items & Extensions.
- [Risk] Helper launches but XPC fails due to Mach service or signing mismatch. -> Mitigation: make Mach service names deterministic and add launch/connection verification tasks before full ZeroFS operations.
- [Risk] Notarization fails on unsigned nested binaries, missing hardened runtime, or debug entitlements. -> Mitigation: sign nested code first, verify with `codesign --verify --deep --strict --verbose=4`, and inspect entitlements in packaging tasks.
- [Risk] Secrets could leak through logs or command arguments. -> Mitigation: use Keychain as source of truth, generated root-only env files, no secret-bearing command arguments, and tests for redaction/report generation.
- [Risk] Performance tests can leave large files on failure. -> Mitigation: model cleanup as required finalization and test failure cleanup using temp directories before real mounted-volume tests.
- [Risk] User-custom mount paths could target unsafe locations. -> Mitigation: domain validation blocks generated config paths, system directories other than allowed mount roots, path traversal, and profile ID injection.

## Migration Plan

1. Create the SwiftPM scaffold with pure domain targets and tests first.
2. Add mockable protocols for Keychain, helper client, metrics, filesystem, and performance execution.
3. Build the UI against mocks before privileged operations exist.
4. Add bundled helper and LaunchDaemon resources behind scripts that can assemble and inspect the app bundle.
5. Add local helper registration and status flows, then real external ZeroFS CLI invocation.
6. Add DMG packaging in local mode.
7. Add Developer ID signing, notarization, stapling, and release verification.

Rollback during development is local: unregister helper, remove generated launchd/runtime files created by the helper, unmount mounted profiles, and delete local build artifacts. Runtime secrets and S3-backed ZeroFS data must be deleted only through explicit user action.

## Open Questions

- Whether v1 should opt out of App Sandbox for the main app/helper pair or prototype a sandboxed pair. The initial task should validate this with `SMAppService` before locking entitlements.
- Whether final distribution should sign the DMG itself in addition to signing and notarizing the app payload.
- Whether a future universal binary is required for Intel Macs. The design should not block it, but v1 targets Apple Silicon first.
