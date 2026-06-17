## ADDED Requirements

### Requirement: Helper exposes only specific privileged operations
The privileged helper SHALL expose a narrow API for install or update profile runtime, start service, stop service, restart service, mount, unmount, flush, status, sync runtime secrets, and bounded log reads.

#### Scenario: App requests supported operation
- **WHEN** the app requests `mount` for a valid profile
- **THEN** the helper validates the profile and performs only the mount operation

#### Scenario: App attempts arbitrary command
- **WHEN** any client attempts to pass an arbitrary shell command
- **THEN** the helper rejects the request because no generic command execution API exists

### Requirement: Helper validates all privileged inputs
The privileged helper MUST revalidate profile IDs, generated paths, mount paths, service labels, plist contents, and ports before touching privileged filesystem locations or launchd state.

#### Scenario: Malicious path from UI process
- **WHEN** the app or any XPC client sends a generated path outside the allowed runtime root
- **THEN** the helper rejects the operation and returns a structured validation error

#### Scenario: Duplicate port configuration
- **WHEN** a profile requests conflicting NFS, RPC, or metrics ports
- **THEN** the helper refuses to install or start the runtime

### Requirement: SMAppService bundled daemon registration is release-only
The system SHALL reserve ServiceManagement `SMAppService` daemon registration for official release mode, with the helper executable and LaunchDaemon plist bundled inside the app.

#### Scenario: Register helper in official release
- **WHEN** the user initiates helper installation in `official-release`
- **THEN** the app registers the bundled daemon plist by filename through ServiceManagement

#### Scenario: User approval required
- **WHEN** macOS requires approval for the background item
- **THEN** the app shows a state explaining that the user must approve the item in System Settings

#### Scenario: Helper requested in github-dev
- **WHEN** the user initiates helper installation or auto-mount in `github-dev`
- **THEN** the app does not call `SMAppService.register()`
- **AND** the app directs the user to manual CLI or debug launchd testing

### Requirement: Helper state is observable by the app
The system SHALL expose helper states including not registered, requires approval, enabled, disabled, not found, running, stopped, and failed.

#### Scenario: Helper is disabled
- **WHEN** the helper is disabled in System Settings
- **THEN** the app shows the disabled state and provides remediation instructions

#### Scenario: Helper launch fails
- **WHEN** the helper is registered but cannot launch
- **THEN** the app shows a structured error with bounded recent logs

### Requirement: Launchd resources are profile-aware
The helper SHALL generate or manage launchd resources with deterministic labels and metadata derived from profile ID and bundle identifiers.

#### Scenario: Generate LaunchDaemon plist
- **WHEN** runtime service files are generated
- **THEN** the plist includes deterministic labels, bundle-relative program metadata where applicable, and no secret values
