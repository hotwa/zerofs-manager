# Scheduled Reliability Probes Design

## Goal

Add an optional per-profile reliability and speed probe to ZeroFS Manager. The feature answers a practical user question: "Is this mounted object-storage disk currently healthy and reasonably fast from this Mac on this network?"

The probe is not a benchmark suite and must not present results as absolute storage-provider performance. Network conditions, Wi-Fi quality, campus routing, TLS, object-store throttling, ZeroFS cache state, file size, flush timing, and macOS sleep/wake behavior all affect the measured speed. The product should report recent health, trend, and failure reasons rather than over-precise ranking.

## Product Scope

Each mount profile gets:

- a manual `Test Now` action,
- an optional scheduled test setting, disabled by default,
- a recent-result status icon in the profile list,
- the latest probe summary in the profile detail view,
- a compact recent-history view.

The first implementation supports two execution modes:

- in-app timer mode while ZeroFS Manager is open,
- optional sudo-installed background `LaunchDaemon` mode for probes while the app is closed.

The UI may expose these as one scheduled-testing feature. Internally, it must keep in-app scheduling and background launchd scheduling separate so GitHub-dev users can run the safer app-open mode without installing another daemon.

## Defaults

Scheduled tests are off by default for every profile.

Default settings when a user enables scheduled testing:

- interval: 60 minutes,
- test size: 4 MiB,
- scheduled-test maximum size: 16 MiB,
- manual-test maximum without confirmation: 64 MiB,
- manual-test maximum with explicit confirmation: 512 MiB,
- history retention: 500 results per profile or 30 days, whichever is smaller.

The scheduled probe must skip rather than queue unlimited work when the Mac is asleep, offline, or the previous probe is still running.

## UI Design

The mount/profile list shows a small dynamic reliability icon for each profile:

- gray: disabled or no result,
- green: latest probe succeeded and is within normal bounds,
- yellow: latest probe succeeded but is slow, unstable, or missing non-critical data,
- red: latest probe failed.

The icon should have an accessible label and tooltip-style text such as "Healthy 12 min ago", "Slow write 8 min ago", or "Probe failed: mount missing".

The selected profile detail view adds a `Reliability Probe` section near the existing performance and mount actions. It includes:

- `Test Now` button,
- scheduled testing toggle,
- interval picker: 15 min, 30 min, 1 hour, 3 hours,
- scheduled test size picker: 1 MiB, 4 MiB, 16 MiB,
- manual test size picker: 1 MiB, 4 MiB, 16 MiB, 64 MiB,
- execution mode indicator: app-open timer, background LaunchDaemon, or disabled,
- latest result: timestamp, outcome, write throughput, read throughput, total duration, cleanup state, and short failure reason,
- compact history list with recent status dots and throughput values.

The UI must not use explanatory marketing text. It should be operational: controls, current state, and recent evidence.

## Probe Operation

Each probe runs against the mounted filesystem path for one profile.

Preflight checks:

- profile exists and has a valid mount path,
- mount path exists,
- mount path is currently mounted,
- mount line looks like a local ZeroFS NFS mount unless the user explicitly runs an advanced manual override,
- no other probe is currently running for the same profile.

Probe steps:

1. Create `<mount>/.zerofs-manager-probes/<profile-id>/`.
2. Write a random temporary payload file of the configured size.
3. `sync`.
4. Flush ZeroFS when a trusted profile runtime can provide the staged `zerofs` binary and config path.
5. Copy the file back to a local temporary readback path.
6. Compare SHA-256 of remote and readback files.
7. Record `df` before write, after write, and after cleanup.
8. Capture bounded Prometheus metrics from the profile metrics port when reachable.
9. Delete remote and local temporary files.
10. Store a sanitized result record.

Scheduled probes must not unmount the filesystem. Manual tests may expose a separate advanced option to unmount after testing only when the user explicitly asks for it.

## Data Model

Add profile-scoped probe settings:

- enabled,
- interval seconds,
- size bytes,
- allow background LaunchDaemon,
- last scheduled run timestamp,
- last user-triggered run timestamp.

Add probe result records:

- result ID,
- profile ID,
- trigger: manual, in-app schedule, background launchd,
- start and end timestamps,
- size bytes,
- write seconds and bytes per second,
- read seconds and bytes per second,
- checksum status,
- cleanup status,
- `df` snapshots,
- bounded metrics excerpt or metrics-unavailable marker,
- outcome: success, degraded, failed, skipped,
- classification: unknown, healthy, degraded, failed, disabled,
- short user-facing reason,
- technical detail for logs.

