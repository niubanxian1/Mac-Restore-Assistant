#!/bin/bash
# Install the independent MRA device-control helper with a self-contained,
# race-aware rollback. Does not touch com.macrestore.assistant.privileged.
set -euo pipefail

LABEL="com.mra.devicecontrol.helper"
HELPER_DST="/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
BACKEND_DST="/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
PLIST_DST="/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"
SOCKET="/var/run/com.mra.devicecontrol.helper.sock"
BACKUP_DIR="/Users/Shared/MRA_HELPER_ROLLBACK_20261110T1650"
RECORD_DIR="/Users/Shared/MRA_DEVICE_CAPTURE_PROTOTYPE/install-record"

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HERE/MRA Device Control Prototype.app"
HELPER_SRC="$APP_DIR/Contents/Resources/mra-helper"
BACKEND_SRC="$APP_DIR/Contents/Resources/direct_rid_dfu"
PLIST_SRC="$HERE/com.mra.devicecontrol.helper.plist"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

EXPECTED_HELPER="052abc6f028c197172e60d63ed9edd07a05d500eace2bfbf0b508d9dab95bc45"
EXPECTED_BACKEND="6c21e95c8ebedd224c946bc50ee53a5af31c7d00508e0d1ce3bc473b40440f69"
EXPECTED_PLIST="d30e8029aacd1c80e093380a94fe52edb5d378eb90aeed9dc9e2ec6a03805e3e"
EXPECTED_OLD_HELPER="544488c3c51668ec2905bf81f5805ede7580f4e9d01351c85479ec7db34d3986"
EXPECTED_OLD_BACKEND="ce88e7c6dfbd5d840f278e0514ee810c2ee89683e42819283c5727f79cca07db"
EXPECTED_OLD_PLIST="d30e8029aacd1c80e093380a94fe52edb5d378eb90aeed9dc9e2ec6a03805e3e"
ABSENT_TIMEOUT=15
READY_TIMEOUT=15
ROLLBACK_ARMED=0
ROLLBACK_RUNNING=0
ROLLBACK_DONE=0
FAILURE_LOGGED=0
FAIL_LOG=""

sha() { shasum -a 256 "$1" | awk '{print $1}'; }
service_print() { launchctl print "system/$LABEL" 2>&1; }
service_exists() { launchctl print "system/$LABEL" >/dev/null 2>&1; }
pid_of_service() { service_print | awk '/^[[:space:]]*pid = /{print $3; exit}'; }
helper_process_pids() { ps -axo pid=,command= | awk -v p="$HELPER_DST" '$2 == p { print $1 }'; }
socket_has_listener() {
  [ -S "$SOCKET" ] || return 1
  /usr/sbin/lsof "$SOCKET" >/dev/null 2>&1
}

check_file() {
  local file=$1 expected=$2 label=$3
  [ -f "$file" ] || die_preflight "$label missing: $file"
  local actual; actual=$(sha "$file")
  echo "HASH $label $actual"
  [ "$actual" = "$expected" ] || die_preflight "$label hash mismatch (expected $expected)"
}

die_preflight() {
  echo "INSTALL_ABORT: $*" >&2
  exit 1
}

cleanup_stale_socket() {
  if [ -S "$SOCKET" ] && ! socket_has_listener; then
    echo "removing stale socket without listener: $SOCKET"
    rm -f "$SOCKET"
  fi
}

