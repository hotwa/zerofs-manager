#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=""
WORK_ROOT="${WORK_ROOT:-$(mktemp -d)}"
ZEROFS_PID=""
MOUNTED_BY_SCRIPT=0
DELETE_ENV_ON_EXIT=0

usage() {
  cat <<'USAGE'
Usage: Scripts/manual-mount-test.sh --env .env.local [--keep-mounted] [--delete-env-on-exit]

Debug-only manual S3/ZeroFS mount smoke test. This bypasses the app,
Apple signing, notarization, and SMAppService.
USAGE
}

KEEP_MOUNTED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --keep-mounted)
      KEEP_MOUNTED=1
      shift
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
  set +e
  if [[ "$KEEP_MOUNTED" != "1" && "$MOUNTED_BY_SCRIPT" == "1" && -n "${ZEROFS_MOUNT_POINT:-}" ]]; then
    sudo /sbin/umount "$ZEROFS_MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "$ZEROFS_PID" ]]; then
    kill "$ZEROFS_PID" >/dev/null 2>&1 || true
    wait "$ZEROFS_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$DELETE_ENV_ON_EXIT" == "1" && -n "$ENV_FILE" ]]; then
    rm -f "$ENV_FILE"
  fi
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

set -a
source "$ENV_FILE"
set +a

ZEROFS_BIN="${ZEROFS_BIN:-/usr/local/bin/zerofs}"
ZEROFS_MOUNT_POINT="${ZEROFS_MOUNT_POINT:-/Volumes/ZeroFS-Test}"
ZEROFS_NFS_PORT="${ZEROFS_NFS_PORT:-12049}"
ZEROFS_RPC_PORT="${ZEROFS_RPC_PORT:-17000}"
ZEROFS_METRICS_PORT="${ZEROFS_METRICS_PORT:-19091}"
ZEROFS_CACHE_DIR="${ZEROFS_CACHE_DIR:-$WORK_ROOT/cache}"
S3_PREFIX="${S3_PREFIX:-}"
S3_REGION="${S3_REGION:-us-east-1}"
ZEROFS_PASSWORD="${ZEROFS_PASSWORD:-${ZEROFS_ENCRYPTION_PASSWORD:-}}"
TEST_SIZE_MB="${TEST_SIZE_MB:-16}"

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env var: $name" >&2
    exit 2
  fi
}

for name in ZEROFS_BIN ZEROFS_MOUNT_POINT S3_ENDPOINT S3_BUCKET S3_ACCESS_KEY S3_SECRET_KEY ZEROFS_PASSWORD; do
  require_var "$name"
done

