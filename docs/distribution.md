# Developer ID Distribution

Distribution packaging is intentionally separate from GitHub-style dev packaging.

`official-release` is release-only. If Developer ID or notary settings are missing, release scripts print:

```text
Official release signing is unavailable because Developer ID is not configured.
Skipping official release path.
```

and exit successfully so `github-dev` work can continue.

## Required Inputs

Set a Developer ID signing identity:

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: Example Team (TEAMID)"
```

Provide notarization credentials through a keychain profile:

```sh
export NOTARY_PROFILE="zerofs-manager-notary"
export DEVELOPMENT_TEAM="TEAMID"
```

## Build Signed DMG

```sh
Scripts/sign-notarize-staple.sh
```

The script:

- builds `ZeroFS Manager.app` with `CONFIGURATION=release` by default
- verifies bundle layout and strict code signing
- signs the privileged helper
- signs the main app executable
- signs the app bundle with hardened runtime
- verifies with `codesign --verify --deep --strict --verbose=4`
- creates and signs a distribution DMG
- submits with `xcrun notarytool submit --wait`
- staples with `xcrun stapler staple`
- verifies with `spctl`

The script skips if Developer ID or notary credentials are missing. It must not produce a release-labeled artifact with best-effort signing.

The distribution DMG does not include or redistribute ZeroFS. The GUI detects an externally installed `zerofs` binary and shows the upstream install command when missing.

## Clean-Machine Verification

Before public distribution, test the stapled DMG on a clean macOS account or machine:

```sh
spctl -a -vv -t open --context context:primary-signature dist/ZeroFS-Manager-distribution.dmg
hdiutil attach dist/ZeroFS-Manager-distribution.dmg
cp -R "/Volumes/ZeroFS Manager/ZeroFS Manager.app" /Applications/
codesign --verify --deep --strict --verbose=4 "/Applications/ZeroFS Manager.app"
spctl -a -vv "/Applications/ZeroFS Manager.app"
```

Then launch the app from `/Applications`, approve the helper if macOS asks, and run the in-app helper status check before trying a real mount.

## Manual Approval Is Still Required

Even a signed and notarized app cannot bypass macOS user controls. Helper/background item approval can still require the user to approve or re-enable the item in System Settings.

## GitHub-style Dev Alternative

For local development and technical-user testing without Apple Developer Program:

```sh
Scripts/package-github-dev.sh
```

This emits ad-hoc signed dev artifacts and a README warning that Gatekeeper may block them. These artifacts are not official macOS distribution builds.

For the free GitHub edition, this is the supported low-friction distribution track. Users install ZeroFS separately, then manually authorize `sudo` when they want the app/scripts to install launchd files, start/stop ZeroFS, mount/unmount NFS, or run privileged diagnostics. This can cover real S3 mounting and testing without Apple Developer ID, but it does not provide the no-warning installation experience of notarized Developer ID software.

The GitHub edition should describe the installed ZeroFS version as a compatibility diagnostic. The currently tested baseline is `zerofs 1.2.6`; it is not bundled, pinned, or required when a compatible newer upstream ZeroFS is installed.

## Apple References

- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [ServiceManagement](https://developer.apple.com/documentation/ServiceManagement)
- [Developer ID](https://developer.apple.com/developer-id/)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
