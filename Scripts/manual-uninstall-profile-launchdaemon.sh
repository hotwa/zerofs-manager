#!/usr/bin/env bash
set -euo pipefail

PROFILE_ID=""
MOUNT_POINT=""
KEEP_RUNTIME=0

usage() {
  cat <<'USAGE'
Usage: Scripts/manual-uninstall-profile-launchdaemon.sh --profile-id PROFILE_ID [--mount-point /Volumes/ZeroFS-Name] [--keep-runtime]

Removes a GitHub-style sudo-authorized LaunchDaemon profile. By default it
stops launchd jobs, unmounts the profile mount point when known, removes plist
files, and deletes the root-owned runtime directory containing secrets.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id)
      PROFILE_ID="${2:-}"
      shift 2
      ;;
    --mount-point)
      MOUNT_POINT="${2:-}"
      shift 2
      ;;
    --keep-runtime)
      KEEP_RUNTIME=1
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

[[ -n "$PROFILE_ID" ]] || {
  echo "Missing --profile-id" >&2
  usage >&2
  exit 2
}

[[ "$PROFILE_ID" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || {
  echo "Invalid profile id: $PROFILE_ID" >&2
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

is_trusted_root_env() {
  local path="$1"
  local metadata
  sudo test -f "$path" || return 1
  sudo test ! -L "$path" || return 1
  metadata="$(sudo /usr/bin/stat -f '%Su:%Sg:%Lp' "$path" 2>/dev/null || true)"
  [[ "$metadata" == "root:wheel:600" ]]
}

read_trusted_mount_point() {
  local path="$1"
  if ! is_trusted_root_env "$path"; then
    return 1
  fi
  sudo /bin/zsh -c 'set -euo pipefail; source "$1"; printf "%s" "${ZEROFS_MOUNT_POINT:-}"' zerofs-manager "$path" 2>/dev/null
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

LABEL_PREFIX="com.zerofs.manager.profile.$PROFILE_ID"
RUNTIME_LABEL="$LABEL_PREFIX.zerofs"
MOUNT_LABEL="$LABEL_PREFIX.mount"
PROBE_LABEL="$LABEL_PREFIX.probe"
PROFILE_ROOT="/Library/Application Support/ZeroFSManager/Profiles/$PROFILE_ID"
PROBE_RESULT_ROOT="/Library/Application Support/ZeroFSManager/ProbeResults/$PROFILE_ID"
PROBE_LOCK_ROOT="/tmp/zerofs-manager-probe-locks"
CACHE_DIR="/var/cache/zerofs-manager/$PROFILE_ID"
LOG_ROOT="/Library/Logs/ZeroFSManager/$PROFILE_ID"
ENV_PATH="$PROFILE_ROOT/zerofs.env"
RUNTIME_PLIST="/Library/LaunchDaemons/$RUNTIME_LABEL.plist"
MOUNT_PLIST="/Library/LaunchDaemons/$MOUNT_LABEL.plist"
PROBE_PLIST="/Library/LaunchDaemons/$PROBE_LABEL.plist"

if [[ -n "$MOUNT_POINT" ]] && ! is_safe_mount_point "$MOUNT_POINT"; then
  echo "Refusing unsafe mount point: $MOUNT_POINT" >&2
  exit 2
fi

echo "Removing ZeroFS Manager LaunchDaemons for profile: $PROFILE_ID"
sudo -v

if [[ -z "$MOUNT_POINT" ]] && sudo test -e "$ENV_PATH"; then
  MOUNT_POINT="$(read_trusted_mount_point "$ENV_PATH" || true)"
  if [[ -z "$MOUNT_POINT" ]]; then
    echo "Skipping mount point lookup because existing env is missing or not root:wheel 0600: $ENV_PATH" >&2
  fi
fi

bootout_job "$PROBE_LABEL" "$PROBE_PLIST"
bootout_job "$MOUNT_LABEL" "$MOUNT_PLIST"
bootout_job "$RUNTIME_LABEL" "$RUNTIME_PLIST"
ensure_job_unloaded "$PROBE_LABEL"
ensure_job_unloaded "$MOUNT_LABEL"
ensure_job_unloaded "$RUNTIME_LABEL"

if [[ -n "$MOUNT_POINT" ]] && ! is_safe_mount_point "$MOUNT_POINT"; then
  echo "Refusing unsafe mount point: $MOUNT_POINT" >&2
  exit 2
fi

if [[ -n "$MOUNT_POINT" ]] && /sbin/mount | /usr/bin/grep -Fq " on $MOUNT_POINT "; then
  echo "Unmounting: $MOUNT_POINT"
  sudo /sbin/umount "$MOUNT_POINT" >/dev/null 2>&1 || true
fi

sudo rm -f "$PROBE_PLIST" "$MOUNT_PLIST" "$RUNTIME_PLIST"
case "$PROBE_LOCK_ROOT/$PROFILE_ID.lock" in
  "/tmp/zerofs-manager-probe-locks/$PROFILE_ID.lock")
    sudo rm -rf "$PROBE_LOCK_ROOT/$PROFILE_ID.lock"
    ;;
esac

if [[ "$KEEP_RUNTIME" != "1" ]]; then
  case "$PROFILE_ROOT" in
    "/Library/Application Support/ZeroFSManager/Profiles/$PROFILE_ID")
      sudo rm -rf "$PROFILE_ROOT"
      ;;
  esac
  case "$CACHE_DIR" in
    "/var/cache/zerofs-manager/$PROFILE_ID")
      sudo rm -rf "$CACHE_DIR"
      ;;
  esac
  case "$LOG_ROOT" in
    "/Library/Logs/ZeroFSManager/$PROFILE_ID")
      sudo rm -rf "$LOG_ROOT"
      ;;
  esac
  case "$PROBE_RESULT_ROOT" in
    "/Library/Application Support/ZeroFSManager/ProbeResults/$PROFILE_ID")
      sudo rm -rf "$PROBE_RESULT_ROOT"
      ;;
  esac
fi

echo "Removed:"
echo "  $RUNTIME_LABEL"
echo "  $MOUNT_LABEL"
echo "  $PROBE_LABEL"
