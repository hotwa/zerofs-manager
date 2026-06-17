## 1. Project Scaffold

- [x] 1.1 Create SwiftPM package with targets for app, UI, domain, secrets, helper client, privileged helper, launchd, performance, and packaging support.
- [x] 1.2 Add local verification coverage for domain, secrets, helper client, launchd generation, and performance workflow through `ZeroFSManagerChecks` because this Command Line Tools environment lacks XCTest/Swift Testing modules.
- [x] 1.3 Add script directory and initial scripts for build, bundle assembly, local DMG packaging, and distribution packaging.
- [x] 1.4 Add resource layout for external ZeroFS dependency guidance, LaunchDaemon plist templates, app metadata, and entitlements.
- [x] 1.5 Add CI-like local verification script that runs `swift build`, `ZeroFSManagerChecks`, bundle checks, and OpenSpec validation.

## 2. Domain and Profile Management

- [x] 2.1 Implement `ProfileID`, `MountProfile`, `PortSet`, `CacheSettings`, `Quota`, `MountPath`, and `AutoMountPolicy` in a UI-free domain target.
- [x] 2.2 Implement validation for endpoint URL, bucket, prefix, mount path, quota, cache sizes, duplicate ports, and allowed port ranges.
- [x] 2.3 Implement profile-scoped runtime path, service label, Mach service name, log path, and report path derivation.
- [x] 2.4 Implement one-active-profile v1 policy while keeping the storage model capable of multiple profiles.
- [x] 2.5 Add local checks for valid profile creation, unsafe mount path rejection, invalid object storage fields, duplicate ports, profile rename stability, and future profile non-collision.

## 3. Secret Storage

- [x] 3.1 Define `SecretStore` protocol and secret key types for S3 Access Key ID, S3 Secret Access Key, and ZeroFS encryption password.
- [x] 3.2 Implement `InMemorySecretStore` for tests and SwiftUI previews.
- [x] 3.3 Implement `KeychainSecretStore` using the Security framework with profile-derived service/account names.
- [x] 3.4 Implement secret redaction helpers for errors, logs, reports, and debug output.
- [x] 3.5 Add local checks proving secrets are redacted and not written into profile JSON, launchd plist, or bundle fixtures.

## 4. Helper Client Contract

- [x] 4.1 Define `PrivilegedHelperClient` protocol with install/update, sync runtime secrets, start, stop, restart, mount, unmount, flush, status, and bounded log operations.
- [x] 4.2 Define typed request, response, status, and error models shared between app and helper.
- [x] 4.3 Implement `MockPrivilegedHelperClient` for UI previews, tests, and failure injection.
- [x] 4.4 Add local checks for helper unavailable, requires approval, disabled, service running but unmounted, stale mount, and mount failure states.

## 5. SwiftUI App Shell and UX

- [x] 5.1 Build the Dashboard + Mount/Profile list shell with one visible profile and a disabled or explanatory add-profile path for v1.
- [x] 5.2 Build profile settings UI for endpoint, bucket, prefix, mount path, quota, cache sizes, ports, auto-mount, and performance test size.
- [x] 5.3 Build status cards for helper registration, ZeroFS process, mount state, metrics reachability, quota display, and last error.
- [x] 5.4 Build mount failure alert and notification state with retry, settings, logs, and disable-auto-mount actions.
- [x] 5.5 Wire the UI to mock helper, mock secret store, and sample profile data before enabling privileged operations.
- [x] 5.6 Add ZeroFS CLI dependency detection, missing-state install command, copy command, and re-detect UI.
- [x] 5.7 Add GitHub-style dev mode banner, signing TeamIdentifier display, endpoint reachability check, and manual test guidance actions.

## 6. Launchd and SMAppService Resources

- [x] 6.1 Implement deterministic LaunchDaemon plist generation and validation for bundled `SMAppService.daemon(plistName:)` registration.
- [x] 6.2 Include `Label`, `BundleProgram`, `MachServices`, and `AssociatedBundleIdentifiers` in the bundled helper plist.
- [x] 6.3 Add local checks that verify plist filenames include `.plist`, helper paths are bundle-relative, and plist data contains no secrets.
- [x] 6.4 Add status mapping for ServiceManagement states including not registered, requires approval, enabled, disabled, not found, running, stopped, and failed.
- [x] 6.5 Add UI remediation text for System Settings > General > Login Items & Extensions approval. Requires manual macOS approval during official release integration testing.
- [x] 6.6 Gate `SMAppService.register()` behind `official-release` mode so `github-dev` never auto-registers the helper.

## 7. Privileged Helper Implementation

