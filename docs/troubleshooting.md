# Troubleshooting

## GitHub-style Dev Build Versus Official Release

Current development defaults to `github-dev`. In this mode, Apple signing and formal helper authorization are release-only and should not block ZeroFS CLI/S3 testing.

The following are expected or nonblocking for `github-dev`:

- `0 valid identities found`
- `TeamIdentifier=not set`
- ad-hoc signing
- no Developer ID
- no notarization
- `spctl --assess` failure or inconclusive output
- `SMAppServiceErrorDomain Code=3`
- `security error -67056`

These errors mainly involve Apple signing, TeamIdentifier, helper registration, bundle code requirements, or notarization. They do not block manual S3/ZeroFS CLI real mount testing.

Use:

```sh
Scripts/manual-mount-test.sh --env .env.local --delete-env-on-exit
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M
Scripts/manual-install-profile-launchdaemon.sh --env .env.local --delete-env-on-exit
```

Manual CLI and debug launchd testing is not equivalent to official `SMAppService` authorization.

## sudo LaunchDaemon Profile Does Not Apply Changes

GitHub-dev auto-mount uses root-owned profile config rather than rewriting plist files for every parameter change. This is intentional.

Expected layout:

- plist files: `/Library/LaunchDaemons/com.zerofs.manager.profile.<profile-id>.zerofs.plist` and `.mount.plist`
- optional probe plist: `/Library/LaunchDaemons/com.zerofs.manager.profile.<profile-id>.probe.plist`
- config: `/Library/Application Support/ZeroFSManager/Profiles/<profile-id>/zerofs.toml`
- secrets/env: `/Library/Application Support/ZeroFSManager/Profiles/<profile-id>/zerofs.env`
- sanitized probe results: `/Library/Application Support/ZeroFSManager/ProbeResults/<profile-id>/`
- logs: `/Library/Logs/ZeroFSManager/<profile-id>/zerofs.log`

After changing endpoint, bucket, prefix, mount directory, ports, cache, quota, or credentials, click `Apply & Restart LaunchDaemon` in the app or rerun:

```sh
Scripts/manual-install-profile-launchdaemon.sh --env .env.local --delete-env-on-exit
```

To remove the persistent profile daemon:

```sh
Scripts/manual-uninstall-profile-launchdaemon.sh --profile-id example-profile --mount-point /Volumes/ZeroFS-Example
```

## Helper Requires Approval

Symptom: the app reports `requiresApproval` or cannot connect to the helper.

In `github-dev`, do not treat this as a blocker for real S3/ZeroFS CLI testing. Use the manual test scripts instead. In `official-release`, continue with the actions below.

Action:

1. Move the app to `/Applications`.
2. Open `System Settings > General > Login Items & Extensions`.
3. Enable the ZeroFS Manager helper/background item if macOS shows it there.
4. Run `Scripts/diagnose-helper.sh` for launchd and recent log state.

## Helper Does Not Launch

Check the bundled plist:

```sh
Scripts/verify-bundle.sh "dist/ZeroFS Manager.app"
```

The helper plist must contain:

- `Label = com.zerofs.manager.helper`
- `BundleProgram = Contents/MacOS/ZeroFSPrivilegedHelper`
- `MachServices:com.zerofs.manager.helper = true`
- `AssociatedBundleIdentifiers:0 = com.zerofs.manager`

## Codesigning Failure `-67056`

Symptom: the mount dialog reports `SMAppServiceErrorDomain Code=3` and `code: -67056`.

In `github-dev`, this indicates the formal Apple helper path is not enabled. It should not block manual S3 mounting through `Scripts/manual-mount-test.sh`.

Action:

1. Rebuild the local app with `Scripts/build-app.sh`.
2. Verify the installed app with:

   ```sh
   APP_PATH="/Applications/ZeroFS Manager.app" Scripts/diagnose-helper.sh
   codesign --verify --deep --strict --verbose=4 "/Applications/ZeroFS Manager.app"
   ```

3. If verification reports `code has no resources but signature indicates they must be present`, reinstall the latest locally built app or DMG. This is an app bundle signing problem, not an S3 configuration problem.
4. For public distribution, use Developer ID signing and notarization; ad-hoc local signing is not sufficient for release.

## No TeamIdentifier Or No Signing Identities

Symptoms:

- `TeamIdentifier=not set`
- `security find-identity -p codesigning -v` reports `0 valid identities found`

In `github-dev`, this is expected for ad-hoc builds. Run `Scripts/inspect-signature.sh "dist/ZeroFS Manager.app"` to confirm strict ad-hoc code signing still passes. Only `official-release` requires Apple TeamIdentifier and Developer ID.

## XPC Connection Failure

Symptoms: the helper is approved but app operations still report unavailable, timeout, or connection invalidated.

Actions:

1. Confirm the app is running from `/Applications`, not directly from the DMG.
2. Run `APP_PATH="/Applications/ZeroFS Manager.app" Scripts/diagnose-helper.sh`.
3. Verify the Mach service name is `com.zerofs.manager.helper` in both the bundled plist and client code.
4. Verify the app and helper were signed by the same Developer ID identity in distribution builds.
5. Check recent logs for `ZeroFSPrivilegedHelper` and ServiceManagement messages.

## Mount Fails

Common causes:

- ZeroFS CLI is not installed or not visible on `PATH`
- S3 endpoint, bucket, prefix, or credentials are incorrect.
- the selected mount directory already exists with incompatible permissions
- NFS/RPC/metrics ports are already in use
- the helper is not approved or not running
- ZeroFS cannot reach the object-storage endpoint

The UI must redact secrets in all errors and show bounded log excerpts only.

If ZeroFS is missing, install it with:

```sh
curl -sSfL https://sh.zerofs.net | sh
```

## Stale Mount

If the ZeroFS process is stopped but the mount point still appears mounted, the helper should report a stale state. Manual cleanup can require an explicit unmount before restarting the profile.

## Quota Versus Object-Store Capacity

ZeroFS reports the configured virtual quota to macOS. This is not the real remaining capacity of the S3/MinIO/RustFS bucket. Real provider capacity usually requires provider-side APIs or admin credentials and is outside v1 scope.

## Performance Test Cleanup

The performance runner writes a temp file, flushes through the helper, reads it back, compares SHA-256, and removes both remote and readback files. If cleanup fails, the report should show the cleanup state so the user can remove leftovers manually.

For a real mounted ZeroFS volume, run:

```sh
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M
```

Large tests require explicit confirmation:

```sh
Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 1024M --confirm-large-test
```

## Reliability Probe Results

Reliability probes are disabled until the user enables them. When enabled, each probe writes and removes a hidden temporary file under `.zerofs-manager-probes/<profile-id>/`, so it creates small network/object-storage traffic.

If the icon is red, check whether the mount path is actually mounted, whether the local NFS export is still available, and whether hidden probe files were left behind. If background mode is enabled, re-run `Apply & Restart LaunchDaemon` after changing interval, size, mount point, ports, or ZeroFS binary path.

Probe results are sanitized and do not contain S3 credentials. They are health samples, not object-store capacity readings.

`manual-performance-test.sh` refuses mount points that do not look like local ZeroFS/NFS mounts unless `--allow-non-zerofs-mount` is provided. Only use that override for a scratch volume that can be safely modified and unmounted.
