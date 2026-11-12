#!/bin/bash
# Install the independent MRA device-control helper with a self-contained,
# race-aware rollback. Does not touch com.macrestore.assistant.privileged.
# 0.2.2: hash and signature pre-checks complete before any quarantine prompt.
# This package does not depend on the 0.2.1 development-machine BACKUP_DIR.
# This script never changes Gatekeeper, AMFI, spctl, or SIP, never reinstalls
# a Helper unless this script is explicitly executed, and never issues
# DFU/Reboot/Restore commands.
set -euo pipefail

LABEL="com.mra.devicecontrol.helper"
: "${HELPER_DST:=/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper}"
: "${BACKEND_DST:=/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu}"
: "${PLIST_DST:=/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist}"
: "${SOCKET:=/var/run/com.mra.devicecontrol.helper.sock}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${RECORD_DIR:=$HERE/install-record}"
PACKAGE_BACKUP="$RECORD_DIR/pre-install-backup"
APP_DIR=""
if [ -n "${MRA_APP_DIR:-}" ] && [ -d "$MRA_APP_DIR" ]; then
  APP_DIR="$MRA_APP_DIR"
fi
if [ -z "$APP_DIR" ]; then
for CANDIDATE in \
  "$HERE/牛半仙Mac维修辅助工具.app" \
  "$HERE/Candidate/牛半仙Mac维修辅助工具.app" \
  "$HERE/MRA Device Control Prototype.app" \
  "$HERE/Candidate/MRA Device Control Prototype.app"; do
  if [ -d "$CANDIDATE" ]; then
    APP_DIR="$CANDIDATE"
    break
  fi
done
if [ -z "$APP_DIR" ]; then
  APP_DIR="$HERE/牛半仙Mac维修辅助工具.app"
fi
fi
HELPER_SRC="$APP_DIR/Contents/Resources/mra-helper"
BACKEND_SRC="$APP_DIR/Contents/Resources/direct_rid_dfu"
APP_INFO="$APP_DIR/Contents/Info.plist"
APP_BIN="$APP_DIR/Contents/MacOS/DeviceCapturePrototype"
if [ -f "$HERE/com.mra.devicecontrol.helper.plist" ]; then
  PLIST_SRC="$HERE/com.mra.devicecontrol.helper.plist"
elif [ -f "$HERE/Candidate/com.mra.devicecontrol.helper.plist" ]; then
  PLIST_SRC="$HERE/Candidate/com.mra.devicecontrol.helper.plist"
else
  PLIST_SRC="$HERE/com.mra.devicecontrol.helper.plist"
fi

: "${XATTR_BIN:=/usr/bin/xattr}"
: "${FIND_BIN:=/usr/bin/find}"
: "${VTOOL_BIN:=/usr/bin/vtool}"
: "${SW_VERS_BIN:=/usr/bin/sw_vers}"
: "${PLUTIL_BIN:=/usr/bin/plutil}"
: "${SORT_BIN:=/usr/bin/sort}"
: "${LAUNCHCTL_BIN:=/bin/launchctl}"
: "${PS_BIN:=/bin/ps}"
: "${LSOF_BIN:=/usr/sbin/lsof}"
: "${RM_BIN:=/bin/rm}"
: "${INSTALL_BIN:=/usr/bin/install}"
: "${CODESIGN_BIN:=/usr/bin/codesign}"
: "${SHA_BIN:=/usr/bin/shasum}"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

EXPECTED_HELPER="c81917fd26bbcd20b023569a0e6e5abddd510c0a0994d18ed482132b82ac0d58"
EXPECTED_BACKEND="ea512931a2793de2bc18fcd7b2b2a539d7964336b2696d75662b7d4cf34d2c15"
EXPECTED_PLIST="d30e8029aacd1c80e093380a94fe52edb5d378eb90aeed9dc9e2ec6a03805e3e"
# Predecessor triplet (older helper/backend, same plist). Known only so an
# upgrade may snapshot and replace it. This package never reads
# /Users/Shared/MRA_HELPER_ROLLBACK_20261110T1650.
EXPECTED_OLD_HELPER="916b78cb6b95ca8a152f625d4f73c46f3142255fd85f6c12be6f19e3f62f5ac9"
EXPECTED_OLD_HELPER_2="197d1f334536d9719598db4ccff46cf4b79f04bf3b05629c077c6f1536252ebe"
EXPECTED_OLD_BACKEND_2="b03160fd14e0424a180c460f4fdd142767fdf8d26bdef0e7a1f1f7b01ad4d418"
EXPECTED_OLD_BACKEND_3="7105ddd2ce10f735d86747068c68749bce728f5a50502b6d093b2957a69dba25"
EXPECTED_OLD_BACKEND="f5bc28e04299f77b8d99e425772c89b2ca54dabd25df2218b491f0363ec32aeb"
EXPECTED_OLD_PLIST="d30e8029aacd1c80e093380a94fe52edb5d378eb90aeed9dc9e2ec6a03805e3e"
: "${ABSENT_TIMEOUT:=15}"
: "${READY_TIMEOUT:=15}"
ROLLBACK_ARMED=0
ROLLBACK_RUNNING=0
ROLLBACK_DONE=0
FAILURE_LOGGED=0
HAD_PREVIOUS_INSTALL=0
FAIL_LOG=""

