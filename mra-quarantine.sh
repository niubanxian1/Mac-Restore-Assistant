#!/bin/bash
# Quarantine inspection/clear helpers for MRA 0.2.2 deploy scripts.
# Source this file; do not run it as a standalone installer.
# Clearing is only called after explicit confirmation, and only on the
# paths the caller passes (current deploy payload). Never touches
# Gatekeeper, AMFI, spctl, SIP, or any global security setting.

: "${XATTR_BIN:=/usr/bin/xattr}"
: "${FIND_BIN:=/usr/bin/find}"

quarantine_scan() {
  local root="${1:?}" p
  [ -e "$root" ] || return 0
  # Process substitution + explicit return 0: `read -d ""` hits EOF with
  # status 1, which would abort a `set -o pipefail` installer.
  while IFS= read -r -d '' p; do
    if "$XATTR_BIN" -p com.apple.quarantine "$p" >/dev/null 2>&1; then
      printf '%s\n' "$p"
    fi
  done < <("$FIND_BIN" "$root" -print0) || true
  return 0
}

quarantine_clear_scoped() {
  local root
  for root in "$@"; do
    [ -e "$root" ] || continue
    if ! "$XATTR_BIN" -dr com.apple.quarantine "$root"; then
      return 1
    fi
  done
  return 0
}
