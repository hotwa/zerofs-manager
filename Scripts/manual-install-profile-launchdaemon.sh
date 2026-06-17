#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=""
DELETE_ENV_ON_EXIT=0

usage() {
  cat <<'USAGE'
Usage: Scripts/manual-install-profile-launchdaemon.sh --env /path/to/profile.env [--delete-env-on-exit]

Installs or updates a root-owned LaunchDaemon profile for GitHub-style dev
builds. This is the sudo-authorized path for technical users without Apple
Developer ID. It writes runtime config under /Library/Application Support,
stores secrets in a root-only env file, reloads launchd, and kickstarts the
ZeroFS runtime and mount jobs.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --delete-env-on-exit)
      DELETE_ENV_ON_EXIT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$ENV_FILE" && -f "$ENV_FILE" ]] || {
  echo "Missing --env file" >&2
  usage >&2
  exit 2
}

cleanup() {
  if [[ "$DELETE_ENV_ON_EXIT" == "1" && -n "$ENV_FILE" ]]; then
    rm -f "$ENV_FILE"
  fi
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

set -a
source "$ENV_FILE"
set +a

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env var: $name" >&2
    exit 2
  fi
}

for name in ZEROFS_PROFILE_ID ZEROFS_BIN ZEROFS_MOUNT_POINT S3_ENDPOINT S3_BUCKET S3_ACCESS_KEY S3_SECRET_KEY ZEROFS_PASSWORD; do
  require_var "$name"
done