No S3 access key, S3 secret key, ZeroFS password, full env contents, or raw command line with secrets may be stored in probe settings, probe results, logs, or UI state.

## Reliability Classification

The classification intentionally favors clarity over precision.

Rules for the first version:

- disabled or no result: gray,
- skipped because scheduling was disabled, Mac asleep, previous probe running, or mount missing during app-open-only mode: gray unless the previous result was red,
- checksum failure, write failure, read failure, cleanup failure, or mount missing during an explicitly requested manual probe: red,
- successful probe with write or read throughput below 5 MiB/s: yellow,
- successful probe more than 50 percent slower than the median of the last 10 successful probes for the same profile: yellow,
- successful probe with metrics unavailable but data path healthy: yellow only when metrics were previously available for this profile, otherwise green,
- successful probe with normal throughput and cleanup: green.

These thresholds should be constants in the domain layer so they are testable and easy to adjust later.

## Background LaunchDaemon Mode

Background mode uses one additional profile-scoped LaunchDaemon:

`com.zerofs.manager.profile.<profile-id>.probe`

The daemon runs a root-owned probe wrapper script from the same profile runtime area as the existing root-owned ZeroFS runtime. It reads root-owned profile config but writes only sanitized result JSON to:

`/Library/Application Support/ZeroFSManager/ProbeResults/<profile-id>/`

The result directory is root-owned but world-readable because it contains no secrets. Secret-bearing profile runtime files remain under the existing root-only profile directory.

The app enables, updates, or disables the background probe daemon through the same reviewed sudo-terminal pattern used by `Apply & Restart LaunchDaemon`. Changing interval, test size, mount path, ports, or staged ZeroFS binary requires re-running the sudo update so launchd and the probe wrapper read current settings.

Background mode must be optional. Users who do not want another root job can still use `Test Now` and app-open scheduled tests.

## Storage and Privacy

In-app probe history is stored in the user's Application Support directory. Background probe history is stored as sanitized JSON under `/Library/Application Support/ZeroFSManager/ProbeResults/<profile-id>/` and mirrored into the UI when the app can read it.

Probe result files must be bounded. Keep at most 500 records or 30 days per profile. Cleanup old records during app startup and after background probe completion.

Probe temporary files live only under the hidden `.zerofs-manager-probes` directory in the mounted filesystem. The cleanup path must be generated from the profile ID and random result ID, never from untrusted user-entered relative paths.

## Error Handling

The UI should show short reasons:

- not mounted,
- mount path missing,
- not a local ZeroFS mount,
- write failed,
- read failed,
- checksum mismatch,
- cleanup incomplete,
- metrics unavailable,
- background daemon not installed,
- background daemon failed,
- skipped because previous probe still running.

Failures must include enough technical detail in logs for debugging, but dialogs and profile-list badges should stay concise.

Cleanup failures are important. A probe can be red even when write/read succeeded if temporary files could not be removed.

## Testing Strategy

Unit and integration-style checks should cover:

- probe settings validation,
- reliability classification thresholds,
- result retention,
- secret redaction,
- probe runner cleanup on success and failure,
- checksum mismatch behavior,
- mount preflight behavior,
- metrics-unavailable behavior,
- no unmount during scheduled probes,
- background LaunchDaemon script generation,
- sanitized result JSON permissions and contents,
- UI source markers for manual test button, scheduled toggle, interval picker, and profile-list reliability icon.

Manual verification should include:

- an app-open manual probe against a real mounted ZeroFS profile,
- a scheduled app-open probe,
- a background LaunchDaemon probe after the app is closed,
- a failure case with a missing mount path,
- confirmation that temporary remote files are removed.

## Non-Goals

- No automatic cache, quota, or port tuning based on probe results.
- No provider leaderboard or cross-user benchmarking.
- No claim that probe speed equals object-store raw throughput.
- No default background network traffic.
- No high-frequency stress testing.
- No storage-capacity measurement beyond existing `df` and quota explanation.

## Release Notes Impact

The documentation should explain that scheduled probes generate small temporary files and network traffic when enabled. It should also explain why results may vary across networks and why ZeroFS `df` capacity is configured quota rather than upstream object-storage capacity.
