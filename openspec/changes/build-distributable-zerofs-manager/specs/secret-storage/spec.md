## ADDED Requirements

### Requirement: Keychain is the primary secret store
The system SHALL store S3 Access Key ID, S3 Secret Access Key, and ZeroFS encryption password in macOS Keychain using service and account names derived from the profile ID and secret kind.

#### Scenario: Save profile secrets
- **WHEN** the user saves credentials for a profile
- **THEN** the system writes the secret values to Keychain and does not write them to app preferences

#### Scenario: Load profile secrets
- **WHEN** the user opens an existing profile
- **THEN** the system retrieves secret availability from Keychain without displaying secret values by default

### Requirement: Runtime secret files are generated state
The system SHALL treat root-only runtime secret files as generated state synchronized by the privileged helper, not as the source of truth.

#### Scenario: Sync runtime secrets
- **WHEN** profile credentials change
- **THEN** the app asks the privileged helper to write updated root-only runtime secrets for that profile

#### Scenario: Runtime secret missing
- **WHEN** the helper reports that a runtime secret file is missing
- **THEN** the app offers to resync from Keychain instead of asking the user to edit root files manually

### Requirement: Secrets are never logged or reported
The system MUST redact or omit secret values from logs, reports, errors, OpenSpec artifacts, command arguments, and world-readable files.

#### Scenario: Helper operation fails
- **WHEN** a helper operation involving credentials fails
- **THEN** the surfaced error contains no Access Key, Secret Key, or ZeroFS encryption password

#### Scenario: Export performance report
- **WHEN** the user exports a performance report
- **THEN** the report contains endpoint, bucket, prefix, and profile name but no secret values

### Requirement: Secret storage is testable without Keychain
The system SHALL expose a secret-store protocol with an in-memory implementation for tests and previews.

#### Scenario: Run unit tests
- **WHEN** tests exercise credential-dependent UI or services
- **THEN** they use a mock secret store and do not require access to the user's Keychain
