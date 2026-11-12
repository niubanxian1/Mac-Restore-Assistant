#!/bin/bash
# Official 0.2.2 acceptance harness for T11 / T13.
# Isolated scratch destinations only. Never sudo. Never the production socket.
# Refuses to run if any dest is under /Library or the real /var/run.
set -euo pipefail

usage() {
  echo "usage: $0 <case> [evidence-file]" >&2
  echo "cases: red-quarantine red-uninstall red-rollback" >&2
  echo "       green-quarantine green-quarantine-dry-run" >&2
  echo "       green-uninstall-service green-uninstall-process green-uninstall-socket" >&2
  echo "       green-install-t1205z-dry-run green-uninstall-t1205z-dry-run" >&2
  echo "       green-install-t1306z-dry-run green-uninstall-t1306z-dry-run" >&2
  echo "       green-install-no-vtool-dry-run" >&2
  echo "       green-quarantine-stage-fallback" >&2
  echo "       green-missing-destination-directories" >&2
  echo "       green-uninstall-stale-socket" >&2
  exit 2
}

CASE="${1:-}"
[ -n "$CASE" ] || usage

: "${WT_ROOT:=}"
: "${FIXTURES_ROOT:=}"
: "${SEALED_ROOT:=/Users/Shared/MRA_DEVICE_CONTROL_RELEASE_0.2.2_20261110T1145Z}"
: "${LEGACY_T1205_ROOT:=/Users/Shared/MRA_DEVICE_CONTROL_RELEASE_0.2.2_20261110T1145Z}"
: "${LEGACY_T1306_ROOT:=/Users/Shared/MRA_DEVICE_CONTROL_RELEASE_0.2.2_20261110T1306Z}"
: "${EVIDENCE_DIR:=}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$FIXTURES_ROOT" ]; then
  if [ -d "$SCRIPT_DIR/../Fixtures" ]; then
    FIXTURES_ROOT="$(cd "$SCRIPT_DIR/../Fixtures" && pwd)"
  elif [ -d "$SCRIPT_DIR/../Fixtures" ]; then
    FIXTURES_ROOT="$(cd "$SCRIPT_DIR/../Fixtures" && pwd)"
  fi
fi
if [ -z "$WT_ROOT" ]; then
  if [ -f "$SCRIPT_DIR/../../../install-mra-device-control.sh" ]; then
    WT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  fi
fi
[ -n "$WT_ROOT" ] || { echo "HARNESS_FAIL: WT_ROOT is not set and could not be inferred" >&2; exit 2; }
[ -n "$FIXTURES_ROOT" ] || { echo "HARNESS_FAIL: FIXTURES_ROOT is not set" >&2; exit 2; }

INSTALLER="$WT_ROOT/install-mra-device-control.sh"
UNINSTALL="$WT_ROOT/uninstall-mra-device-control.sh"
QUARANTINE_LIB="$WT_ROOT/mra-quarantine.sh"
PRE_MINOS="$WT_ROOT/install-mra-device-control.pre-minos-quarantine.sh"
STUBS="$FIXTURES_ROOT/stubs"
UNSAFE_UNINSTALL="$FIXTURES_ROOT/scripts/unsafe-uninstall.sh"
UNSAFE_ROLLBACK="$FIXTURES_ROOT/scripts/unsafe-rollback.sh"
SEALED_APP="$SEALED_ROOT/MRA Device Control Prototype.app"
SEALED_PLIST="$SEALED_ROOT/com.mra.devicecontrol.helper.plist"
CANDIDATE_APP="$WT_ROOT/Candidate/MRA Device Control Prototype.app"
CANDIDATE_PLIST="$WT_ROOT/Candidate/com.mra.devicecontrol.helper.plist"

[ -f "$INSTALLER" ] || { echo "HARNESS_FAIL: installer missing: $INSTALLER" >&2; exit 2; }
[ -f "$UNINSTALL" ] || { echo "HARNESS_FAIL: uninstall missing: $UNINSTALL" >&2; exit 2; }
[ -x "$STUBS/launchctl" ] || { echo "HARNESS_FAIL: stubs missing under $STUBS" >&2; exit 2; }

WORKDIR=$(mktemp -d /tmp/mra022-accept-XXXXXX)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

