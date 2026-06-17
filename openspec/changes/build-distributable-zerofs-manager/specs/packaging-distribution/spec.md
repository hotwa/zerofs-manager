## ADDED Requirements

### Requirement: App bundle contains required executables and resources
The build system SHALL assemble `ZeroFS Manager.app` with the main app executable, privileged helper executable, bundled LaunchDaemon plist, resources, and Info.plist metadata, while treating ZeroFS as a user-installed external dependency.

#### Scenario: Build local app bundle
- **WHEN** the local app build script succeeds
- **THEN** the app bundle contains the expected executable, helper, and LaunchDaemon plist paths
- **AND** the app bundle does not contain `Contents/Resources/zerofs/zerofs`

#### Scenario: Verify external ZeroFS policy
- **WHEN** packaging checks the app bundle
- **THEN** it verifies that ZeroFS is not embedded in the GUI DMG
- **AND** runtime UI displays the official install command when `zerofs` is missing

### Requirement: GitHub-style dev packaging works without Developer ID credentials
The build system SHALL produce GitHub-style development app, zip, and DMG artifacts even when Developer ID or notarization credentials are unavailable.

#### Scenario: Missing Developer ID credentials in github-dev mode
- **WHEN** the user runs GitHub-style dev packaging without Developer ID credentials
- **THEN** the script creates dev artifacts and marks them as not Developer ID signed or notarized
- **AND** `spctl` failure does not block the dev artifact

### Requirement: Official release packaging enforces signing and notarization
The build system MUST reserve Developer ID signing, hardened runtime, notarization, stapling, and verification for official release artifacts.

#### Scenario: Missing credentials in official-release mode
- **WHEN** the user runs official release scripts without required Developer ID or notarization credentials
- **THEN** the scripts explain that official release signing is unavailable
- **AND** the scripts skip without blocking GitHub-style dev builds

#### Scenario: Successful distribution packaging
- **WHEN** signing and notarization credentials are available
- **THEN** nested executables are signed before the containing app, the app is verified, the DMG is submitted to notary service, the ticket is stapled, and Gatekeeper verification passes

### Requirement: Packaging captures common failure modes
The build system SHALL report actionable failures for invalid bundle layout, missing plist suffix, unsigned nested code, missing hardened runtime, debug entitlements, and modified bundle contents after signing.

#### Scenario: Helper plist missing
- **WHEN** the bundled LaunchDaemon plist is missing or incorrectly named
- **THEN** packaging verification fails with a message naming the expected path

#### Scenario: Nested code unsigned
- **WHEN** the helper or app executable is unsigned in distribution mode
- **THEN** packaging verification fails before notarization

### Requirement: Signature inspection distinguishes dev and release failures
The build system SHALL classify unsigned, ad-hoc, Apple Development, Developer ID Application, and non-Apple signed artifacts without treating dev-only Apple trust failures as S3 blockers.

#### Scenario: Ad-hoc dev build has no TeamIdentifier
- **WHEN** the user inspects an ad-hoc GitHub-style dev app
- **THEN** the script reports `TeamIdentifier=not set` as expected for dev mode
- **AND** strict `codesign --verify --deep --strict` remains required
