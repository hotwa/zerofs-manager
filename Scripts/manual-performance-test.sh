#!/usr/bin/env bash
set -euo pipefail

MOUNT_PATH="/Volumes/ZeroFS-Test"
SIZE_TEXT="128M"
CONFIRM_LARGE=0
UNMOUNT_AFTER=1
ALLOW_NON_ZEROFS_MOUNT=0
WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
SIZE_BYTES_DEFAULT=$((128 * 1024 * 1024))

usage() {
  cat <<'USAGE'
Usage: Scripts/manual-performance-test.sh --mount-point /Volumes/ZeroFS-Test [--size 128M] [--confirm-large-test] [--skip-unmount] [--allow-non-zerofs-mount]

Runs a small real-filesystem performance smoke test against an already mounted
ZeroFS path. Large tests such as --size 1024M require --confirm-large-test.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mount-point)
      MOUNT_PATH="${2:-}"
      shift 2
      ;;
    --size)
      SIZE_TEXT="${2:-}"
      shift 2
      ;;
    --confirm-large-test)
      CONFIRM_LARGE=1
      shift
      ;;
    --skip-unmount)
      UNMOUNT_AFTER=0
      shift
      ;;
    --allow-non-zerofs-mount)
      ALLOW_NON_ZEROFS_MOUNT=1
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

parse_size_bytes() {
  local value="$1"
  case "$value" in
    *[Mm])
      [[ "${value%[Mm]}" =~ ^[0-9]+$ ]] || return 1
      echo "$((${value%[Mm]} * 1024 * 1024))"
      ;;
    *[Gg])
      [[ "${value%[Gg]}" =~ ^[0-9]+$ ]] || return 1
      echo "$((${value%[Gg]} * 1024 * 1024 * 1024))"
      ;;
    *)
      [[ "$value" =~ ^[0-9]+$ ]] || return 1
      echo "$value"
      ;;
  esac
}

if ! SIZE_BYTES="$(parse_size_bytes "$SIZE_TEXT")" || [[ "$SIZE_BYTES" -le 0 || "$SIZE_BYTES" -lt 1048576 ]]; then
  echo "Invalid --size: $SIZE_TEXT" >&2
  exit 2
fi
if [[ "$SIZE_BYTES" -gt $((512 * 1024 * 1024)) && "$CONFIRM_LARGE" != "1" ]]; then
  echo "Large tests require --confirm-large-test. Requested: $SIZE_TEXT" >&2
  exit 2
fi

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

[[ -d "$MOUNT_PATH" ]] || {
  echo "Mount path does not exist: $MOUNT_PATH" >&2
  exit 2
}
MOUNT_LINE="$(/sbin/mount | /usr/bin/grep -F " on $MOUNT_PATH " | head -n 1 || true)"
[[ -n "$MOUNT_LINE" ]] || {
  echo "Path is not mounted: $MOUNT_PATH" >&2
  exit 2
}
if [[ "$ALLOW_NON_ZEROFS_MOUNT" != "1" ]]; then
  if [[ "$MOUNT_LINE" != *"127.0.0.1:/"* || "$MOUNT_LINE" != *"nfs"* ]]; then
    echo "Mount point does not look like a local ZeroFS/NFS mount: $MOUNT_LINE" >&2
    echo "Use --allow-non-zerofs-mount only for an intentional test scratch volume." >&2
    exit 2
  fi
fi

mkdir -p "$WORK_DIR"
TOKEN="$(uuidgen)"
REMOTE_FILE="$MOUNT_PATH/.zerofs-manager-perf-$TOKEN.bin"
READBACK_FILE="$WORK_DIR/readback-$TOKEN.bin"
SMALL_DIR="$MOUNT_PATH/.zerofs-manager-small-files-$TOKEN"

cleanup_remote() {
  set +e
  sudo /bin/rm -f "$REMOTE_FILE"
  sudo /bin/rm -rf "$SMALL_DIR"
  if [[ "$UNMOUNT_AFTER" == "1" ]]; then
    sudo /sbin/umount "$MOUNT_PATH" >/dev/null 2>&1 || true
  fi
}
trap 'cleanup_remote; cleanup' EXIT

echo "Manual ZeroFS performance test"
echo "Mount point: $MOUNT_PATH"
echo "Size: $SIZE_TEXT"
echo

echo "df before write"
df -h "$MOUNT_PATH"

echo "sequential write"
WRITE_START="$(date +%s)"
sudo /bin/dd if=/dev/zero of="$REMOTE_FILE" bs=1m count="$((SIZE_BYTES / 1024 / 1024))" status=progress
sync
if [[ -n "${ZEROFS_BIN:-}" && -n "${ZEROFS_CONFIG:-}" && -x "${ZEROFS_BIN:-}" ]]; then
  "$ZEROFS_BIN" flush --config "$ZEROFS_CONFIG"
fi
WRITE_END="$(date +%s)"

echo "df after write"
df -h "$MOUNT_PATH"

echo "sequential read"
READ_START="$(date +%s)"
sudo /bin/cp "$REMOTE_FILE" "$READBACK_FILE"
READ_END="$(date +%s)"

REMOTE_SHA="$(sudo /usr/bin/shasum -a 256 "$REMOTE_FILE" | awk '{print $1}')"
READBACK_SHA="$(/usr/bin/shasum -a 256 "$READBACK_FILE" | awk '{print $1}')"
if [[ "$REMOTE_SHA" != "$READBACK_SHA" ]]; then
  echo "Checksum mismatch" >&2
  exit 1
fi

echo "small files create/read/delete"
sudo /bin/mkdir -p "$SMALL_DIR"
for i in $(seq 1 100); do
  printf "small files %s %s\n" "$TOKEN" "$i" | sudo /usr/bin/tee "$SMALL_DIR/file-$i.txt" >/dev/null
done
for i in $(seq 1 100); do
  sudo /bin/cat "$SMALL_DIR/file-$i.txt" >/dev/null
done
sudo /bin/rm -rf "$SMALL_DIR"

sudo /bin/rm -f "$REMOTE_FILE"
rm -f "$READBACK_FILE"
sync

echo "df after cleanup"
df -h "$MOUNT_PATH"

WRITE_SECONDS=$((WRITE_END - WRITE_START))
READ_SECONDS=$((READ_END - READ_START))
echo "Manual performance test passed"
echo "Write seconds: $WRITE_SECONDS"
echo "Read seconds: $READ_SECONDS"

if [[ "$UNMOUNT_AFTER" == "1" ]]; then
  sudo /sbin/umount "$MOUNT_PATH"
  echo "Unmounted $MOUNT_PATH"
else
  echo "Skipped unmount for $MOUNT_PATH"
fi
