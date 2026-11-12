#!/bin/bash
# Uninstall com.mra.devicecontrol.helper only when installed hashes match this
# 0.2.2 package. Does not touch com.macrestore.assistant.privileged, does not
# change Gatekeeper/AMFI/spctl/SIP, and does not issue DFU/Reboot commands.
# Do not run a live uninstall on the development machine: hashes currently
# match the frozen 0.2.1 Helper already installed there.
set -euo pipefail

LABEL="com.mra.devicecontrol.helper"
: "${HELPER_DST:=/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper}"
: "${BACKEND_DST:=/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu}"
: "${PLIST_DST:=/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist}"
: "${SOCKET:=/var/run/com.mra.devicecontrol.helper.sock}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${RECORD_DIR:=$HERE/install-record}"

EXPECTED_HELPER="c81917fd26bbcd20b023569a0e6e5abddd510c0a0994d18ed482132b82ac0d58"
# Candidate 0.2.3: T1306Z RELEASE uninstall still listed T1205Z as EXPECTED_HELPER;
# this candidate copy matches the verified T1306Z helper so current-version uninstall can target the reused payload.
# T1205Z legacy hash 5ed74e1f… is not deleted by this current-version uninstall path.
EXPECTED_BACKEND="ea512931a2793de2bc18fcd7b2b2a539d7964336b2696d75662b7d4cf34d2c15"
LEGACY_BACKEND_4="7105ddd2ce10f735d86747068c68749bce728f5a50502b6d093b2957a69dba25"
LEGACY_HELPER="44d54a4cfdd0a31b7c65c87db6dfa9599e67e1fa4aeb55a4a811b178f24b5da8"
LEGACY_BACKEND="2a00942530b8c28916e55dfc9984c1284f651fddd00d99a4398208b930530a7d"
LEGACY_HELPER_T1205Z="5ed74e1fe877a63ccacf683772c1f735d8b88d14fa0786e2c2f997db255b3aec"
LEGACY_HELPER_2="916b78cb6b95ca8a152f625d4f73c46f3142255fd85f6c12be6f19e3f62f5ac9"
LEGACY_HELPER_3="197d1f334536d9719598db4ccff46cf4b79f04bf3b05629c077c6f1536252ebe"
LEGACY_BACKEND_2="f5bc28e04299f77b8d99e425772c89b2ca54dabd25df2218b491f0363ec32aeb"
LEGACY_BACKEND_3="b03160fd14e0424a180c460f4fdd142767fdf8d26bdef0e7a1f1f7b01ad4d418"
EXPECTED_PLIST="d30e8029aacd1c80e093380a94fe52edb5d378eb90aeed9dc9e2ec6a03805e3e"

: "${LAUNCHCTL_BIN:=/bin/launchctl}"
: "${PS_BIN:=/bin/ps}"
: "${AWK_BIN:=/usr/bin/awk}"
: "${GREP_BIN:=/usr/bin/grep}"
: "${SHASUM_BIN:=/usr/bin/shasum}"
: "${RM_BIN:=/bin/rm}"
: "${LSOF_BIN:=/usr/sbin/lsof}"

