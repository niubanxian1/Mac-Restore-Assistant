#!/bin/bash
set -euo pipefail
: "${HELPER_DST:?}"
: "${BACKEND_DST:?}"
: "${PLIST_DST:?}"
: "${RM_BIN:=/bin/rm}"
echo "UNSAFE_ROLLBACK_BEGIN"
"$RM_BIN" -f "$HELPER_DST" "$BACKEND_DST" "$PLIST_DST"
echo "UNSAFE_ROLLBACK_DELETED"
exit 0