[[ "$ZEROFS_PROFILE_ID" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || {
  echo "Invalid ZEROFS_PROFILE_ID: $ZEROFS_PROFILE_ID" >&2
  exit 2
}

is_safe_mount_point() {
  local path="$1"
  [[ "$path" == /Volumes/* ]] || return 1
  [[ "$path" != "/Volumes/" ]] || return 1
  [[ "$path" != *"//"* ]] || return 1
  [[ "$path" != *"/../"* && "$path" != *"/.." ]] || return 1
  [[ "$path" != *"/./"* && "$path" != *"/." ]] || return 1
}

if ! is_safe_mount_point "$ZEROFS_MOUNT_POINT"; then
  echo "Refusing unsafe ZEROFS_MOUNT_POINT: $ZEROFS_MOUNT_POINT" >&2
  exit 2
fi

[[ -x "$ZEROFS_BIN" ]] || {
  echo "ZeroFS binary not executable: $ZEROFS_BIN" >&2
  exit 2
}

ZEROFS_NFS_PORT="${ZEROFS_NFS_PORT:-2049}"
ZEROFS_RPC_PORT="${ZEROFS_RPC_PORT:-17000}"
ZEROFS_METRICS_PORT="${ZEROFS_METRICS_PORT:-9091}"
ZEROFS_QUOTA_GB="${ZEROFS_QUOTA_GB:-1024}"
ZEROFS_DISK_CACHE_GB="${ZEROFS_DISK_CACHE_GB:-10}"
ZEROFS_MEMORY_CACHE_GB="${ZEROFS_MEMORY_CACHE_GB:-0.5}"
S3_REGION="${S3_REGION:-us-east-1}"
S3_PREFIX="${S3_PREFIX:-}"
ZEROFS_PROBE_ENABLED="${ZEROFS_PROBE_ENABLED:-0}"
ZEROFS_PROBE_INTERVAL_SECONDS="${ZEROFS_PROBE_INTERVAL_SECONDS:-3600}"
ZEROFS_PROBE_SIZE_BYTES="${ZEROFS_PROBE_SIZE_BYTES:-4194304}"
ZEROFS_PROBE_TOOL="${ZEROFS_PROBE_TOOL:-}"

case "$ZEROFS_PROBE_ENABLED" in
  1|true|TRUE|yes|YES|on|ON)
    ZEROFS_PROBE_ENABLED=1
    ;;
  *)
    ZEROFS_PROBE_ENABLED=0
    ;;
esac

[[ "$ZEROFS_PROBE_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "Invalid ZEROFS_PROBE_INTERVAL_SECONDS: $ZEROFS_PROBE_INTERVAL_SECONDS" >&2
  exit 2
}
[[ "$ZEROFS_PROBE_SIZE_BYTES" =~ ^[0-9]+$ ]] || {
  echo "Invalid ZEROFS_PROBE_SIZE_BYTES: $ZEROFS_PROBE_SIZE_BYTES" >&2
  exit 2
}
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  (( ZEROFS_PROBE_INTERVAL_SECONDS >= 60 )) || {
    echo "ZEROFS_PROBE_INTERVAL_SECONDS must be at least 60 seconds" >&2
    exit 2
  }
  (( ZEROFS_PROBE_SIZE_BYTES > 0 && ZEROFS_PROBE_SIZE_BYTES <= 16777216 )) || {
    echo "ZEROFS_PROBE_SIZE_BYTES must be between 1 byte and 16 MiB" >&2
    exit 2
  }
  [[ -x "$ZEROFS_PROBE_TOOL" ]] || {
    echo "ZEROFS_PROBE_TOOL is not executable: $ZEROFS_PROBE_TOOL" >&2
    exit 2
  }
fi

LABEL_PREFIX="com.zerofs.manager.profile.$ZEROFS_PROFILE_ID"
RUNTIME_LABEL="$LABEL_PREFIX.zerofs"
MOUNT_LABEL="$LABEL_PREFIX.mount"
PROBE_LABEL="$LABEL_PREFIX.probe"
PROFILE_ROOT="/Library/Application Support/ZeroFSManager/Profiles/$ZEROFS_PROFILE_ID"
PROBE_RESULT_ROOT="/Library/Application Support/ZeroFSManager/ProbeResults/$ZEROFS_PROFILE_ID"
PROBE_LOCK_ROOT="/tmp/zerofs-manager-probe-locks"
LOG_ROOT="/Library/Logs/ZeroFSManager/$ZEROFS_PROFILE_ID"
CACHE_DIR="${ZEROFS_CACHE_DIR:-/var/cache/zerofs-manager/$ZEROFS_PROFILE_ID}"
CONFIG_PATH="$PROFILE_ROOT/zerofs.toml"
ENV_PATH="$PROFILE_ROOT/zerofs.env"
STAGED_ZEROFS_BIN="$PROFILE_ROOT/zerofs"
STAGED_PROBE_TOOL="$PROFILE_ROOT/ZeroFSProbeTool"
RUN_SCRIPT="$PROFILE_ROOT/run-zerofs.sh"
MOUNT_SCRIPT="$PROFILE_ROOT/mount-zerofs.sh"
FLUSH_SCRIPT="$PROFILE_ROOT/flush-zerofs.sh"
PROBE_SCRIPT="$PROFILE_ROOT/probe-zerofs.sh"
RUNTIME_PLIST="/Library/LaunchDaemons/$RUNTIME_LABEL.plist"
MOUNT_PLIST="/Library/LaunchDaemons/$MOUNT_LABEL.plist"
PROBE_PLIST="/Library/LaunchDaemons/$PROBE_LABEL.plist"
LOG_PATH="$LOG_ROOT/zerofs.log"
PROBE_LOG_PATH="$LOG_ROOT/probe.log"
RPC_SOCKET="/var/run/zerofs-manager-$ZEROFS_PROFILE_ID.rpc.sock"

shell_quote() {
  local value="$1"
  printf "'"
  printf "%s" "$value" | sed "s/'/'\\\\''/g"
  printf "'"
}

toml_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

redact() {
  local text="$*"
  for secret in "${S3_ACCESS_KEY:-}" "${S3_SECRET_KEY:-}" "${ZEROFS_PASSWORD:-}"; do
    if [[ -n "$secret" ]]; then
      text="${text//$secret/[REDACTED]}"
    fi
  done
  printf "%s\n" "$text"
}

is_trusted_root_env() {
  local path="$1"
  local metadata
  sudo test -f "$path" || return 1
  sudo test ! -L "$path" || return 1
  metadata="$(sudo /usr/bin/stat -f '%Su:%Sg:%Lp' "$path" 2>/dev/null || true)"
  [[ "$metadata" == "root:wheel:600" ]]
}

read_trusted_env_value() {
  local path="$1"
  local name="$2"
  if ! is_trusted_root_env "$path"; then
    return 1
  fi
  sudo /bin/zsh -c 'set -euo pipefail; source "$1"; case "$2" in ZEROFS_MOUNT_POINT) printf "%s" "${ZEROFS_MOUNT_POINT:-}" ;; *) exit 2 ;; esac' zerofs-manager "$path" "$name" 2>/dev/null
}

bootout_job() {
  local label="$1"
  local plist="$2"
  sudo launchctl bootout system "$plist" >/dev/null 2>&1 || true
  sudo launchctl bootout "system/$label" >/dev/null 2>&1 || true
}

ensure_job_unloaded() {
  local label="$1"
  if sudo launchctl print "system/$label" >/dev/null 2>&1; then
    echo "LaunchDaemon is still loaded after bootout: $label" >&2
    exit 1
  fi
}

assert_root_owned_runtime_file() {
  local path="$1"
  local metadata
  local owner
  local group
  local mode
  sudo test -f "$path" || {
    echo "Missing staged runtime file: $path" >&2
    exit 1
  }
  sudo test ! -L "$path" || {
    echo "Refusing symlinked staged runtime file: $path" >&2
    exit 1
  }
  metadata="$(sudo /usr/bin/stat -f '%Su:%Sg:%Lp' "$path" 2>/dev/null || true)"
  IFS=: read -r owner group mode <<< "$metadata"
  if [[ "$owner" != "root" || "$group" != "wheel" || -z "$mode" ]]; then
    echo "Refusing unsafe staged runtime file metadata for $path: $metadata" >&2
    exit 1
  fi
  if (( (8#$mode & 022) != 0 )); then
    echo "Refusing group/world-writable staged runtime file: $path" >&2
    exit 1
  fi
  if (( (8#$mode & 111) == 0 )); then
    echo "Refusing non-executable staged runtime file: $path" >&2
    exit 1
  fi
}

echo "Installing ZeroFS Manager LaunchDaemons for profile: $ZEROFS_PROFILE_ID"
echo "This path uses sudo and launchd directly. It does not require Apple Developer ID or SMAppService."
sudo -v

OLD_MOUNT_POINT=""
if sudo test -e "$ENV_PATH"; then
  OLD_MOUNT_POINT="$(read_trusted_env_value "$ENV_PATH" ZEROFS_MOUNT_POINT || true)"
  if [[ -z "$OLD_MOUNT_POINT" ]]; then
    echo "Skipping previous mount point because existing env is missing or not root:wheel 0600: $ENV_PATH" >&2
  fi
fi
if [[ -n "$OLD_MOUNT_POINT" ]] && ! is_safe_mount_point "$OLD_MOUNT_POINT"; then
  echo "Skipping unsafe previous mount point from existing env: $OLD_MOUNT_POINT" >&2
  OLD_MOUNT_POINT=""
fi

bootout_job "$PROBE_LABEL" "$PROBE_PLIST"
bootout_job "$MOUNT_LABEL" "$MOUNT_PLIST"
bootout_job "$RUNTIME_LABEL" "$RUNTIME_PLIST"
ensure_job_unloaded "$PROBE_LABEL"
ensure_job_unloaded "$MOUNT_LABEL"
ensure_job_unloaded "$RUNTIME_LABEL"

if [[ -n "$OLD_MOUNT_POINT" && "$OLD_MOUNT_POINT" != "$ZEROFS_MOUNT_POINT" ]]; then
  if /sbin/mount | /usr/bin/grep -Fq " on $OLD_MOUNT_POINT "; then
    echo "Unmounting previous mount point: $OLD_MOUNT_POINT"
    sudo /sbin/umount "$OLD_MOUNT_POINT" >/dev/null 2>&1 || true
  fi
fi

MOUNT_POINT_ALREADY_MOUNTED=0
if /sbin/mount | /usr/bin/grep -Fq " on $ZEROFS_MOUNT_POINT "; then
  MOUNT_POINT_ALREADY_MOUNTED=1
fi

TMP_DIR="$(mktemp -d)"
STORAGE_PREFIX=""
if [[ -n "$S3_PREFIX" ]]; then
  STORAGE_PREFIX="/$S3_PREFIX"
fi

cat > "$TMP_DIR/zerofs.toml" <<CONFIG
[cache]
dir = "\${ZEROFS_CACHE_DIR}"
disk_size_gb = $ZEROFS_DISK_CACHE_GB
memory_size_gb = $ZEROFS_MEMORY_CACHE_GB

[storage]
url = $(toml_string "s3://$S3_BUCKET$STORAGE_PREFIX")
encryption_password = "\${ZEROFS_PASSWORD}"

[filesystem]
max_size_gb = $ZEROFS_QUOTA_GB
compression = "zstd-3"

[aws]
access_key_id = "\${AWS_ACCESS_KEY_ID}"
secret_access_key = "\${AWS_SECRET_ACCESS_KEY}"
endpoint = $(toml_string "$S3_ENDPOINT")
region = $(toml_string "$S3_REGION")

[servers.nfs]
addresses = [$(toml_string "127.0.0.1:$ZEROFS_NFS_PORT")]

[servers.rpc]
addresses = [$(toml_string "127.0.0.1:$ZEROFS_RPC_PORT")]
unix_socket = $(toml_string "$RPC_SOCKET")

[prometheus]
addresses = [$(toml_string "127.0.0.1:$ZEROFS_METRICS_PORT")]

[telemetry]
enabled = false
CONFIG

cat > "$TMP_DIR/zerofs.env" <<ENV
AWS_ACCESS_KEY_ID=$(shell_quote "$S3_ACCESS_KEY")
AWS_SECRET_ACCESS_KEY=$(shell_quote "$S3_SECRET_KEY")
ZEROFS_PASSWORD=$(shell_quote "$ZEROFS_PASSWORD")
ZEROFS_CACHE_DIR=$(shell_quote "$CACHE_DIR")
ZEROFS_CONFIG=$(shell_quote "$CONFIG_PATH")
ZEROFS_ENV_FILE=$(shell_quote "$ENV_PATH")
ZEROFS_MOUNT_POINT=$(shell_quote "$ZEROFS_MOUNT_POINT")
ZEROFS_NFS_PORT=$(shell_quote "$ZEROFS_NFS_PORT")
ZEROFS_RPC_PORT=$(shell_quote "$ZEROFS_RPC_PORT")
ZEROFS_METRICS_PORT=$(shell_quote "$ZEROFS_METRICS_PORT")
ZEROFS_PROBE_ENABLED=$(shell_quote "$ZEROFS_PROBE_ENABLED")
ZEROFS_PROBE_INTERVAL_SECONDS=$(shell_quote "$ZEROFS_PROBE_INTERVAL_SECONDS")
ZEROFS_PROBE_SIZE_BYTES=$(shell_quote "$ZEROFS_PROBE_SIZE_BYTES")
ENV

cat > "$TMP_DIR/run-zerofs.sh" <<RUN
#!/bin/zsh
set -euo pipefail
set -a
source $(shell_quote "$ENV_PATH")
set +a
exec $(shell_quote "$STAGED_ZEROFS_BIN") run --config $(shell_quote "$CONFIG_PATH")
RUN

cat > "$TMP_DIR/mount-zerofs.sh" <<MOUNT
#!/bin/zsh
set -euo pipefail
set -a
source $(shell_quote "$ENV_PATH")
set +a

MOUNT_POINT=\${ZEROFS_MOUNT_POINT}
NFS_HOST="127.0.0.1"
NFS_PORT="\${ZEROFS_NFS_PORT}"
NFS_SOURCE="127.0.0.1:/"
NFS_OPTIONS="async,nolocks,vers=3,tcp,port=\${ZEROFS_NFS_PORT},mountport=\${ZEROFS_NFS_PORT},hard,rsize=1048576,wsize=1048576"

if /sbin/mount | /usr/bin/grep -Fq " on \${MOUNT_POINT} "; then
  exit 0
fi

/bin/mkdir -p "\${MOUNT_POINT}"

ready="false"
for _ in {1..60}; do
  if /usr/bin/nc -z "\${NFS_HOST}" "\${NFS_PORT}" >/dev/null 2>&1; then
    ready="true"
    break
  fi
  /bin/sleep 1
done

if [[ "\${ready}" != "true" ]]; then
  echo "ZeroFS NFS port \${NFS_HOST}:\${NFS_PORT} did not become ready within 60 seconds" >&2
  exit 1
fi

/sbin/mount -t nfs -o "\${NFS_OPTIONS}" "\${NFS_SOURCE}" "\${MOUNT_POINT}"
MOUNT

cat > "$TMP_DIR/flush-zerofs.sh" <<FLUSH
#!/bin/zsh
set -euo pipefail
set -a
source $(shell_quote "$ENV_PATH")
set +a
exec $(shell_quote "$STAGED_ZEROFS_BIN") flush --config $(shell_quote "$CONFIG_PATH")
FLUSH

cat > "$TMP_DIR/runtime.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$RUNTIME_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$RUN_SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$LOG_PATH</string>
  <key>WorkingDirectory</key>
  <string>/var/empty</string>
</dict>
</plist>
PLIST

cat > "$TMP_DIR/mount.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$MOUNT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$MOUNT_SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>StandardOutPath</key>
  <string>$LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$LOG_PATH</string>
  <key>WorkingDirectory</key>
  <string>/var/empty</string>
</dict>
</plist>
PLIST

if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  cat > "$TMP_DIR/probe-zerofs.sh" <<PROBE
#!/bin/zsh
set -euo pipefail
set -a
source $(shell_quote "$ENV_PATH")
set +a
MOUNT_POINT=$(shell_quote "$ZEROFS_MOUNT_POINT")
ready="false"
for _ in {1..60}; do
  if /sbin/mount | /usr/bin/grep -Fq " on \${MOUNT_POINT} "; then
    ready="true"
    break
  fi
  /bin/sleep 1
done
if [[ "\${ready}" != "true" ]]; then
  echo "Skipping probe because mount is not ready: \${MOUNT_POINT}" >&2
  exit 75
fi
exec $(shell_quote "$STAGED_PROBE_TOOL") \\
  --profile-id $(shell_quote "$ZEROFS_PROFILE_ID") \\
  --mount-point $(shell_quote "$ZEROFS_MOUNT_POINT") \\
  --size-bytes $(shell_quote "$ZEROFS_PROBE_SIZE_BYTES") \\
  --metrics-port $(shell_quote "$ZEROFS_METRICS_PORT") \\
  --result-dir $(shell_quote "$PROBE_RESULT_ROOT") \\
  --work-dir $(shell_quote "$PROFILE_ROOT/probe-work") \\
  --zerofs-bin $(shell_quote "$STAGED_ZEROFS_BIN") \\
  --config $(shell_quote "$CONFIG_PATH") \\
  --lock-dir $(shell_quote "$PROBE_LOCK_ROOT/$ZEROFS_PROFILE_ID.lock") \\
  --trigger backgroundLaunchDaemon
PROBE

  cat > "$TMP_DIR/probe.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PROBE_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PROBE_SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>$ZEROFS_PROBE_INTERVAL_SECONDS</integer>
  <key>StandardOutPath</key>
  <string>$PROBE_LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$PROBE_LOG_PATH</string>
  <key>WorkingDirectory</key>
  <string>/var/empty</string>
</dict>
</plist>
PLIST
fi

PLISTS_TO_LINT=("$TMP_DIR/runtime.plist" "$TMP_DIR/mount.plist")
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  PLISTS_TO_LINT+=("$TMP_DIR/probe.plist")
fi
plutil -lint "${PLISTS_TO_LINT[@]}"

sudo /bin/mkdir -p "$PROFILE_ROOT" "$LOG_ROOT" "$CACHE_DIR"
if [[ "$MOUNT_POINT_ALREADY_MOUNTED" != "1" ]]; then
  sudo /bin/mkdir -p "$ZEROFS_MOUNT_POINT"
fi
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  sudo /bin/mkdir -p "$PROBE_RESULT_ROOT" "$PROBE_LOCK_ROOT"
fi
sudo /usr/sbin/chown root:wheel "$PROFILE_ROOT" "$LOG_ROOT" "$CACHE_DIR"
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  sudo /usr/sbin/chown root:wheel "$PROBE_RESULT_ROOT"
fi
sudo /bin/chmod 700 "$PROFILE_ROOT"
sudo /bin/chmod 755 "$LOG_ROOT" "$CACHE_DIR"
if [[ "$MOUNT_POINT_ALREADY_MOUNTED" != "1" ]]; then
  sudo /bin/chmod 755 "$ZEROFS_MOUNT_POINT"
fi
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  sudo /bin/chmod 755 "$PROBE_RESULT_ROOT"
  sudo /bin/chmod 1777 "$PROBE_LOCK_ROOT"
fi

sudo /usr/bin/install -o root -g wheel -m 0755 "$ZEROFS_BIN" "$STAGED_ZEROFS_BIN"
assert_root_owned_runtime_file "$STAGED_ZEROFS_BIN"
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  sudo /usr/bin/install -o root -g wheel -m 0755 "$ZEROFS_PROBE_TOOL" "$STAGED_PROBE_TOOL"
  assert_root_owned_runtime_file "$STAGED_PROBE_TOOL"
fi
sudo /usr/bin/install -o root -g wheel -m 0644 "$TMP_DIR/zerofs.toml" "$CONFIG_PATH"
sudo /usr/bin/install -o root -g wheel -m 0600 "$TMP_DIR/zerofs.env" "$ENV_PATH"
sudo /usr/bin/install -o root -g wheel -m 0700 "$TMP_DIR/run-zerofs.sh" "$RUN_SCRIPT"
sudo /usr/bin/install -o root -g wheel -m 0700 "$TMP_DIR/mount-zerofs.sh" "$MOUNT_SCRIPT"
sudo /usr/bin/install -o root -g wheel -m 0700 "$TMP_DIR/flush-zerofs.sh" "$FLUSH_SCRIPT"
sudo /usr/bin/install -o root -g wheel -m 0644 "$TMP_DIR/runtime.plist" "$RUNTIME_PLIST"
sudo /usr/bin/install -o root -g wheel -m 0644 "$TMP_DIR/mount.plist" "$MOUNT_PLIST"
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  sudo /usr/bin/install -o root -g wheel -m 0700 "$TMP_DIR/probe-zerofs.sh" "$PROBE_SCRIPT"
  sudo /usr/bin/install -o root -g wheel -m 0644 "$TMP_DIR/probe.plist" "$PROBE_PLIST"
else
  sudo rm -f "$PROBE_PLIST" "$PROBE_SCRIPT" "$STAGED_PROBE_TOOL"
fi

echo "Runtime config written to: $PROFILE_ROOT"
echo "Secrets are stored in root-only env file: $ENV_PATH"
echo "ZeroFS binary staged to root-owned runtime path: $STAGED_ZEROFS_BIN"
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  echo "Probe tool staged to root-owned runtime path: $STAGED_PROBE_TOOL"
  echo "Probe results will be written to: $PROBE_RESULT_ROOT"
fi
echo "Bootstrapping LaunchDaemons..."

sudo launchctl bootstrap system "$RUNTIME_PLIST"
sudo launchctl bootstrap system "$MOUNT_PLIST"
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  sudo launchctl bootstrap system "$PROBE_PLIST"
fi
sudo launchctl enable "system/$RUNTIME_LABEL" >/dev/null 2>&1 || true
sudo launchctl enable "system/$MOUNT_LABEL" >/dev/null 2>&1 || true
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  sudo launchctl enable "system/$PROBE_LABEL" >/dev/null 2>&1 || true
fi
sudo launchctl kickstart -k "system/$RUNTIME_LABEL"
sudo launchctl kickstart -k "system/$MOUNT_LABEL" >/dev/null 2>&1 || true
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  sudo launchctl kickstart -k "system/$PROBE_LABEL" >/dev/null 2>&1 || true
fi

echo "Installed and restarted:"
echo "  $RUNTIME_LABEL"
echo "  $MOUNT_LABEL"
if [[ "$ZEROFS_PROBE_ENABLED" == "1" ]]; then
  echo "  $PROBE_LABEL"
else
  echo "  probe LaunchDaemon disabled"
fi
redact "Mount point: $ZEROFS_MOUNT_POINT"