OUT="${2:-}"
if [ -z "$OUT" ]; then
  OUT="$WORKDIR/out.txt"
fi
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
CMD_LOG="$WORKDIR/cmd.log"
: > "$CMD_LOG"

emit() { echo "$@" | /usr/bin/tee -a "$OUT"; }
fail() { emit "HARNESS_FAIL: $*"; emit "CASE_RESULT=FAIL"; exit 1; }

run_logged() {
  set +e
  "$@" > "$CMD_LOG" 2>&1
  local rc=$?
  /usr/bin/tee -a "$OUT" < "$CMD_LOG"
  return "$rc"
}

emit "CASE=$CASE"
emit "WHEN=$(date '+%F %T %z')"
emit "WORKDIR=$WORKDIR"
emit "WT_ROOT=$WT_ROOT"
emit "FIXTURES_ROOT=$FIXTURES_ROOT"
emit "SEALED_ROOT=$SEALED_ROOT"
sha_of() { /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'; }

is_forbidden_dest() {
  local p="$1"
  case "$p" in
    /Library/*|/var/run/*)
      return 0
      ;;
  esac
  return 1
}

assert_scratch_dest() {
  local p="$1"
  [ -n "$p" ] || fail "empty dest"
  if is_forbidden_dest "$p"; then
    fail "refusing system dest: $p"
  fi
  case "$p" in
    /tmp/*|"$WORKDIR"/*)
      ;;
    *)
      fail "refusing non-scratch dest: $p"
      ;;
  esac
}

OWNER_HELPER="/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
OWNER_HELPER_PRESENT=0
OWNER_HELPER_HASH=""
if [ -f "$OWNER_HELPER" ]; then
  OWNER_HELPER_PRESENT=1
  OWNER_HELPER_HASH=$(sha_of "$OWNER_HELPER")
fi
emit "OWNER_HELPER_PRESENT=$OWNER_HELPER_PRESENT"

assert_owner_untouched() {
  if [ "$OWNER_HELPER_PRESENT" -eq 1 ]; then
    [ -f "$OWNER_HELPER" ] || fail "Owner Helper file disappeared during $CASE"
    [ "$(sha_of "$OWNER_HELPER")" = "$OWNER_HELPER_HASH" ] || fail "Owner Helper hash changed during $CASE"
  fi
}

export_common() {
  local root=$1 record=$2
  export HELPER_DST="$root/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
  export BACKEND_DST="$root/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
  export PLIST_DST="$root/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"
  export SOCKET="$root/var/run/com.mra.devicecontrol.helper.sock"
  export RECORD_DIR="$record"
  export CODESIGN_BIN="$STUBS/codesign"
  export LAUNCHCTL_BIN="$STUBS/launchctl"
  export PS_BIN="$STUBS/ps"
  export LSOF_BIN="$STUBS/lsof"
  export RM_BIN="$STUBS/rm"
  export RM_LOG="$record/rm.log"
  export MRA_TEST_HARNESS=1
  export ABSENT_TIMEOUT=1
  export MRA_WAIT_ATTEMPTS=3
  mkdir -p "$record" "$(dirname "$HELPER_DST")" "$(dirname "$BACKEND_DST")" "$(dirname "$PLIST_DST")" "$(dirname "$SOCKET")"
  : > "$RM_LOG"
  assert_scratch_dest "$HELPER_DST"
  assert_scratch_dest "$BACKEND_DST"
  assert_scratch_dest "$PLIST_DST"
  assert_scratch_dest "$SOCKET"
}

setup_official_pkg() {
  local dest=$1
  mkdir -p "$dest"
  [ -d "$SEALED_APP" ] || fail "sealed app missing (read-only source): $SEALED_APP"
  [ -f "$SEALED_PLIST" ] || fail "sealed plist missing: $SEALED_PLIST"
  /usr/bin/ditto "$SEALED_APP" "$dest/MRA Device Control Prototype.app"
  /bin/cp "$SEALED_PLIST" "$dest/com.mra.devicecontrol.helper.plist"
  /bin/cp "$QUARANTINE_LIB" "$dest/mra-quarantine.sh"
  /bin/cp "$UNINSTALL" "$dest/uninstall-mra-device-control.sh"
  /bin/cp "$INSTALLER" "$dest/install-mra-device-control.sh"
  chmod 755 "$dest/mra-quarantine.sh" "$dest/uninstall-mra-device-control.sh" "$dest/install-mra-device-control.sh"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-accept;unconfirmed" "$dest/MRA Device Control Prototype.app" || true
  /usr/bin/xattr -wr com.apple.quarantine "mra-022-accept;unconfirmed" "$dest/MRA Device Control Prototype.app"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-accept;unconfirmed" "$dest/MRA Device Control Prototype.app/Contents/Resources/mra-helper"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-accept;unconfirmed" "$dest/MRA Device Control Prototype.app/Contents/Resources/direct_rid_dfu"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-accept;unconfirmed" "$dest/com.mra.devicecontrol.helper.plist"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-accept;unconfirmed" "$dest/install-mra-device-control.sh"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-accept;unconfirmed" "$dest/mra-quarantine.sh"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-accept;unconfirmed" "$dest/uninstall-mra-device-control.sh"
}

setup_clean_pkg() {
  local dest=$1
  mkdir -p "$dest"
  [ -d "$SEALED_APP" ] || fail "sealed app missing (read-only source): $SEALED_APP"
  [ -f "$SEALED_PLIST" ] || fail "sealed plist missing: $SEALED_PLIST"
  /usr/bin/ditto "$SEALED_APP" "$dest/MRA Device Control Prototype.app"
  /bin/cp "$SEALED_PLIST" "$dest/com.mra.devicecontrol.helper.plist"
  /bin/cp "$QUARANTINE_LIB" "$dest/mra-quarantine.sh"
  /bin/cp "$UNINSTALL" "$dest/uninstall-mra-device-control.sh"
  /bin/cp "$INSTALLER" "$dest/install-mra-device-control.sh"
  chmod 755 "$dest/mra-quarantine.sh" "$dest/uninstall-mra-device-control.sh" "$dest/install-mra-device-control.sh"
}

payload_still_quarantined() {
  local dest=$1
  /usr/bin/xattr -p com.apple.quarantine "$dest/com.mra.devicecontrol.helper.plist" >/dev/null \
    && /usr/bin/xattr -p com.apple.quarantine "$dest/MRA Device Control Prototype.app/Contents/Resources/mra-helper" >/dev/null
}

copy_official_dests() {
  local root=$1
  mkdir -p "$root/Library/PrivilegedHelperTools" "$root/Library/LaunchDaemons" "$root/var/run"
  /bin/cp "$SEALED_APP/Contents/Resources/mra-helper" "$root/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
  /bin/cp "$SEALED_APP/Contents/Resources/direct_rid_dfu" "$root/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
  /bin/cp "$SEALED_PLIST" "$root/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"
}

copy_legacy_triplet() {
  local root=$1 legacy_root=$2
  local app="$legacy_root/MRA Device Control Prototype.app"
  [ -f "$app/Contents/Resources/mra-helper" ] || fail "legacy helper missing: $app"
  [ -f "$app/Contents/Resources/direct_rid_dfu" ] || fail "legacy backend missing: $app"
  [ -f "$legacy_root/com.mra.devicecontrol.helper.plist" ] || fail "legacy plist missing: $legacy_root"
  mkdir -p "$root/Library/PrivilegedHelperTools" "$root/Library/LaunchDaemons" "$root/var/run"
  /bin/cp "$app/Contents/Resources/mra-helper" "$root/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
  /bin/cp "$app/Contents/Resources/direct_rid_dfu" "$root/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
  /bin/cp "$legacy_root/com.mra.devicecontrol.helper.plist" "$root/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"
}

make_unix_socket() {
  local path=$1
  mkdir -p "$(dirname "$path")"
  /usr/bin/python3 -c "import socket,os; p='$path'; os.path.exists(p) and os.remove(p); s=socket.socket(socket.AF_UNIX); s.bind(p)"
}

# ---------- RED: pre-minos installer has no unconfirmed quarantine abort ----------
red_quarantine() {
  local pkg="$WORKDIR/red-q-pkg" fake="$WORKDIR/red-q-fake" rec="$WORKDIR/red-q-rec"
  mkdir -p "$pkg" "$fake/Library/PrivilegedHelperTools" "$fake/Library/LaunchDaemons" "$fake/var/run" "$fake/outside" "$rec"
  if [ -d "$CANDIDATE_APP" ]; then
    /usr/bin/ditto "$CANDIDATE_APP" "$pkg/MRA Device Control Prototype.app"
    /bin/cp "$CANDIDATE_PLIST" "$pkg/com.mra.devicecontrol.helper.plist"
  else
    setup_official_pkg "$pkg"
  fi
  /usr/bin/xattr -wr com.apple.quarantine "mra-022-accept-red;unconfirmed" "$pkg/MRA Device Control Prototype.app"
  printf 'CANARY_HELPER\n' > "$fake/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
  printf 'CANARY_BACKEND\n' > "$fake/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
  printf 'CANARY_PLIST\n' > "$fake/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"
  printf 'KEEP_OUTSIDE\n' > "$fake/outside/keep.txt"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-outside;must-remain" "$fake/outside/keep.txt"
  export_common "$fake" "$rec"
  local patched="$pkg/install-old.sh"
  [ -f "$PRE_MINOS" ] || fail "pre-minos installer missing: $PRE_MINOS"
  /bin/cp "$PRE_MINOS" "$patched"
  chmod 755 "$patched"
  /usr/bin/sed -i.bak \
    -e "s|/Library/PrivilegedHelperTools|$fake/Library/PrivilegedHelperTools|g" \
    -e "s|/Library/LaunchDaemons|$fake/Library/LaunchDaemons|g" \
    -e "s|/var/run/com.mra.devicecontrol.helper.sock|$SOCKET|g" \
    -e "s|/Users/Shared/MRA_HELPER_ROLLBACK_20261110T1650|$rec/fake-backup|g" \
    -e "s|/usr/bin/codesign|$STUBS/codesign|g" \
    "$patched"
  if grep -E 'HELPER_DST="/Library/|BACKEND_DST="/Library/|PLIST_DST="/Library/|SOCKET="/var/run/' "$patched"; then
    fail "patched pre-minos installer still contains real system destinations"
  fi
  mkdir -p "$rec/fake-backup"
  local before_h; before_h=$(sha_of "$fake/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper")
  set +e
  run_logged /bin/bash "$patched" --dry-run < /dev/null
  local rc=$?
  set -e
  emit "RED_QUARANTINE_RC=$rc"
  if grep -q 'STOP_QUARANTINED_PACKAGE' "$CMD_LOG"; then
    fail "UNEXPECTED: pre-minos installer already aborted on quarantine"
  fi
  [ "$(sha_of "$fake/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper")" = "$before_h" ] \
    || fail "RED old installer mutated fake-system helper"
  grep -q CANARY_HELPER "$fake/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper" \
    || fail "canary helper mutated"
  grep -q KEEP_OUTSIDE "$fake/outside/keep.txt" || fail "outside keep.txt mutated"
  emit "RED_QUARANTINE=YES"
  emit "CASE_RESULT=PASS"
}

# ---------- GREEN: current installer aborts unconfirmed / dry-run quarantine ----------
green_quarantine() {
  local dry="${1:-0}"
  local pkg="$WORKDIR/green-q-pkg" fake="$WORKDIR/green-q-fake" rec="$WORKDIR/green-q-rec"
  setup_official_pkg "$pkg"
  mkdir -p "$fake/Library/PrivilegedHelperTools" "$fake/Library/LaunchDaemons" "$fake/var/run" "$fake/outside"
  printf 'KEEP_OUTSIDE\n' > "$fake/outside/keep.txt"
  printf 'CANARY_SIDE\n' > "$fake/Library/PrivilegedHelperTools/canary-side.txt"
  /usr/bin/xattr -w com.apple.quarantine "mra-022-outside;must-remain" "$fake/outside/keep.txt"
  export_common "$fake" "$rec"
  unset MRA_QUARANTINE_CONFIRM || true
  local keep_before side_before
  keep_before=$(sha_of "$fake/outside/keep.txt")
  side_before=$(sha_of "$fake/Library/PrivilegedHelperTools/canary-side.txt")
  set +e
  if [ "$dry" -eq 1 ]; then
    run_logged /bin/bash "$pkg/install-mra-device-control.sh" --dry-run < /dev/null
  else
    run_logged /bin/bash "$pkg/install-mra-device-control.sh" < /dev/null
  fi
  local rc=$?
  set -e
  emit "GREEN_QUARANTINE_RC=$rc"
  grep -q 'STOP_QUARANTINED_PACKAGE' "$CMD_LOG" || fail "installer did not emit STOP_QUARANTINED_PACKAGE"
  [ "$rc" -ne 0 ] || fail "installer exited 0 under unconfirmed quarantine"
  if grep -q 'INSTALL_OK' "$CMD_LOG"; then
    fail "installer claimed INSTALL_OK"
  fi
  [ ! -e "$HELPER_DST" ] || fail "helper was copied to fake-system"
  [ ! -e "$BACKEND_DST" ] || fail "backend was copied to fake-system"
  [ ! -e "$PLIST_DST" ] || fail "plist was copied to fake-system"
  payload_still_quarantined "$pkg" || fail "unconfirmed run cleared package quarantine"
  [ "$(sha_of "$fake/outside/keep.txt")" = "$keep_before" ] || fail "outside keep.txt changed"
  [ "$(sha_of "$fake/Library/PrivilegedHelperTools/canary-side.txt")" = "$side_before" ] || fail "side canary changed"
  /usr/bin/xattr -p com.apple.quarantine "$fake/outside/keep.txt" >/dev/null || fail "outside xattr cleared"
  if [ -s "$RM_LOG" ] && /usr/bin/grep -v '^$' "$RM_LOG" | /usr/bin/grep -q .; then
    fail "RM_LOG not empty: $(cat "$RM_LOG")"
  fi
  emit "GREEN_QUARANTINE=YES"
  emit "CASE_RESULT=PASS"
}

# ---------- RED: unsafe uninstall / rollback deletes while "service" may be live ----------
red_delete() {
  local kind=$1
  local script
  if [ "$kind" = "uninstall" ]; then
    script="$UNSAFE_UNINSTALL"
  else
    script="$UNSAFE_ROLLBACK"
  fi
  [ -x "$script" ] || fail "unsafe script missing: $script"
  local fake="$WORKDIR/red-del-fake" rec="$WORKDIR/red-del-rec"
  mkdir -p "$fake/Library/PrivilegedHelperTools" "$fake/Library/LaunchDaemons" "$fake/var/run"
  printf 'CANARY_HELPER\n' > "$fake/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
  printf 'CANARY_BACKEND\n' > "$fake/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
  printf 'CANARY_PLIST\n' > "$fake/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"
  export_common "$fake" "$rec"
  export LAUNCHCTL_MODE=present
  export PS_MODE=running
  set +e
  run_logged /bin/bash "$script"
  local rc=$?
  set -e
  emit "RED_${kind}_RC=$rc"
  if [ -f "$HELPER_DST" ] && [ -f "$BACKEND_DST" ] && [ -f "$PLIST_DST" ]; then
    fail "unsafe $kind left files in place (not a RED baseline)"
  fi
  emit "RED_${kind}=YES"
  emit "CASE_RESULT=PASS"
}

# ---------- GREEN: current uninstall refuses to delete while service/process/socket live ----------
green_uninstall() {
  local mode=$1
  local fake="$WORKDIR/green-u-fake" rec="$WORKDIR/green-u-rec"
  copy_official_dests "$fake"
  export_common "$fake" "$rec"
  unset LAUNCHCTL_MODE PS_MODE LSOF_MODE || true
  case "$mode" in
    service)
      export LAUNCHCTL_MODE=present
      export PS_MODE=
      export LSOF_MODE=
      ;;
    process)
      export LAUNCHCTL_MODE=absent
      export PS_MODE=running
      export LSOF_MODE=
      ;;
    socket)
      export LAUNCHCTL_MODE=absent
      export PS_MODE=
      export LSOF_MODE=listening
      make_unix_socket "$SOCKET"
      ;;
    *) fail "unknown uninstall mode $mode" ;;
  esac
  local h_before b_before p_before
  h_before=$(sha_of "$HELPER_DST")
  b_before=$(sha_of "$BACKEND_DST")
  p_before=$(sha_of "$PLIST_DST")
  set +e
  run_logged /bin/bash "$UNINSTALL"
  local rc=$?
  set -e
  emit "GREEN_UNINSTALL_${mode}_RC=$rc"
  grep -q 'NO_FILES_DELETED' "$CMD_LOG" || fail "missing NO_FILES_DELETED"
  case "$mode" in
    service) grep -q 'DELETE_ABORTED_SERVICE_STILL_RUNNING' "$CMD_LOG" || fail "missing DELETE_ABORTED_SERVICE_STILL_RUNNING" ;;
    process) grep -q 'DELETE_ABORTED_PROCESS_STILL_RUNNING' "$CMD_LOG" || fail "missing DELETE_ABORTED_PROCESS_STILL_RUNNING" ;;
    socket) grep -q 'DELETE_ABORTED_SOCKET_STILL_LISTENING' "$CMD_LOG" || fail "missing DELETE_ABORTED_SOCKET_STILL_LISTENING" ;;
  esac
  [ -f "$HELPER_DST" ] && [ -f "$BACKEND_DST" ] && [ -f "$PLIST_DST" ] || fail "GREEN uninstall deleted fake-system files"
  [ "$(sha_of "$HELPER_DST")" = "$h_before" ] || fail "helper hash changed during aborted uninstall"
  [ "$(sha_of "$BACKEND_DST")" = "$b_before" ] || fail "backend hash changed during aborted uninstall"
  [ "$(sha_of "$PLIST_DST")" = "$p_before" ] || fail "plist hash changed during aborted uninstall"
  if /usr/bin/grep -q '^RM ' "$RM_LOG" 2>/dev/null; then
    fail "RM_LOG recorded deletes: $(cat "$RM_LOG")"
  fi
  [ "$rc" -ne 0 ] || fail "GREEN uninstall exited 0 while $mode still live"
  emit "GREEN_UNINSTALL_${mode}=YES"
  emit "CASE_RESULT=PASS"
}

green_install_legacy_dry_run() {
  local legacy_root=$1 label=$2
  local pkg="$WORKDIR/${label}-install-pkg" fake="$WORKDIR/${label}-install-fake" rec="$WORKDIR/${label}-install-rec"
  setup_clean_pkg "$pkg"
  copy_legacy_triplet "$fake" "$legacy_root"
  export_common "$fake" "$rec"
  set +e
  run_logged /bin/bash "$pkg/install-mra-device-control.sh" --dry-run < /dev/null
  local rc=$?
  set -e
  emit "${label}_INSTALL_DRYRUN_RC=$rc"
  [ "$rc" -eq 0 ] || fail "${label} installer rejected a real known legacy triplet"
  grep -q 'EXISTING_INSTALL=KNOWN' "$CMD_LOG" || fail "${label} installer did not classify legacy install as known"
  grep -q 'DRY_RUN_OK' "$CMD_LOG" || fail "${label} installer did not complete dry-run"
  ! grep -q 'STOP_UNKNOWN_VERSION' "$CMD_LOG" || fail "${label} installer still reports STOP_UNKNOWN_VERSION"
  emit "${label}_INSTALL_OFFLINE=YES"
  emit "CASE_RESULT=PASS"
}

green_uninstall_legacy_dry_run() {
  local legacy_root=$1 label=$2
  local fake="$WORKDIR/${label}-uninstall-fake" rec="$WORKDIR/${label}-uninstall-rec"
  copy_legacy_triplet "$fake" "$legacy_root"
  export_common "$fake" "$rec"
  set +e
  run_logged /bin/bash "$UNINSTALL" --dry-run < /dev/null
  local rc=$?
  set -e
  emit "${label}_UNINSTALL_DRYRUN_RC=$rc"
  [ "$rc" -eq 0 ] || fail "${label} uninstaller rejected a real known legacy triplet"
  grep -q 'DRY_RUN_OK' "$CMD_LOG" || fail "${label} uninstaller did not complete dry-run"
  ! grep -q 'STOP_UNKNOWN_VERSION' "$CMD_LOG" || fail "${label} uninstaller still reports STOP_UNKNOWN_VERSION"
  emit "${label}_UNINSTALL_OFFLINE=YES"
  emit "CASE_RESULT=PASS"
}

green_uninstall_stale_socket() {
  local fake="$WORKDIR/green-u-stale-fake" rec="$WORKDIR/green-u-stale-rec"
  copy_official_dests "$fake"
  export_common "$fake" "$rec"
  export LAUNCHCTL_MODE=absent PS_MODE= LSOF_MODE=
  make_unix_socket "$SOCKET"
  set +e
  run_logged /bin/bash "$UNINSTALL" < /dev/null
  local rc=$?
  set -e
  emit "GREEN_UNINSTALL_stale_RC=$rc"
  [ "$rc" -eq 0 ] || fail "stale-socket uninstall failed"
  grep -q 'STALE_SOCKET_REMOVED' "$CMD_LOG" || fail "stale socket removal was not reported"
  grep -q 'UNINSTALL_OK' "$CMD_LOG" || fail "uninstall did not report success"
  if [ -e "$SOCKET" ]; then
    emit "REMAINS_SOCKET=$SOCKET"
    fail "uninstall left a stale socket behind"
  fi
  [ ! -e "$HELPER_DST" ] || fail "helper remains after uninstall"
  [ ! -e "$BACKEND_DST" ] || fail "backend remains after uninstall"
  [ ! -e "$PLIST_DST" ] || fail "plist remains after uninstall"
  emit "GREEN_UNINSTALL_stale=YES"
  emit "CASE_RESULT=PASS"
}

green_install_no_vtool_dry_run() {
  local pkg="$WORKDIR/no-vtool-pkg" fake="$WORKDIR/no-vtool-fake" rec="$WORKDIR/no-vtool-rec"
  setup_clean_pkg "$pkg"
  mkdir -p "$fake"
  export_common "$fake" "$rec"
  export VTOOL_BIN=/usr/bin/false
  set +e
  run_logged /bin/bash "$pkg/install-mra-device-control.sh" --dry-run < /dev/null
  local rc=$?
  set -e
  emit "NO_VTOOL_RC=$rc"
  [ "$rc" -eq 0 ] || fail "installer requires vtool for its minos preflight"
  grep -q 'MINOS_CONSISTENT=YES' "$CMD_LOG" || fail "minos fallback did not prove consistency"
  grep -q 'DRY_RUN_OK' "$CMD_LOG" || fail "no-vtool dry-run did not complete"
  emit "NO_VTOOL_DRYRUN=YES"
  emit "CASE_RESULT=PASS"
}

green_quarantine_stage_fallback() {
  local pkg="$WORKDIR/readonly-q-pkg" rec="$WORKDIR/readonly-q-rec"
  setup_official_pkg "$pkg"
  mkdir -p "$rec"
  local before
  before=$(sha_of "$pkg/MRA Device Control Prototype.app/Contents/Resources/mra-helper")
  set +e
  (
    export HELPER_DST="$WORKDIR/readonly-q-fake/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
    export BACKEND_DST="$WORKDIR/readonly-q-fake/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
    export PLIST_DST="$WORKDIR/readonly-q-fake/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"
    export SOCKET="$WORKDIR/readonly-q-fake/var/run/com.mra.devicecontrol.helper.sock"
    export RECORD_DIR="$rec"
    export MRA_APP_DIR="$pkg/MRA Device Control Prototype.app"
    export MRA_SOURCE_ONLY=1
    export MRA_QUARANTINE_CONFIRM=yes
    export XATTR_BIN="$STUBS/xattr-protected"
    export XATTR_PROTECTED_PREFIX="$pkg/MRA Device Control Prototype.app"
    source "$pkg/install-mra-device-control.sh"
    check_quarantine
    echo "STAGED_HELPER_SRC=$HELPER_SRC"
    echo "STAGED_BACKEND_SRC=$BACKEND_SRC"
    echo "STAGED_PLIST_SRC=$PLIST_SRC"
    case "$HELPER_SRC:$BACKEND_SRC:$PLIST_SRC" in
      "$pkg/MRA Device Control Prototype.app"*) echo "SOURCE_STILL_USED=YES"; exit 1 ;;
    esac
    [ -f "$HELPER_SRC" ] && [ -f "$BACKEND_SRC" ] && [ -f "$PLIST_SRC" ] || exit 1
  ) > "$CMD_LOG" 2>&1
  local rc=$?
  set -e
  /usr/bin/tee -a "$OUT" < "$CMD_LOG"
  emit "READONLY_QUARANTINE_RC=$rc"
  [ "$rc" -eq 0 ] || fail "read-only quarantined app was not handled with staged payload"
  grep -q 'QUARANTINE_STAGED_PAYLOAD=YES' "$CMD_LOG" || fail "payload was not staged"
  grep -q 'QUARANTINE_CLEARED=YES' "$CMD_LOG" || fail "staged payload quarantine was not cleared"
  grep -q 'STAGED_PAYLOAD_VERIFIED=YES' "$CMD_LOG" || fail "staged payload verification was not reported"
  ! grep -q 'failed to clear quarantine on' "$CMD_LOG" || fail "installer tried to change the read-only source app"
  payload_still_quarantined "$pkg" || fail "source app quarantine changed"
  [ "$(sha_of "$pkg/MRA Device Control Prototype.app/Contents/Resources/mra-helper")" = "$before" ] \
    || fail "source app helper bytes changed"
  emit "SOURCE_APP_UNCHANGED=YES"
  emit "CASE_RESULT=PASS"
}

green_missing_destination_directories() {
  local pkg="$WORKDIR/missing-dirs-pkg" fake="$WORKDIR/missing-dirs-fake" rec="$WORKDIR/missing-dirs-rec"
  setup_clean_pkg "$pkg"
  mkdir -p "$rec"
  set +e
  (
    export HELPER_DST="$fake/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"
    export BACKEND_DST="$fake/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
    export PLIST_DST="$fake/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"
    export SOCKET="$fake/var/run/com.mra.devicecontrol.helper.sock"
    export RECORD_DIR="$rec"
    export MRA_APP_DIR="$pkg/MRA Device Control Prototype.app"
    export MRA_SOURCE_ONLY=1
    export MRA_TEST_HARNESS=1
    source "$pkg/install-mra-device-control.sh"
    prepare_destination_directories
    [ -d "$(dirname "$HELPER_DST")" ] || exit 1
    [ -d "$(dirname "$BACKEND_DST")" ] || exit 1
    [ -d "$(dirname "$PLIST_DST")" ] || exit 1
    echo "HELPER_PARENT=$(dirname "$HELPER_DST")"
    echo "PLIST_PARENT=$(dirname "$PLIST_DST")"
  ) > "$CMD_LOG" 2>&1
  local rc=$?
  set -e
  /usr/bin/tee -a "$OUT" < "$CMD_LOG"
  emit "MISSING_DEST_DIRS_RC=$rc"
  [ "$rc" -eq 0 ] || fail "installer did not create missing destination directories"
  [ -d "$fake/Library/PrivilegedHelperTools" ] || fail "PrivilegedHelperTools parent missing"
  [ -d "$fake/Library/LaunchDaemons" ] || fail "LaunchDaemons parent missing"
  emit "DESTINATION_DIRECTORIES_READY=YES"
  emit "CASE_RESULT=PASS"
}

case "$CASE" in
  red-quarantine) red_quarantine ;;
  red-uninstall) red_delete uninstall ;;
  red-rollback) red_delete rollback ;;
  green-quarantine) green_quarantine 0 ;;
  green-quarantine-dry-run) green_quarantine 1 ;;
  green-uninstall-service) green_uninstall service ;;
  green-uninstall-process) green_uninstall process ;;
  green-uninstall-socket) green_uninstall socket ;;
  green-install-t1205z-dry-run) green_install_legacy_dry_run "$LEGACY_T1205_ROOT" t1205z ;;
  green-uninstall-t1205z-dry-run) green_uninstall_legacy_dry_run "$LEGACY_T1205_ROOT" t1205z ;;
  green-install-t1306z-dry-run) green_install_legacy_dry_run "$LEGACY_T1306_ROOT" t1306z ;;
  green-uninstall-t1306z-dry-run) green_uninstall_legacy_dry_run "$LEGACY_T1306_ROOT" t1306z ;;
  green-install-no-vtool-dry-run) green_install_no_vtool_dry_run ;;
  green-quarantine-stage-fallback) green_quarantine_stage_fallback ;;
  green-missing-destination-directories) green_missing_destination_directories ;;
  green-uninstall-stale-socket) green_uninstall_stale_socket ;;
  *) usage ;;
esac

assert_owner_untouched
emit "OWNER_HELPER_UNCHANGED=YES"
exit 0