- [x] 7.1 Create the privileged helper executable target and minimal XPC/Mach service entrypoint.
- [x] 7.2 Implement helper-side revalidation for profile ID, generated paths, mount paths, service labels, port sets, and runtime roots.
- [x] 7.3 Implement runtime file generation for ZeroFS TOML and root-only env files without logging secrets.
- [x] 7.4 Implement external ZeroFS binary path modeling for helper-managed runtime operations without embedding or redistributing ZeroFS.
- [x] 7.5 Implement helper operations for start, stop, restart, mount, unmount, flush, status, and bounded log reads.
- [x] 7.6 Add integration tests or manual test scripts for helper registration and XPC connectivity. Requires macOS authorization and may require signing setup.

## 8. Login Auto-Mount

- [x] 8.1 Add Login Item or app-managed login-start flow for after-login auto-mount.
- [x] 8.2 On login start, check the active profile, helper state, service state, mount state, and metrics reachability separately.
- [x] 8.3 Implement auto-mount retry and failure surfacing through app alerts and notifications.
- [x] 8.4 Add tests for auto-mount disabled, helper unavailable, service running but unmounted, and mount failure alert content.
- [x] 8.5 Disable login auto-mount in `github-dev` mode so startup only performs non-privileged checks.

## 9. Performance Testing

- [x] 9.1 Implement performance test runner with configurable test size, write, helper flush, readback, SHA-256 compare, cleanup, and report generation.
- [x] 9.2 Add `df` snapshots before write, after write, and after cleanup, with explicit quota semantics text.
- [x] 9.3 Add Prometheus metrics collection before cleanup and after settled cleanup.
- [x] 9.4 Add cleanup-on-failure behavior for write failure, read failure, checksum failure, cancellation, and helper flush failure.
- [x] 9.5 Add local checks using temp directories and mock helper clients without requiring ZeroFS, S3, root, or 1 GB writes.
- [x] 9.6 Add an optional manual integration test profile that can run against a real mounted ZeroFS volume.
- [x] 9.7 Add manual real-mount and 128M default performance scripts for S3/MinIO/R2 testing without Apple Developer ID.

## 10. Bundle Assembly and Local DMG

- [x] 10.1 Implement `build-app.sh` to build SwiftPM products and assemble `ZeroFS Manager.app` with expected bundle layout.
- [x] 10.2 Add bundle verification that ZeroFS is not embedded and is treated as an external dependency.
- [x] 10.3 Add bundle layout verification for main executable, helper executable, LaunchDaemon plist, resources, Info.plist, and entitlements.
- [x] 10.4 Implement `package-dmg.sh` for local unsigned or development-signed DMG output.
- [x] 10.5 Add verification that local mode clearly marks the artifact as not notarized for distribution.
- [x] 10.6 Add `package-github-dev.sh`, `sign-app-adhoc.sh`, and `inspect-signature.sh` for GitHub Release-style dev artifacts.

## 11. Developer ID Signing and Notarization

- [x] 11.1 Implement official release signing scripts with explicit checks for Developer ID Application identity and notary credentials. Missing credentials skip rather than block dev builds.
- [x] 11.2 Sign nested helper and app binaries before signing the containing app; do not sign or redistribute external ZeroFS. Requires Developer ID credentials.
- [x] 11.3 Enable hardened runtime and reject debug entitlements such as `get-task-allow` in distribution mode. Requires Developer ID credentials.
- [x] 11.4 Verify with `codesign --verify --deep --strict --verbose=4` before creating the distribution DMG. Requires Developer ID credentials.
- [x] 11.5 Submit with `xcrun notarytool submit --wait`, staple with `xcrun stapler staple`, and verify with `spctl -a -vv`. Requires Apple notarization credentials.
- [x] 11.6 Add actionable failure messages for missing credentials, unsigned nested code, invalid helper plist, missing hardened runtime, modified bundle after signing, and stapling failures.
- [x] 11.7 Add release-only wrappers for Developer ID signing, notarization, and release verification.

## 12. Documentation and Release Checks

- [x] 12.1 Document local development build, local DMG packaging, helper approval flow, and rollback commands.
- [x] 12.2 Document distribution signing, notarization, stapling, and clean-machine verification.
- [x] 12.3 Document the difference between ZeroFS configured quota and real object-store capacity.
- [x] 12.4 Add troubleshooting docs for SMAppService approval, helper not launching, XPC connection failure, mount failure, stale mount, and performance cleanup.
- [x] 12.5 Run `openspec validate build-distributable-zerofs-manager --strict` and fix all validation issues.
- [x] 12.6 Commit the completed OpenSpec artifacts and scaffold changes.
- [x] 12.7 Document GitHub-style dev build, manual CLI/debug launchd tests, official release mode, and Apple signing errors as nonblocking for dev S3 testing.
