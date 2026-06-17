## ADDED Requirements

### Requirement: Login-after-start auto-mount
The system SHALL support automatic mounting after the user logs in when the profile's auto-mount setting is enabled.

#### Scenario: User logs in with auto-mount enabled
- **WHEN** the app or login item starts after login
- **THEN** it checks the active profile and asks the helper to ensure the ZeroFS service is installed, running, and mounted

#### Scenario: Auto-mount disabled
- **WHEN** the profile's auto-mount setting is disabled
- **THEN** the app does not mount automatically and leaves manual mount controls available

### Requirement: Mount failures surface as app alerts
The system MUST show an app-visible alert or notification when login auto-mount fails.

#### Scenario: Mount command fails
- **WHEN** the helper returns a mount failure
- **THEN** the app displays profile name, failed operation, human-readable message, bounded log excerpt, and retry/settings/log actions

#### Scenario: Helper unavailable
- **WHEN** login auto-mount cannot contact the helper
- **THEN** the app displays a failure state with instructions to approve or reinstall the helper

### Requirement: Status monitoring distinguishes service and mount state
The system SHALL track helper registration state, ZeroFS process state, NFS mount state, and metrics reachability separately.

#### Scenario: Service running but not mounted
- **WHEN** ZeroFS is running but the mount path is not mounted
- **THEN** the dashboard shows a partial state and offers a mount action

#### Scenario: Mounted path is stale
- **WHEN** the mount exists but status checks indicate failure or staleness
- **THEN** the dashboard shows a warning and offers unmount/remount actions

### Requirement: V1 does not require pre-login mounting
The system SHALL not require mounting before user login in v1.

#### Scenario: Machine boots to login screen
- **WHEN** no user has logged in
- **THEN** v1 makes no guarantee that ZeroFS is mounted