QUARANTINE_LIB="$HERE/mra-quarantine.sh"
if [ ! -f "$QUARANTINE_LIB" ] && [ -f "$HERE/Candidate/mra-quarantine.sh" ]; then
  QUARANTINE_LIB="$HERE/Candidate/mra-quarantine.sh"
fi
# shellcheck source=mra-quarantine.sh
. "$QUARANTINE_LIB"

sha() { "$SHA_BIN" -a 256 "$1" | /usr/bin/awk '{print $1}'; }
service_print() { "$LAUNCHCTL_BIN" print "system/$LABEL" 2>&1; }
service_exists() { "$LAUNCHCTL_BIN" print "system/$LABEL" >/dev/null 2>&1; }
pid_of_service() { service_print | /usr/bin/awk '/^[[:space:]]*pid = /{print $3; exit}'; }
helper_process_pids() { "$PS_BIN" -axo pid=,command= | /usr/bin/awk -v p="$HELPER_DST" '$2 == p { print $1 }'; }
socket_has_listener() {
  [ -S "$SOCKET" ] || return 1
  "$LSOF_BIN" "$SOCKET" >/dev/null 2>&1
}

using_system_destinations() {
  case "$HELPER_DST$BACKEND_DST$PLIST_DST" in
    /Library/*) return 0 ;;
    *) return 1 ;;
  esac
}

die_preflight() {
  echo "INSTALL_ABORT: $*" >&2
  exit 1
}

# ---- minos / quarantine pre-checks (no system changes) ----
ver_max() {
  printf '%s\n' "$@" | "$SORT_BIN" -V | /usr/bin/tail -n 1
}

ver_ge() {
  [ "$(ver_max "$1" "$2")" = "$1" ]
}

minos_of() {
  local file=$1 value
  [ -f "$file" ] || die_preflight "minos target missing: $file"
  [ -x "$VTOOL_BIN" ] || die_preflight "vtool missing: $VTOOL_BIN"
  value=$("$VTOOL_BIN" -show-build "$file" 2>/dev/null | /usr/bin/awk '/minos/{print $2; exit}')
  [ -n "$value" ] || die_preflight "could not read minos from $file"
  printf '%s\n' "$value"
}

plist_minos_of() {
  local file=$1 value
  [ -f "$file" ] || die_preflight "Info.plist missing: $file"
  value=$("$PLUTIL_BIN" -extract LSMinimumSystemVersion raw -- "$file" 2>/dev/null || true)
  [ -n "$value" ] || die_preflight "LSMinimumSystemVersion missing in $file"
  printf '%s\n' "$value"
}

# Payload only: App bundle (covers Helper and backend inside it), plist, and
# this installer. Never recursively clear a source worktree root.
quarantine_payload_roots() {
  printf '%s\n' "$APP_DIR"
  [ -f "$PLIST_SRC" ] && printf '%s\n' "$PLIST_SRC"
  printf '%s\n' "$0"
  [ -f "$HERE/mra-quarantine.sh" ] && printf '%s\n' "$HERE/mra-quarantine.sh"
  [ -f "$HERE/uninstall-mra-device-control.sh" ] && printf '%s\n' "$HERE/uninstall-mra-device-control.sh"
  return 0
}

check_minos() {
  local app_minos helper_minos backend_minos plist_minos effective host_os
  app_minos=$(minos_of "$APP_BIN")
  helper_minos=$(minos_of "$HELPER_SRC")
  backend_minos=$(minos_of "$BACKEND_SRC")
  plist_minos=$(plist_minos_of "$APP_INFO")
  effective=$(ver_max "$app_minos" "$helper_minos" "$backend_minos")
  host_os=$("$SW_VERS_BIN" -productVersion)
  echo "MINOS_APP=$app_minos"
  echo "MINOS_HELPER=$helper_minos"
  echo "MINOS_BACKEND=$backend_minos"
  echo "MINOS_PLIST=$plist_minos"
  echo "MINOS_EFFECTIVE=$effective"
  echo "HOST_OS=$host_os"
  if [ "$plist_minos" != "$effective" ]; then
    echo "MINOS_MISMATCH"
    die_preflight "Info.plist LSMinimumSystemVersion ($plist_minos) must equal the highest bundled minos ($effective)"
  fi
  if ! ver_ge "$host_os" "$effective"; then
    echo "STOP_UNSUPPORTED_OS"
    die_preflight "host macOS $host_os is below required $effective"
  fi
  echo "MINOS_CONSISTENT=YES"
}

check_signatures() {
  "$CODESIGN_BIN" --verify --strict "$HELPER_SRC"
  "$CODESIGN_BIN" --verify --strict "$BACKEND_SRC"
  "$CODESIGN_BIN" --verify --strict --deep "$APP_DIR"
  "$PLUTIL_BIN" -lint "$PLIST_SRC"
  "$PLUTIL_BIN" -lint "$APP_INFO"
  echo "SIGNATURE_OK"
}

is_known_triplet() {
  local h=$1 b=$2 p=$3
  if [ "$h" = "$EXPECTED_HELPER" ] && [ "$b" = "$EXPECTED_BACKEND" ] && [ "$p" = "$EXPECTED_PLIST" ]; then
    return 0
  fi
  if [ "$h" = "$EXPECTED_OLD_HELPER" ] && [ "$b" = "$EXPECTED_OLD_BACKEND" ] && [ "$p" = "$EXPECTED_OLD_PLIST" ]; then
    return 0
  fi
  if [ "$h" = "$EXPECTED_OLD_HELPER_2" ] && [ "$b" = "$EXPECTED_OLD_BACKEND" ] && [ "$p" = "$EXPECTED_OLD_PLIST" ]; then
    return 0
  fi
  if [ "$h" = "$EXPECTED_HELPER" ] && [ "$b" = "$EXPECTED_OLD_BACKEND_2" ] && [ "$p" = "$EXPECTED_OLD_PLIST" ]; then
    return 0
  fi
  if [ "$h" = "$EXPECTED_HELPER" ] && [ "$b" = "$EXPECTED_OLD_BACKEND_3" ] && [ "$p" = "$EXPECTED_OLD_PLIST" ]; then
    return 0
  fi
  return 1
}

check_existing_install() {
  local present=0 h b p
  [ -e "$HELPER_DST" ] && present=1
  [ -e "$BACKEND_DST" ] && present=1
  [ -e "$PLIST_DST" ] && present=1
  if [ "$present" -eq 0 ]; then
    echo "EXISTING_INSTALL=NONE"
    HAD_PREVIOUS_INSTALL=0
    return 0
  fi
  if [ ! -f "$HELPER_DST" ] || [ ! -f "$BACKEND_DST" ] || [ ! -f "$PLIST_DST" ]; then
    echo "STOP_UNKNOWN_VERSION"
    die_preflight "incomplete installed set; refusing to overwrite"
  fi
  h=$(sha "$HELPER_DST")
  b=$(sha "$BACKEND_DST")
  p=$(sha "$PLIST_DST")
  echo "EXISTING_HELPER=$h"
  echo "EXISTING_BACKEND=$b"
  echo "EXISTING_PLIST=$p"
  if ! is_known_triplet "$h" "$b" "$p"; then
    echo "STOP_UNKNOWN_VERSION"
    die_preflight "installed hashes are not a known 0.2.2/predecessor triplet; refusing to overwrite"
  fi
  echo "EXISTING_INSTALL=KNOWN"
  HAD_PREVIOUS_INSTALL=1
}

check_quarantine() {
  local roots root p
  QUARANTINE_FOUND=0
  QUARANTINE_PATHS=""
  roots=$(quarantine_payload_roots)
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      echo "QUARANTINE_DETECTED=$p"
      QUARANTINE_FOUND=1
      if [ -n "$QUARANTINE_PATHS" ]; then
        QUARANTINE_PATHS="$QUARANTINE_PATHS
$p"
      else
        QUARANTINE_PATHS="$p"
      fi
    done < <(quarantine_scan "$root" || true)
  done <<< "$roots"
  if [ "$QUARANTINE_FOUND" -eq 0 ]; then
    echo "QUARANTINE_DETECTED=NONE"
    echo "QUARANTINE_CLEARED=NO"
    return 0
  fi
  echo "QUARANTINE_CLEARED=NO"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY_RUN_QUARANTINED=YES"
    echo "STOP_QUARANTINED_PACKAGE"
    die_preflight "quarantine present; dry-run reports only and does not clear xattrs"
  fi
  local answer=""
  if [ "${MRA_QUARANTINE_CONFIRM:-}" = "yes" ]; then
    answer="yes"
  elif [ ! -t 0 ]; then
    echo "STOP_QUARANTINED_PACKAGE"
    die_preflight "quarantine present and no TTY for confirmation; no system files were copied"
  else
    echo "检测到 com.apple.quarantine。哈希和签名校验已完成。"
    echo "是否只清除当前部署目录的 quarantine？不会修改 Gatekeeper、AMFI、spctl 或 SIP。"
    if ! read -r -p "输入 yes 继续，其他取消: " answer; then
      echo "STOP_QUARANTINED_PACKAGE"
      die_preflight "quarantine confirmation failed; no system files were copied"
    fi
  fi
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      echo "STOP_QUARANTINED_PACKAGE"
      die_preflight "quarantine not confirmed; no system files were copied"
      ;;
  esac
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    if ! quarantine_clear_scoped "$root"; then
      echo "QUARANTINE_CLEAR_FAILED"
      echo "STOP_QUARANTINED_PACKAGE"
      die_preflight "failed to clear quarantine on $root"
    fi
  done <<< "$roots"
  if [ -n "$(check_quarantine_remaining)" ]; then
    echo "QUARANTINE_CLEAR_FAILED"
    echo "STOP_QUARANTINED_PACKAGE"
    die_preflight "quarantine still present after scoped clear"
  fi
  echo "QUARANTINE_CLEARED=YES"
}

check_quarantine_remaining() {
  local roots root
  roots=$(quarantine_payload_roots)
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    quarantine_scan "$root"
  done <<< "$roots"
}

check_file() {
  local file=$1 expected=$2 label=$3
  [ -f "$file" ] || die_preflight "$label missing: $file"
  local actual; actual=$(sha "$file")
  echo "HASH $label $actual"
  [ "$actual" = "$expected" ] || die_preflight "$label hash mismatch (expected $expected)"
}

cleanup_stale_socket() {
  if [ -S "$SOCKET" ] && ! socket_has_listener; then
    echo "removing stale socket without listener: $SOCKET"
    "$RM_BIN" -f "$SOCKET"
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
  echo "DELETE_ABORTED_SERVICE_STILL_RUNNING"
  return 1
}

wait_socket_released() {
  local deadline=$((SECONDS + ABSENT_TIMEOUT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! socket_has_listener; then return 0; fi
    sleep 0.2
  done
  echo "DELETE_ABORTED_SOCKET_STILL_LISTENING"
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
  mkdir -p "$RECORD_DIR"
  FAIL_LOG="$RECORD_DIR/install-failure-$(date +%Y%m%dT%H%M%S).log"
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
    "$CODESIGN_BIN" -dvvv "$HELPER_DST" 2>&1 | grep -E 'Identifier|TeamIdentifier|CDHash' || true
    echo "--- socket ---"
    [ -S "$SOCKET" ] && echo "socket exists" || echo "socket missing"
  } >"$rec" 2>&1 || true
  echo "rollback evidence: $rec"
}

snapshot_existing_install() {
  if [ "$HAD_PREVIOUS_INSTALL" -ne 1 ]; then
    echo "SNAPSHOT=NONE"
    return 0
  fi
  mkdir -p "$PACKAGE_BACKUP"
  "$INSTALL_BIN" -m 0755 "$HELPER_DST" "$PACKAGE_BACKUP/com.mra.devicecontrol.helper"
  "$INSTALL_BIN" -m 0755 "$BACKEND_DST" "$PACKAGE_BACKUP/com.mra.direct_rid_dfu"
  "$INSTALL_BIN" -m 0644 "$PLIST_DST" "$PACKAGE_BACKUP/com.mra.devicecontrol.helper.plist"
  echo "SNAPSHOT=$PACKAGE_BACKUP"
}

payload_service_is_clean() {
  if service_exists; then
    echo "DELETE_ABORTED_SERVICE_STILL_RUNNING"
    return 1
  fi
  if [ -n "$(helper_process_pids || true)" ]; then
    echo "DELETE_ABORTED_PROCESS_STILL_RUNNING"
    return 1
  fi
  if socket_has_listener; then
    echo "DELETE_ABORTED_SOCKET_STILL_LISTENING"
    return 1
  fi
  return 0
}

safe_delete_expected_payload() {
  if ! payload_service_is_clean; then
    echo "NO_FILES_DELETED"
    return 1
  fi
  local p e
  for pair in "$HELPER_DST:$EXPECTED_HELPER" "$BACKEND_DST:$EXPECTED_BACKEND" "$PLIST_DST:$EXPECTED_PLIST"; do
    p="${pair%%:*}"
    e="${pair#*:}"
    if [ -f "$p" ] && [ "$(sha "$p")" = "$e" ]; then
      "$RM_BIN" -f "$p"
    elif [ -f "$p" ]; then
      echo "STOP_UNKNOWN_VERSION"
      echo "NO_FILES_DELETED"
      return 1
    fi
  done
  return 0
}

perform_rollback() {
  if [ "$ROLLBACK_RUNNING" -eq 1 ] || [ "$ROLLBACK_DONE" -eq 1 ]; then
    return 1
  fi
  ROLLBACK_RUNNING=1
  set +e
  echo "=== ROBUST ROLLBACK ==="
  local ok=1

  "$LAUNCHCTL_BIN" bootout "system/$LABEL" 2>/dev/null || true

  if ! wait_absent; then
    echo "ROLLBACK_FAILED: label still present or real process still alive" >&2
    echo "NO_FILES_DELETED"
    ok=0
  fi
  if [ "$ok" -eq 1 ] && ! wait_socket_released; then
    echo "ROLLBACK_FAILED: old socket still has a listener" >&2
    echo "NO_FILES_DELETED"
    ok=0
  fi
  if [ "$ok" -eq 1 ] && ! payload_service_is_clean; then
    echo "ROLLBACK_FAILED: service not fully stopped; refusing to copy or delete" >&2
    echo "NO_FILES_DELETED"
    ok=0
  fi
  [ "$ok" -eq 1 ] && cleanup_stale_socket

  if [ "$ok" -eq 1 ]; then
    if [ -f "$PACKAGE_BACKUP/com.mra.devicecontrol.helper" ] \
       && [ -f "$PACKAGE_BACKUP/com.mra.direct_rid_dfu" ] \
       && [ -f "$PACKAGE_BACKUP/com.mra.devicecontrol.helper.plist" ]; then
      "$INSTALL_BIN" -o root -g wheel -m 755 "$PACKAGE_BACKUP/com.mra.devicecontrol.helper" "$HELPER_DST" || ok=0
      "$INSTALL_BIN" -o root -g wheel -m 755 "$PACKAGE_BACKUP/com.mra.direct_rid_dfu" "$BACKEND_DST" || ok=0
      "$INSTALL_BIN" -o root -g wheel -m 644 "$PACKAGE_BACKUP/com.mra.devicecontrol.helper.plist" "$PLIST_DST" || ok=0
      if [ "$ok" -eq 1 ]; then
        if ! "$LAUNCHCTL_BIN" bootstrap system "$PLIST_DST"; then
          echo "ROLLBACK_FAILED: bootstrap of snapshotted plist failed" >&2
          ok=0
        elif ! wait_ready; then
          echo "ROLLBACK_FAILED: restored service not running with PID/socket" >&2
          ok=0
        fi
      fi
    else
      echo "ROLLBACK_FRESH_INSTALL: no package-local snapshot; deleting only this payload after stop"
      if ! safe_delete_expected_payload; then
        ok=0
      fi
    fi
  fi

  if [ "$ok" -eq 1 ]; then
    rollback_evidence SUCCESS
    echo "ROLLBACK_OK"
  else
    rollback_evidence FAILURE
    echo "ROLLBACK_FAILED" >&2
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

run_preflight() {
  echo "=== PREFLIGHT ==="
  echo "package_dir=$HERE"
  echo "app_dir=$APP_DIR"
  echo "record_dir=$RECORD_DIR"
  echo "BACKUP_DIR_DEPENDENCY=NO"
  [ -d "$APP_DIR" ] || die_preflight "App missing: $APP_DIR"
  [ -f "$APP_BIN" ] || die_preflight "App executable missing: $APP_BIN"
  [ -f "$APP_INFO" ] || die_preflight "Info.plist missing: $APP_INFO"
  echo "--- hash ---"
  check_file "$HELPER_SRC" "$EXPECTED_HELPER" candidate-helper
  check_file "$BACKEND_SRC" "$EXPECTED_BACKEND" candidate-backend
  check_file "$PLIST_SRC" "$EXPECTED_PLIST" candidate-plist
  echo "--- signature ---"
  check_signatures
  echo "--- minos ---"
  check_minos
  echo "--- existing install (read-only) ---"
  check_existing_install
  echo "--- quarantine ---"
  check_quarantine
  echo "preflight OK"
}

run_install() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "=== DRY RUN: no launchctl/system changes ==="
    echo "would snapshot existing known install into $PACKAGE_BACKUP (not 0.2.1 BACKUP_DIR)"
    echo "would arm EXIT/ERR rollback before bootout"
    echo "would bootout: $LABEL"
    echo "would wait absent/process exit/socket release ${ABSENT_TIMEOUT}s"
    echo "would install: $HELPER_DST"
    echo "would install: $BACKEND_DST"
    echo "would install: $PLIST_DST"
    echo "would verify installed hashes/codesign/plutil"
    echo "would bootstrap once and wait ${READY_TIMEOUT}s"
    echo "on failure: log to $RECORD_DIR, robust rollback from package-local snapshot or safe delete, no retry"
    echo "DRY_RUN_OK"
    exit 0
  fi

  if using_system_destinations; then
    [ "$(id -u)" -eq 0 ] || die_preflight "run as root: sudo $0"
  elif [ "${MRA_TEST_HARNESS:-0}" != "1" ]; then
    die_preflight "refusing to install to non-system destinations without MRA_TEST_HARNESS=1"
  fi

  ROLLBACK_ARMED=1
  trap on_err ERR
  trap on_exit EXIT

  mkdir -p "$RECORD_DIR"
  snapshot_existing_install
  service_print > "$RECORD_DIR/launchctl-preinstall-$(date +%Y%m%dT%H%M%S).txt" 2>&1 || true

  echo "=== BOOTOUT ==="
  "$LAUNCHCTL_BIN" bootout "system/$LABEL" 2>/dev/null || true
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
  if using_system_destinations; then
    "$INSTALL_BIN" -o root -g wheel -m 755 "$HELPER_SRC" "$HELPER_DST"
    "$INSTALL_BIN" -o root -g wheel -m 755 "$BACKEND_SRC" "$BACKEND_DST"
    "$INSTALL_BIN" -o root -g wheel -m 644 "$PLIST_SRC" "$PLIST_DST"
  else
    "$INSTALL_BIN" -m 755 "$HELPER_SRC" "$HELPER_DST"
    "$INSTALL_BIN" -m 755 "$BACKEND_SRC" "$BACKEND_DST"
    "$INSTALL_BIN" -m 644 "$PLIST_SRC" "$PLIST_DST"
  fi

  echo "=== VERIFY INSTALLED PATHS ==="
  check_file "$HELPER_DST" "$EXPECTED_HELPER" installed-helper
  check_file "$BACKEND_DST" "$EXPECTED_BACKEND" installed-backend
  check_file "$PLIST_DST" "$EXPECTED_PLIST" installed-plist
  "$CODESIGN_BIN" --verify --strict "$HELPER_DST"
  "$CODESIGN_BIN" --verify --strict "$BACKEND_DST"
  "$PLUTIL_BIN" -lint "$PLIST_DST"
  echo "installed files verified"

  echo "=== BOOTSTRAP (ONCE) ==="
  if ! "$LAUNCHCTL_BIN" bootstrap system "$PLIST_DST"; then
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
  "$CODESIGN_BIN" -dvvv "$HELPER_DST" 2>&1 | grep -E 'CDHash=' | head -1 || true
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
    "$CODESIGN_BIN" -dvvv "$HELPER_DST" 2>&1 | grep -E 'Identifier|TeamIdentifier|CDHash' || true
  } > "$RECORD"
  echo "record: $RECORD"
  ROLLBACK_ARMED=0
  echo "INSTALL_OK"
}

if [ "${MRA_SOURCE_ONLY:-0}" != "1" ]; then
  run_preflight
  run_install
fi
