#!/usr/bin/env bash
# alertmanager_test with no config: everything goes to the webhook sink.
# Also checks the target's args reach the test.
set -euo pipefail
# shellcheck disable=SC1090
source "$ALERTMANAGER_TESTLIB"

[[ $# -eq 2 && "$1" == "one" && "$2" == "two words" ]] \
  || { echo "FAIL: args = [$*], want [one] [two words]" >&2; exit 1; }
echo "PASS: args forwarded"

am_post_alert alertname=Hello instance=a
am_post_alert alertname=Hello instance=b
am_wait_notifications 2 >/dev/null
all=$(am_notifications)
grep -q '"receiver":"webhook"' <<<"$all" || { echo "FAIL: receiver not webhook" >&2; exit 1; }
for i in a b; do
  grep -q "\"instance\":\"$i\"" <<<"$all" || { echo "FAIL: instance $i not notified" >&2; exit 1; }
done
echo "PASS: default config delivers each alert to the sink"
