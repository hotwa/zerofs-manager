## ADDED Requirements

### Requirement: Profile model captures ZeroFS mount configuration
The system SHALL model each mount as a `MountProfile` containing display name, endpoint URL, access key reference, secret key reference, bucket, prefix, mount path, quota, disk cache size, memory cache size, NFS port, RPC port, metrics port, login auto-mount setting, and performance test size.

#### Scenario: Create valid profile
- **WHEN** the user enters valid S3, mount, quota, cache, and port values
- **THEN** the system stores a complete profile without requiring root privileges

#### Scenario: Show configurable mount path
- **WHEN** the user opens profile settings
- **THEN** the mount path is editable and defaults to `/Volumes/ZeroFS-<profileName>` for new profiles

### Requirement: Profile validation blocks unsafe values
The system MUST validate profile values before saving or sending them to the privileged helper.

#### Scenario: Reject unsafe mount path
- **WHEN** the user enters a mount path that is empty, relative, contains path traversal, or points inside generated runtime config directories
- **THEN** the system rejects the profile and shows a field-level validation error

#### Scenario: Reject invalid ports
- **WHEN** the user enters duplicate ports or ports outside the allowed TCP range
- **THEN** the system rejects the profile and explains which port setting is invalid

#### Scenario: Reject invalid object storage fields
- **WHEN** endpoint, bucket, or prefix values are malformed
- **THEN** the system prevents saving and identifies the invalid field

### Requirement: Runtime identifiers are profile-scoped
The system SHALL derive runtime paths, service labels, log paths, report paths, and generated filenames from a stable profile ID.

#### Scenario: Rename profile display name
- **WHEN** the user changes the display name of a profile
- **THEN** existing runtime identifiers remain tied to the stable profile ID rather than the new display name

#### Scenario: Add future second profile
- **WHEN** a second profile is added in a future version
- **THEN** generated labels and runtime paths do not collide with the first profile

### Requirement: V1 exposes profile list but enforces one active profile
The system SHALL show a Mount/Profile list in the UI while v1 allows only one active profile to be configured.

#### Scenario: First profile exists
- **WHEN** one profile already exists
- **THEN** the UI displays it in the profile list and opens its dashboard details

#### Scenario: User attempts additional profile in v1
- **WHEN** the user tries to create another active profile
- **THEN** the system explains that multi-profile mounting is reserved for a future release
