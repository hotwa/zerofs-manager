# ZeroFS Manager DMG Design

## Goal

Build `ZeroFS Manager.app`, a distributable macOS application packaged as a DMG that configures, installs, mounts, monitors, and tests ZeroFS-backed S3 filesystems.

The app targets a highest-spec v1 rather than a throwaway local wrapper. It should use the architecture expected for a macOS product: SwiftUI, ServiceManagement, an authorized privileged helper, Keychain-backed secrets, signed/notarizable packaging, and a clean path from one profile to multiple mount profiles.

## Product Scope

The first release manages one active mount profile but exposes the profile concept in the UI. The main window uses the selected Dashboard layout: a Mounts/Profile list on the left and the selected profile's health, configuration, actions, logs, and performance testing on the right.

The data model must support multiple `MountProfile` records from day one. v1 may restrict creation to one active profile, but profile IDs, per-profile service labels, mount paths, ports, logs, reports, and generated config paths must not be hard-coded to a single global name.

The app ships as a GUI-only DMG. It does not embed, download, or redistribute ZeroFS. Users install ZeroFS separately from upstream, and the app detects `zerofs` on `PATH` or common macOS install locations.

## User-Configurable Fields

Each profile stores:

- display name,
- S3 endpoint URL,
- Access Key ID,
- Secret Access Key,
- bucket,
- prefix,
- mount path,
- ZeroFS virtual quota,
- disk cache size,
- memory cache size,
- NFS port,
- RPC port,
- Prometheus metrics port,
- login-after-start auto-mount setting,
- performance test size.

Mount path is user-configurable. The default can be `/Volumes/ZeroFS-<profileName>`.

## Secrets

Keychain is the primary secret store for UI-managed credentials. The app stores the S3 Access Key, S3 Secret Key, and ZeroFS encryption password in the user's Keychain with service/account names derived from the profile ID.

Because the privileged runtime needs credentials outside normal UI code, the privileged helper writes a root-only runtime secret file when installing or updating a profile. The app must treat that file as generated runtime state, not as the source of truth. UI reads secrets from Keychain and asks the helper to sync runtime files when service configuration changes.

No secret value may be written to logs, reports, OpenSpec artifacts, shell command arguments, or world-readable files.

## Privileged Architecture

The main app does not write `/etc`, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`, `/usr/local/sbin`, or `/Volumes` directly.

A privileged helper performs root operations:

- validate the external ZeroFS CLI path,
- generate profile-specific ZeroFS TOML and root-only env files,
- install/register launchd services through the ServiceManagement-supported path,
- start, stop, restart, mount, unmount, and flush profiles,
- read bounded log excerpts,
- report structured service status and mount errors.

The helper exposes a narrow authenticated XPC interface. Every operation validates profile IDs, paths, port ranges, and generated file locations before touching the filesystem.

## Login Auto-Mount

v1 implements login-after-start auto-mount, not pre-login system boot mounting. A Login Item or app-managed agent starts after the user logs in, checks enabled profiles, asks the helper to ensure the service is installed and running, then mounts the configured profile.

If mounting fails, the app shows a macOS alert/notification with:

- profile name,
- failed operation,
- human-readable error,
- recent helper or ZeroFS log excerpt,
- actions to retry, open settings, open logs, or disable auto-mount.

The architecture should leave room for future system-boot mounting, but v1 does not require Keychain access before user login.

## Runtime Layout

Runtime paths are profile-scoped. Exact paths can be refined during implementation, but the design intent is:

- external ZeroFS: user-installed `zerofs` found on `PATH` or a common install path,
- installed helper/runtime area for privileged files,
- generated config under a root-owned profile directory,
- profile logs under a root-owned log path,
- exported reports under a user-selected or app-managed user directory.

The existing hand-built setup at `/etc/zerofs`, `/Library/LaunchDaemons/com.zerofs.lingyuzeng.*`, and `/Volumes/ZeroFS-lingyuzeng` is useful reference behavior, but the product should generate profile-scoped equivalents rather than assuming those exact names.

## Performance Testing

The app includes a performance test UI. The user selects test size, starts the test, sees progress, and gets a report that includes:

- mount status,
- `df` before, after write, and after cleanup,
- write duration and throughput,
- read duration and throughput,
- SHA-256 source/readback comparison,
- cleanup status,
- Prometheus metrics before and after cleanup,
- clear statement that `df` reports ZeroFS configured quota, not real object-store capacity.

The test runner must cleanup remote and local temporary artifacts on failure. Unit tests should cover cleanup behavior without writing 1 GB.

## Packaging and Distribution

The project should produce a DMG containing `ZeroFS Manager.app`.

The build system must support:

- local debug build,
- local unsigned or development-signed DMG for internal testing,
- Developer ID signed app/helper binaries,
- notarization using Apple's notary service,
- stapling the notarization ticket,
- verification with Gatekeeper tooling.

If Developer ID credentials are unavailable, the packaging script should fail clearly for distribution mode while still allowing a local development artifact.

## OpenSpec and Project Location

The project lives at `/Users/lingyuzeng/project/zerofs-manager`.

OpenSpec is the source for the implementation proposal, design, and task list. The first OpenSpec change should cover the distributable v1 architecture and scaffold.

## Non-Goals for v1

- Do not support simultaneous multi-profile mounting in the first UI release.
- Do not download, embed, or redistribute ZeroFS at install time.
- Do not show real MinIO bucket capacity unless a future admin API integration is added.
- Do not store secrets directly in app preferences.
- Do not rely on ad-hoc shell `sudo` prompts as the production permission model.

## Verification Targets

The first implementation should prove:

- SwiftPM package builds,
- app bundle can be assembled,
- embedded ZeroFS binary is absent,
- profile model and validation tests pass,
- Keychain abstraction can be tested with a mock store,
- helper protocol can be tested without root through a mock client,
- packaging scripts produce at least a local DMG,
- OpenSpec validates,
- documentation explains distribution signing and notarization requirements.
