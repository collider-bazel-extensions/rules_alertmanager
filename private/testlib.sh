#!/usr/bin/env bash
# Helpers for alertmanager_test scripts:  source "$ALERTMANAGER_TESTLIB"
#
#   am_post_alert LABEL=VALUE... [-- ANNOTATION=VALUE...]
#       Fire an alert through the v2 API (via amtool).
#   am_wait_notifications N [TIMEOUT_S]
#       Wait until the webhook sink has received at least N notifications
#       (default timeout 30 s); prints the paths of the payload files.
#   am_notifications
#       Print every received payload, one per line, in arrival order.

am_post_alert() {
  local labels=() annotations=()
  while (( $# )); do
    if [[ "$1" == "--" ]]; then shift; annotations=("$@"); break; fi
    labels+=("$1"); shift
  done
  local a ann_flags=()
  for a in "${annotations[@]}"; do ann_flags+=("--annotation=$a"); done
  "$AMTOOL" --alertmanager.url="$ALERTMANAGER_URL" alert add "${labels[@]}" "${ann_flags[@]}"
}

_am_payloads() {
  local f
  for f in $(ls "$ALERTMANAGER_WEBHOOK_DIR" 2>/dev/null | grep -E '^[0-9]+\.json$' | sort -n); do
    printf '%s\n' "$ALERTMANAGER_WEBHOOK_DIR/$f"
  done
}

am_wait_notifications() {
  local want="$1" timeout="${2:-30}"
  : "${ALERTMANAGER_WEBHOOK_DIR:?am_wait_notifications needs the webhook sink (webhook_sink = True)}"
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(_am_payloads | wc -l) < want )); do
    if (( $(date +%s) >= deadline )); then
      echo "am_wait_notifications: got $(_am_payloads | wc -l) of $want notification(s) within ${timeout}s" >&2
      return 1
    fi
    sleep 0.2
  done
  _am_payloads
}

am_notifications() {
  local f
  for f in $(_am_payloads); do cat "$f"; echo; done
}