[[ -x "$ZEROFS_BIN" ]] || {
  echo "ZeroFS binary not executable: $ZEROFS_BIN" >&2
  exit 2
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

log() {
  redact "$*"
}

mkdir -p "$WORK_ROOT" "$ZEROFS_CACHE_DIR"
CONFIG_PATH="$WORK_ROOT/zerofs.toml"
STORAGE_PREFIX=""
if [[ -n "$S3_PREFIX" ]]; then
  STORAGE_PREFIX="/$S3_PREFIX"
fi

cat > "$CONFIG_PATH" <<CONFIG
[cache]
dir = "$ZEROFS_CACHE_DIR"
disk_size_gb = 10
memory_size_gb = 0.5

[storage]
url = "s3://$S3_BUCKET$STORAGE_PREFIX"
encryption_password = "\${ZEROFS_PASSWORD}"

[filesystem]
max_size_gb = 1024
compression = "zstd-3"

[aws]
access_key_id = "\${AWS_ACCESS_KEY_ID}"
secret_access_key = "\${AWS_SECRET_ACCESS_KEY}"
endpoint = "$S3_ENDPOINT"
region = "$S3_REGION"

[servers.nfs]
addresses = ["127.0.0.1:$ZEROFS_NFS_PORT"]

[servers.rpc]
addresses = ["127.0.0.1:$ZEROFS_RPC_PORT"]
unix_socket = "$WORK_ROOT/zerofs.rpc.sock"

[prometheus]
addresses = ["127.0.0.1:$ZEROFS_METRICS_PORT"]

[telemetry]
enabled = false
CONFIG
chmod 600 "$CONFIG_PATH"

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
export ZEROFS_PASSWORD

log "Manual ZeroFS mount smoke test"
log "Mode: GitHub-style dev, no Apple Developer ID, no SMAppService"
log "ZeroFS: $("$ZEROFS_BIN" --version 2>&1 | tail -n 1 || true)"
log "Endpoint TLS reachability: $S3_ENDPOINT"
curl -I -sS --connect-timeout 5 "$S3_ENDPOINT" >/dev/null || {
  log "Endpoint is not reachable over TLS/HTTP: $S3_ENDPOINT"
  exit 1
}

log "Starting: zerofs run --config $CONFIG_PATH"
"$ZEROFS_BIN" run --config "$CONFIG_PATH" >"$WORK_ROOT/zerofs.log" 2>&1 &
ZEROFS_PID="$!"

ready=0
for _ in {1..60}; do
  if /usr/bin/nc -z 127.0.0.1 "$ZEROFS_NFS_PORT" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != "1" ]]; then
  log "ZeroFS NFS port did not become ready. Recent log:"
  redact "$(tail -n 80 "$WORK_ROOT/zerofs.log" 2>/dev/null || true)"
  exit 1
fi

sudo /bin/mkdir -p "$ZEROFS_MOUNT_POINT"
if ! /sbin/mount | /usr/bin/grep -Fq " on $ZEROFS_MOUNT_POINT "; then
  NFS_OPTIONS="async,nolocks,vers=3,tcp,port=$ZEROFS_NFS_PORT,mountport=$ZEROFS_NFS_PORT,hard,rsize=1048576,wsize=1048576"
  sudo /sbin/mount -t nfs -o "$NFS_OPTIONS" "127.0.0.1:/" "$ZEROFS_MOUNT_POINT"
  MOUNTED_BY_SCRIPT=1
fi

log "Mounted:"
/sbin/mount | /usr/bin/grep -F " on $ZEROFS_MOUNT_POINT " || true
df -h "$ZEROFS_MOUNT_POINT"

TOKEN="$(uuidgen)"
REMOTE_FILE="$ZEROFS_MOUNT_POINT/.zerofs-manager-manual-$TOKEN.bin"
READBACK_FILE="$WORK_ROOT/readback-$TOKEN.bin"

log "Writing ${TEST_SIZE_MB}MiB test file"
sudo /bin/dd if=/dev/zero of="$REMOTE_FILE" bs=1m count="$TEST_SIZE_MB" status=progress
sync
"$ZEROFS_BIN" flush --config "$CONFIG_PATH"
sudo /bin/cp "$REMOTE_FILE" "$READBACK_FILE"

REMOTE_SHA="$(sudo /usr/bin/shasum -a 256 "$REMOTE_FILE" | awk '{print $1}')"
READBACK_SHA="$(/usr/bin/shasum -a 256 "$READBACK_FILE" | awk '{print $1}')"
if [[ "$REMOTE_SHA" != "$READBACK_SHA" ]]; then
  echo "Checksum mismatch" >&2
  exit 1
fi

sudo /bin/rm -f "$REMOTE_FILE"
rm -f "$READBACK_FILE"
sync
df -h "$ZEROFS_MOUNT_POINT"

if [[ "$KEEP_MOUNTED" == "1" ]]; then
  log "Manual mount test passed; mount kept at $ZEROFS_MOUNT_POINT"
else
  sudo /sbin/umount "$ZEROFS_MOUNT_POINT"
  MOUNTED_BY_SCRIPT=0
  log "Manual mount test passed and unmounted $ZEROFS_MOUNT_POINT"
fi