wait_absent() {
  local deadline=$((SECONDS + ABSENT_TIMEOUT))
  local initial_pid; initial_pid=$(pid_of_service || true)
  while [ "$SECONDS" -lt "$deadline" ]; do
    local exists=0 live_pids
    service_exists && exists=1
    live_pids=$(helper_process_pids || true)
    if [ -n "${initial_pid:-}" ] && kill -0 "$initial_pid" 2>/dev/null; then
      :
    elif [ "$exists" -eq 0 ] && [ -z "$live_pids" ]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

wait_socket_released() {
  local deadline=$((SECONDS + ABSENT_TIMEOUT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! socket_has_listener; then return 0; fi
    sleep 0.2
  done
  return 1
}

wait_ready() {
  local deadline=$((SECONDS + READY_TIMEOUT))
  local out
  while [ "$SECONDS" -lt "$deadline" ]; do
    out=$(service_print || true)
    if printf '%s\n' "$out" | grep -q 'state = running' \
       && printf '%s\n' "$out" | grep -q 'pid = ' \
       && socket_has_listener; then
      echo "SERVICE_READY"
      printf '%s\n' "$out" | grep -E 'state =|pid =|program =' | head -5
      return 0
    fi
    sleep 0.2
  done
  return 1
}

log_failure_context() {
  [ "$FAILURE_LOGGED" -eq 1 ] && return 0
  FAILURE_LOGGED=1
  mkdir -p "$BACKUP_DIR"
  FAIL_LOG="$BACKUP_DIR/install-failure-$(date +%Y%m%dT%H%M%S).log"
  {
    echo "=== install/rollback failure $(date '+%F %T %z') ==="
    echo "service: $LABEL"
    echo "socket: $SOCKET"
    echo "--- launchctl print ---"
    service_print || true
    echo "--- launchd/AMFI/syspolicyd excerpt ---"
    log show --last 5m --style compact --predicate \
      'process == "launchd" OR process == "amfid" OR process == "syspolicyd" OR eventMessage CONTAINS[c] "com.mra.devicecontrol.helper"' \
      2>/dev/null | tail -160 || true
    echo "--- filtered diagnostics ---"
    log show --last 5m --style compact --predicate \
      'eventMessage CONTAINS[c] "com.mra.devicecontrol.helper" OR eventMessage CONTAINS[c] "Operation already in progress" OR eventMessage CONTAINS[c] "AMFI" OR eventMessage CONTAINS[c] "syspolicyd"' \
      2>/dev/null | grep -E '37:|5:|AMFI|syspolicyd|launch already|bootstrap|com.mra.devicecontrol.helper' | tail -80 || true
  } >"$FAIL_LOG" 2>&1 || true
  echo "failure log: $FAIL_LOG"
}

rollback_evidence() {
  local result=$1
  mkdir -p "$RECORD_DIR"
  local rec="$RECORD_DIR/rollback-$(date +%Y%m%dT%H%M%S).txt"
  {
    echo "=== rollback $result $(date '+%F %T %z') ==="
    echo "label: $LABEL"
    service_print || true
    echo "helper sha: $(sha "$HELPER_DST" 2>/dev/null || echo MISSING)"
    echo "backend sha: $(sha "$BACKEND_DST" 2>/dev/null || echo MISSING)"
    echo "plist sha: $(sha "$PLIST_DST" 2>/dev/null || echo MISSING)"
    echo "--- codesign ---"
    codesign -dvvv "$HELPER_DST" 2>&1 | grep -E 'Identifier|TeamIdentifier|CDHash' || true
    echo "--- socket ---"
    [ -S "$SOCKET" ] && echo "socket exists" || echo "socket missing"
  } >"$rec" 2>&1 || true
  echo "rollback evidence: $rec"
}

perform_rollback() {
  if [ "$ROLLBACK_RUNNING" -eq 1 ] || [ "$ROLLBACK_DONE" -eq 1 ]; then
    return 1
  fi
  ROLLBACK_RUNNING=1
  set +e
  echo "=== ROBUST ROLLBACK ==="
  local ok=1
  local step_ok

  launchctl bootout "system/$LABEL" 2>/dev/null || true

  if ! wait_absent; then
    echo "ROLLBACK_FAILED: label still present or real process still alive" >&2
    ok=0
  fi
  if [ "$ok" -eq 1 ] && ! wait_socket_released; then
    echo "ROLLBACK_FAILED: old socket still has a listener" >&2
    ok=0
  fi
  [ "$ok" -eq 1 ] && cleanup_stale_socket

  if [ "$ok" -eq 1 ]; then
    install -o root -g wheel -m 755 "$BACKUP_DIR/com.mra.devicecontrol.helper" "$HELPER_DST" || ok=0
    install -o root -g wheel -m 755 "$BACKUP_DIR/com.mra.direct_rid_dfu" "$BACKEND_DST" || ok=0
    install -o root -g wheel -m 644 "$BACKUP_DIR/com.mra.devicecontrol.helper.plist" "$PLIST_DST" || ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    [ "$(sha "$HELPER_DST")" = "$EXPECTED_OLD_HELPER" ] || ok=0
    [ "$(sha "$BACKEND_DST")" = "$EXPECTED_OLD_BACKEND" ] || ok=0
    [ "$(sha "$PLIST_DST")" = "$EXPECTED_OLD_PLIST" ] || ok=0
    codesign --verify --strict "$HELPER_DST" >/dev/null 2>&1 || ok=0
    codesign --verify --strict "$BACKEND_DST" >/dev/null 2>&1 || ok=0
    plutil -lint "$PLIST_DST" >/dev/null 2>&1 || ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    # One bootstrap attempt only. No retry loop.
    if ! launchctl bootstrap system "$PLIST_DST"; then
      echo "ROLLBACK_FAILED: bootstrap of old plist failed" >&2
      ok=0
    fi
  fi
  if [ "$ok" -eq 1 ]; then
    if ! wait_ready; then
      echo "ROLLBACK_FAILED: old service not running with PID/socket" >&2
      ok=0
    fi
  fi

  if [ "$ok" -eq 1 ]; then
    rollback_evidence SUCCESS
    echo "ROLLBACK_OK"
  else
    rollback_evidence FAILURE
    echo "ROLLBACK_FAILED: SYSTEM HAS NO HELPER" >&2
  fi
  ROLLBACK_DONE=1
  ROLLBACK_RUNNING=0
  set -e
  [ "$ok" -eq 1 ] && return 0 || return 1
}

on_err() {
  local rc=$?
  if [ "$ROLLBACK_RUNNING" -eq 1 ] || [ "$ROLLBACK_DONE" -eq 1 ]; then
    return "$rc"
  fi
  if [ "$ROLLBACK_ARMED" -eq 1 ]; then
    log_failure_context
    perform_rollback || rc=1
  fi
  exit "$rc"
}

on_exit() {
  local rc=$?
  trap - ERR EXIT
  if [ "$rc" -ne 0 ] && [ "$ROLLBACK_ARMED" -eq 1 ] && [ "$ROLLBACK_RUNNING" -eq 0 ] && [ "$ROLLBACK_DONE" -eq 0 ]; then
    log_failure_context
    perform_rollback || rc=1
  fi
  exit "$rc"
}

# ---------- preflight (no trap yet; no system changes) ----------
echo "=== PREFLIGHT ==="
check_file "$HELPER_SRC" "$EXPECTED_HELPER" candidate-helper
check_file "$BACKEND_SRC" "$EXPECTED_BACKEND" candidate-backend
check_file "$PLIST_SRC" "$EXPECTED_PLIST" candidate-plist
check_file "$BACKUP_DIR/com.mra.devicecontrol.helper" "$EXPECTED_OLD_HELPER" backup-helper
check_file "$BACKUP_DIR/com.mra.direct_rid_dfu" "$EXPECTED_OLD_BACKEND" backup-backend
check_file "$BACKUP_DIR/com.mra.devicecontrol.helper.plist" "$EXPECTED_OLD_PLIST" backup-plist
codesign --verify --strict "$HELPER_SRC"
codesign --verify --strict "$BACKEND_SRC"
codesign --verify --strict --deep "$APP_DIR"
plutil -lint "$PLIST_SRC"
plutil -lint "$BACKUP_DIR/com.mra.devicecontrol.helper.plist"
echo "preflight OK"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "=== DRY RUN: no launchctl/system changes ==="
  echo "would arm EXIT/ERR rollback before bootout"
  echo "would bootout: $LABEL"
  echo "would wait absent/process exit/socket release ${ABSENT_TIMEOUT}s"
  echo "would install: $HELPER_DST"
  echo "would install: $BACKEND_DST"
  echo "would install: $PLIST_DST"
  echo "would verify installed hashes/codesign/plutil"
  echo "would bootstrap once and wait ${READY_TIMEOUT}s"
  echo "on failure: log launchd/AMFI/syspolicyd, robust rollback, no retry"
  echo "DRY_RUN_OK"
  exit 0
fi

[ "$(id -u)" -eq 0 ] || die_preflight "run as root: sudo $0"

# Arm only before the first system-changing operation.
ROLLBACK_ARMED=1
trap on_err ERR
trap on_exit EXIT

mkdir -p "$RECORD_DIR"
service_print > "$RECORD_DIR/launchctl-preinstall-$(date +%Y%m%dT%H%M%S).txt" 2>&1 || true

echo "=== BOOTOUT ==="
launchctl bootout "system/$LABEL" 2>/dev/null || true
if ! wait_absent; then
  log_failure_context
  exit 1
fi
echo "service absent"
if ! wait_socket_released; then
  log_failure_context
  exit 1
fi
cleanup_stale_socket
echo "socket released"

echo "=== COPY ==="
install -o root -g wheel -m 755 "$HELPER_SRC" "$HELPER_DST"
install -o root -g wheel -m 755 "$BACKEND_SRC" "$BACKEND_DST"
install -o root -g wheel -m 644 "$PLIST_SRC" "$PLIST_DST"

echo "=== VERIFY INSTALLED PATHS ==="
check_file "$HELPER_DST" "$EXPECTED_HELPER" installed-helper
check_file "$BACKEND_DST" "$EXPECTED_BACKEND" installed-backend
check_file "$PLIST_DST" "$EXPECTED_PLIST" installed-plist
codesign --verify --strict "$HELPER_DST"
codesign --verify --strict "$BACKEND_DST"
plutil -lint "$PLIST_DST"
echo "installed files verified"

echo "=== BOOTSTRAP (ONCE) ==="
if ! launchctl bootstrap system "$PLIST_DST"; then
  log_failure_context
  exit 1
fi
if ! wait_ready; then
  log_failure_context
  exit 1
fi

echo "=== INSTALLED ==="
echo "label: $LABEL"
service_print | grep -E 'state =|pid =|program =' | head -5
echo "helper CDHash:"
codesign -dvvv "$HELPER_DST" 2>&1 | grep -E 'CDHash=' | head -1 || true
echo "installed helper sha: $(sha "$HELPER_DST")"
echo "installed backend sha: $(sha "$BACKEND_DST")"
echo "installed plist sha: $(sha "$PLIST_DST")"
RECORD="$RECORD_DIR/install-success-$(date +%Y%m%dT%H%M%S).txt"
{
  echo "label: $LABEL"
  service_print || true
  echo "helper sha: $(sha "$HELPER_DST")"
  echo "backend sha: $(sha "$BACKEND_DST")"
  echo "plist sha: $(sha "$PLIST_DST")"
  codesign -dvvv "$HELPER_DST" 2>&1 | grep -E 'Identifier|TeamIdentifier|CDHash' || true
} > "$RECORD"
echo "record: $RECORD"
ROLLBACK_ARMED=0
echo "INSTALL_OK"
