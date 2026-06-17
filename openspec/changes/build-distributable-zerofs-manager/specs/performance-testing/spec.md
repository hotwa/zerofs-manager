## ADDED Requirements

### Requirement: User can run a configurable performance test
The system SHALL let the user choose a test size and run a write, flush, readback, checksum, cleanup, and report workflow against the mounted profile.

#### Scenario: Run successful test
- **WHEN** the user starts a performance test on a mounted profile
- **THEN** the system writes the test data, flushes, reads it back, compares SHA-256, removes temporary files, and records a PASS result

#### Scenario: Profile not mounted
- **WHEN** the user starts a test for an unmounted profile
- **THEN** the system refuses to start and explains that the profile must be mounted first

### Requirement: Performance reports include capacity semantics
The system SHALL include `df` snapshots and a clear statement that `df` reports the configured ZeroFS quota rather than real object-store capacity.

#### Scenario: Export report
- **WHEN** a test finishes
- **THEN** the report includes `df` before write, after write, after cleanup, throughput, checksum status, cleanup status, and metrics snapshots

### Requirement: Test cleanup is required on success and failure
The system MUST attempt to remove remote and local temporary files when a test succeeds, fails, or is cancelled.

#### Scenario: Write fails
- **WHEN** writing test data fails midway
- **THEN** the system attempts cleanup and records cleanup status in the test result

#### Scenario: Checksum fails
- **WHEN** source and readback SHA-256 values differ
- **THEN** the system reports failure and still attempts cleanup

### Requirement: Performance runner is unit-testable without object storage
The system SHALL allow performance workflow tests to run against temporary local directories and mock helper clients.

#### Scenario: Run cleanup unit test
- **WHEN** a simulated write failure occurs in a unit test
- **THEN** the test verifies cleanup behavior without mounting ZeroFS or writing 1 GB

### Requirement: Manual performance testing supports real dev mounts
The system SHALL provide a GitHub-style dev script for small real mounted ZeroFS performance tests without Apple Developer ID.

#### Scenario: Run default manual performance test
- **WHEN** the user runs `Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test --size 128M`
- **THEN** the script performs sequential write, sequential read, small files create/read/delete, `df` snapshots, sync/flush behavior, checksum verification, cleanup, and unmount

#### Scenario: Large manual performance test
- **WHEN** the user requests a large test such as `--size 1024M`
- **THEN** the script requires `--confirm-large-test`
