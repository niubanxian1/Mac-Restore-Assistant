#!/bin/bash
# Offline stub for Helper argv / fail-closed tests. Never sends VDM.
set -euo pipefail
action=""
controller=""
port=""
rid=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    dfu|reboot|recovery|probe) action="$1"; shift ;;
    --controller) controller="${2:-}"; shift 2 ;;
    --port-number) port="${2:-}"; shift 2 ;;
    --rid) rid="${2:-}"; shift 2 ;;
    *) echo "UNKNOWN_ARG=$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$action" || -z "$controller" || -z "$port" || -z "$rid" ]]; then
  echo '{"status":"BLOCKED","reason":"TRIPLET_REQUIRED","send_performed":false}' 
  echo "TRIPLET_REQUIRED" >&2
  exit 2
fi

if [[ "${MRA_STUB_AMBIGUOUS:-}" == "1" ]]; then
  echo "controller=$controller port-number=$port rid=$rid action=$action send_performed=false"
  echo "{\"rid_selective\":true,\"requested_rid\":$rid,\"controller\":\"$controller\",\"port_number\":$port,\"candidate_service_count\":2,\"send_performed\":false,\"status\":\"BLOCKED\",\"reason\":\"RID_SERVICE_AMBIGUOUS\"}"
  echo "RID_SERVICE_AMBIGUOUS" >&2
  exit 2
fi

echo "controller=$controller port-number=$port rid=$rid action=$action send_performed=false"
echo "{\"rid_selective\":true,\"requested_rid\":$rid,\"controller\":\"$controller\",\"port_number\":$port,\"candidate_service_count\":1,\"send_performed\":false,\"status\":\"READY\",\"reason\":\"\"}"
exit 0
