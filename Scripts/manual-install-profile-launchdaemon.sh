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

LABEL_PREFIX="com.zerofs.manager.profile.$ZEROFS_PROFILE_ID"
RUNTIME_LABEL="$LABEL_PREFIX.zerofs"
MOUNT_LABEL="$LABEL_PREFIX.mount"
PROFILE_ROOT="/Library/Application Support/ZeroFSManager/Profiles/$ZEROFS_PROFILE_ID"
LOG_ROOT="/Library/Logs/ZeroFSManager/$ZEROFS_PROFILE_ID"
CACHE_DIR="${ZEROFS_CACHE_DIR:-/var/cache/zerofs-manager/$ZEROFS_PROFILE_ID}"
CONFIG_PATH="$PROFILE_ROOT/zerofs.toml"
ENV_PATH="$PROFILE_ROOT/zerofs.env"
RUN_SCRIPT="$PROFILE_ROOT/run-zerofs.sh"
MOUNT_SCRIPT="$PROFILE_ROOT/mount-zerofs.sh"
FLUSH_SCRIPT="$PROFILE_ROOT/flush-zerofs.sh"
RUNTIME_PLIST="/Library/LaunchDaemons/$RUNTIME_LABEL.plist"
MOUNT_PLIST="/Library/LaunchDaemons/$MOUNT_LABEL.plist"
LOG_PATH="$LOG_ROOT/zerofs.log"
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

echo "Installing ZeroFS Manager LaunchDaemons for profile: $ZEROFS_PROFILE_ID"
echo "This path uses sudo and launchd directly. It does not require Apple Developer ID or SMAppService."
sudo -v

OLD_MOUNT_POINT=""
if sudo test -f "$ENV_PATH"; then
  OLD_MOUNT_POINT="$(sudo /bin/zsh -c 'source "$1"; printf "%s" "${ZEROFS_MOUNT_POINT:-}"' zerofs-manager "$ENV_PATH" 2>/dev/null || true)"
fi
if [[ -n "$OLD_MOUNT_POINT" ]] && ! is_safe_mount_point "$OLD_MOUNT_POINT"; then
  echo "Skipping unsafe previous mount point from existing env: $OLD_MOUNT_POINT" >&2
  OLD_MOUNT_POINT=""
fi

sudo launchctl bootout system "$MOUNT_PLIST" >/dev/null 2>&1 || true
sudo launchctl bootout system "$RUNTIME_PLIST" >/dev/null 2>&1 || true

if [[ -n "$OLD_MOUNT_POINT" && "$OLD_MOUNT_POINT" != "$ZEROFS_MOUNT_POINT" ]]; then
  if /sbin/mount | /usr/bin/grep -Fq " on $OLD_MOUNT_POINT "; then
    echo "Unmounting previous mount point: $OLD_MOUNT_POINT"
    sudo /sbin/umount "$OLD_MOUNT_POINT" >/dev/null 2>&1 || true
  fi
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
ENV

cat > "$TMP_DIR/run-zerofs.sh" <<RUN
#!/bin/zsh
set -euo pipefail
set -a
source $(shell_quote "$ENV_PATH")
set +a
exec $(shell_quote "$ZEROFS_BIN") run --config $(shell_quote "$CONFIG_PATH")
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
exec $(shell_quote "$ZEROFS_BIN") flush --config $(shell_quote "$CONFIG_PATH")
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

plutil -lint "$TMP_DIR/runtime.plist" "$TMP_DIR/mount.plist"

sudo /bin/mkdir -p "$PROFILE_ROOT" "$LOG_ROOT" "$CACHE_DIR" "$ZEROFS_MOUNT_POINT"
sudo /usr/sbin/chown root:wheel "$PROFILE_ROOT" "$LOG_ROOT" "$CACHE_DIR"
sudo /bin/chmod 700 "$PROFILE_ROOT"
sudo /bin/chmod 755 "$LOG_ROOT" "$CACHE_DIR" "$ZEROFS_MOUNT_POINT"

sudo /usr/bin/install -o root -g wheel -m 0644 "$TMP_DIR/zerofs.toml" "$CONFIG_PATH"
sudo /usr/bin/install -o root -g wheel -m 0600 "$TMP_DIR/zerofs.env" "$ENV_PATH"
sudo /usr/bin/install -o root -g wheel -m 0700 "$TMP_DIR/run-zerofs.sh" "$RUN_SCRIPT"
sudo /usr/bin/install -o root -g wheel -m 0700 "$TMP_DIR/mount-zerofs.sh" "$MOUNT_SCRIPT"
sudo /usr/bin/install -o root -g wheel -m 0700 "$TMP_DIR/flush-zerofs.sh" "$FLUSH_SCRIPT"
sudo /usr/bin/install -o root -g wheel -m 0644 "$TMP_DIR/runtime.plist" "$RUNTIME_PLIST"
sudo /usr/bin/install -o root -g wheel -m 0644 "$TMP_DIR/mount.plist" "$MOUNT_PLIST"

echo "Runtime config written to: $PROFILE_ROOT"
echo "Secrets are stored in root-only env file: $ENV_PATH"
echo "Bootstrapping LaunchDaemons..."

sudo launchctl bootstrap system "$RUNTIME_PLIST"
sudo launchctl bootstrap system "$MOUNT_PLIST"
sudo launchctl enable "system/$RUNTIME_LABEL" >/dev/null 2>&1 || true
sudo launchctl enable "system/$MOUNT_LABEL" >/dev/null 2>&1 || true
sudo launchctl kickstart -k "system/$RUNTIME_LABEL"
sudo launchctl kickstart -k "system/$MOUNT_LABEL" >/dev/null 2>&1 || true

echo "Installed and restarted:"
echo "  $RUNTIME_LABEL"
echo "  $MOUNT_LABEL"
redact "Mount point: $ZEROFS_MOUNT_POINT"
