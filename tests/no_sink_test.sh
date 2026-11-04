#!/usr/bin/env bash
# alertmanager_test(webhook_sink = False): no sink variables; the server
# runs its default config and still accepts and serves alerts.
set -euo pipefail

[[ -z "${ALERTMANAGER_WEBHOOK_URL:-}" && -z "${ALERTMANAGER_WEBHOOK_DIR:-}" ]] \
  || { echo "FAIL: webhook variables set without a sink" >&2; exit 1; }
"$AMTOOL" --alertmanager.url="$ALERTMANAGER_URL" alert add alertname=NoSink
"$AMTOOL" --alertmanager.url="$ALERTMANAGER_URL" -o json alert query alertname=NoSink \
  | grep -q '"receivers":\[{"name":"default"}\]' \
  || { echo "FAIL: NoSink not routed to the default receiver" >&2; exit 1; }
curl -fsS "$ALERTMANAGER_URL/api/v2/status" | grep -q '"cluster":{[^}]*"status":"disabled"' \
  || { echo "FAIL: clustering not disabled" >&2; exit 1; }
echo "PASS: no_sink_test"