using_system_destinations() {
  case "$HELPER_DST$BACKEND_DST$PLIST_DST" in
    /Library/*) return 0 ;;
    *) return 1 ;;
  esac
}

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
if [ "$DRY_RUN" -eq 0 ] && using_system_destinations && [ "$(/usr/bin/id -u)" -ne 0 ]; then
  exec /usr/bin/sudo "$0" "$@"
fi

/bin/mkdir -p "$RECORD_DIR"
LOG="$RECORD_DIR/uninstall-$(/bin/date +%Y%m%dT%H%M%S).log"
exec > >(/usr/bin/tee -a "$LOG") 2>&1

echo "=== MRA Device Control 0.2.2 helper uninstall ==="
echo "package_dir=$HERE"
echo "dry_run=$DRY_RUN"
echo "label=$LABEL"
echo "record_dir=$RECORD_DIR"

fail() { echo "UNINSTALL_FAILED: $*" >&2; exit 2; }
sha() { "$SHASUM_BIN" -a 256 "$1" | "$AWK_BIN" '{print $1}'; }

label_exists() {
  "$LAUNCHCTL_BIN" print "system/$LABEL" >/dev/null 2>&1
}
helper_pids() {
  "$PS_BIN" -axo pid=,command= 2>/dev/null | "$AWK_BIN" -v p="$HELPER_DST" '$2 == p {print $1}'
}
socket_listening() {
  [ -S "$SOCKET" ] || return 1
  "$LSOF_BIN" "$SOCKET" >/dev/null 2>&1
}
cleanup_gap_status() {
  if label_exists; then
    echo "DELETE_ABORTED_SERVICE_STILL_RUNNING"
    return 1
  fi
  if [ -n "$(helper_pids)" ]; then
    echo "DELETE_ABORTED_PROCESS_STILL_RUNNING"
    return 1
  fi
  if socket_listening; then
    echo "DELETE_ABORTED_SOCKET_STILL_LISTENING"
    return 1
  fi
  return 0
}

cleanup_stale_socket() {
  [ -e "$SOCKET" ] || return 0
  if socket_listening; then
    echo "DELETE_ABORTED_SOCKET_STILL_LISTENING"
    return 1
  fi
  "$RM_BIN" -f "$SOCKET" || return 1
  echo "STALE_SOCKET_REMOVED"
}
wait_clean() {
  local attempts="${1:-75}" i=0
  while [ "$i" -lt "$attempts" ]; do
    if ! label_exists && [ -z "$(helper_pids)" ] && ! socket_listening; then
      return 0
    fi
    /bin/sleep 0.2
    i=$((i+1))
  done
  cleanup_gap_status
  return 1
}
delete_if_expected() {
  local p=$1; shift
  local e
  [ -f "$p" ] || return 0
  for e in "$@"; do
    if [ "$(sha "$p")" = "$e" ]; then
      "$RM_BIN" -f "$p"
      return 0
    fi
  done
}
delete_exact_files() {
  delete_if_expected "$HELPER_DST" "$EXPECTED_HELPER" "$LEGACY_HELPER" "$LEGACY_HELPER_T1205Z" "$LEGACY_HELPER_2" "$LEGACY_HELPER_3"
  delete_if_expected "$BACKEND_DST" "$EXPECTED_BACKEND" "$LEGACY_BACKEND" "$LEGACY_BACKEND_2" "$LEGACY_BACKEND_3" "$LEGACY_BACKEND_4"
  delete_if_expected "$PLIST_DST" "$EXPECTED_PLIST"
}
post_delete_verify() {
  local p
  for p in "$HELPER_DST" "$BACKEND_DST" "$PLIST_DST"; do
    if [ -e "$p" ]; then echo "DELETE_VERIFY_FAILED_FILES_REMAIN"; return 1; fi
  done
  if label_exists; then echo "DELETE_VERIFY_FAILED_SERVICE_REMAINS"; return 1; fi
  if [ -n "$(helper_pids)" ]; then echo "DELETE_VERIFY_FAILED_PROCESS_REMAINS"; return 1; fi
  if socket_listening; then echo "DELETE_VERIFY_FAILED_SOCKET_LISTENING"; return 1; fi
  if [ -e "$SOCKET" ]; then echo "DELETE_VERIFY_FAILED_SOCKET_FILE_REMAINS"; return 1; fi
  echo "DELETE_VERIFY_OK"
  return 0
}

any=0
for p in "$HELPER_DST" "$BACKEND_DST" "$PLIST_DST"; do [ -e "$p" ] && any=1; done
if [ "$any" -eq 0 ]; then
  cleanup_stale_socket || fail "stale socket could not be removed"
  echo "NOT_INSTALLED"
  exit 0
fi
[ -f "$HELPER_DST" ] || fail "helper missing but other files exist"
[ -f "$BACKEND_DST" ] || fail "backend missing but other files exist"
[ -f "$PLIST_DST" ] || fail "plist missing but other files exist"
h="$(sha "$HELPER_DST")"
b="$(sha "$BACKEND_DST")"
p="$(sha "$PLIST_DST")"
echo "installed_helper=$h"
echo "installed_backend=$b"
echo "installed_plist=$p"
known_helper=0
for known in "$EXPECTED_HELPER" "$LEGACY_HELPER" "$LEGACY_HELPER_T1205Z" "$LEGACY_HELPER_2" "$LEGACY_HELPER_3"; do
  [ "$h" = "$known" ] && known_helper=1
done
known_backend=0
for known in "$EXPECTED_BACKEND" "$LEGACY_BACKEND" "$LEGACY_BACKEND_2" "$LEGACY_BACKEND_3" "$LEGACY_BACKEND_4"; do
  [ "$b" = "$known" ] && known_backend=1
done
known_pair=0
if [ "$p" = "$EXPECTED_PLIST" ]; then
  case "$h:$b" in
    "$EXPECTED_HELPER:$EXPECTED_BACKEND"|\
    "$EXPECTED_HELPER:$LEGACY_BACKEND_2"|\
    "$EXPECTED_HELPER:$LEGACY_BACKEND_3"|\
    "$LEGACY_HELPER:$LEGACY_BACKEND"|\
    "$LEGACY_HELPER_T1205Z:$LEGACY_BACKEND"|\
    "$LEGACY_HELPER_2:$LEGACY_BACKEND_2"|\
    "$LEGACY_HELPER_3:$LEGACY_BACKEND_2")
      known_pair=1
      ;;
  esac
fi
if [ "$known_helper" -ne 1 ] || [ "$known_backend" -ne 1 ] || [ "$known_pair" -ne 1 ]; then
  echo "STOP_UNKNOWN_VERSION"
  echo "No files were deleted."
  exit 3
fi
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY_RUN_OK"
  echo "WOULD_BOOTOUT=$LABEL"
  echo "WOULD_DELETE=$HELPER_DST"
  echo "WOULD_DELETE=$BACKEND_DST"
  echo "WOULD_DELETE=$PLIST_DST"
  echo "NOTE_DEV_MACHINE_HASH_OVERLAP=YES"
  echo "Live uninstall was not executed."
  exit 0
fi
if using_system_destinations; then
  [ "$(/usr/bin/id -u)" -eq 0 ] || fail "run as root"
elif [ "${MRA_TEST_HARNESS:-0}" != "1" ]; then
  fail "refusing to uninstall non-system destinations without MRA_TEST_HARNESS=1"
fi
echo "=== BOOTOUT ==="
"$LAUNCHCTL_BIN" bootout "system/$LABEL" >/dev/null 2>&1 || true
WAIT_ATTEMPTS="${MRA_WAIT_ATTEMPTS:-75}"
if ! wait_clean "$WAIT_ATTEMPTS"; then
  echo "UNINSTALL_ABORTED"
  echo "NO_FILES_DELETED"
  exit 4
fi
h2="$(sha "$HELPER_DST")"; { [ "$h2" = "$EXPECTED_HELPER" ] || [ "$h2" = "$LEGACY_HELPER" ] || [ "$h2" = "$LEGACY_HELPER_T1205Z" ] || [ "$h2" = "$LEGACY_HELPER_2" ] || [ "$h2" = "$LEGACY_HELPER_3" ]; } || fail "helper changed before deletion"
b2="$(sha "$BACKEND_DST")"; { [ "$b2" = "$EXPECTED_BACKEND" ] || [ "$b2" = "$LEGACY_BACKEND" ] || [ "$b2" = "$LEGACY_BACKEND_2" ] || [ "$b2" = "$LEGACY_BACKEND_3" ] || [ "$b2" = "$LEGACY_BACKEND_4" ]; } || fail "backend changed before deletion"
[ "$(sha "$PLIST_DST")" = "$EXPECTED_PLIST" ] || fail "plist changed before deletion"
cleanup_stale_socket || fail "service/socket is still live or stale socket could not be removed"
delete_exact_files
if ! post_delete_verify; then
  echo "UNINSTALL_INCOMPLETE"
  exit 5
fi
RECORD="$RECORD_DIR/uninstall-success-$(/bin/date +%Y%m%dT%H%M%S).txt"
{
  echo "label: $LABEL"
  echo "removed_helper=$EXPECTED_HELPER"
  echo "removed_backend=$EXPECTED_BACKEND"
  echo "removed_plist=$EXPECTED_PLIST"
  echo "socket=$SOCKET"
} > "$RECORD" 2>&1
echo "UNINSTALL_OK"
echo "record=$RECORD"
exit 0
