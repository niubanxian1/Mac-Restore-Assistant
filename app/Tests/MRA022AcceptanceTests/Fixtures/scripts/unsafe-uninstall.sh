#!/bin/bash
# Intentionally unsafe: deletes destination files while a service may still
# be running. Used only as a RED baseline against the safety contract.
set -euo pipefail
: "${HELPER_DST:?}"
: "${BACKEND_DST:?}"
: "${PLIST_DST:?}"
: "${RM_BIN:=/bin/rm}"
echo "UNSAFE_UNINSTALL_BEGIN"
"$RM_BIN" -f "$HELPER_DST" "$BACKEND_DST" "$PLIST_DST"
echo "UNSAFE_UNINSTALL_DELETED"
exit 0
