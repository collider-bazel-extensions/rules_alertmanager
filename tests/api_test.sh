#!/usr/bin/env bash
# alertmanager_test against tests/testdata/alertmanager.yml: routing with
# `continue`, inhibition, silences and resolved notifications, all
# checked through the API and the webhook sink.
set -euo pipefail
# shellcheck disable=SC1090
source "$ALERTMANAGER_TESTLIB"

fail() { echo "FAIL: $*" >&2; am_notifications >&2 || true; exit 1; }
AM=("$AMTOOL" --alertmanager.url="$ALERTMANAGER_URL")

for v in ALERTMANAGER_URL ALERTMANAGER_HOST ALERTMANAGER_PORT AMTOOL \
         ALERTMANAGER_WEBHOOK_URL ALERTMANAGER_WEBHOOK_DIR; do
  [[ -n "${!v:-}" ]] || fail "\$$v not set"
done
[[ "$ALERTMANAGER_URL" == "http://127.0.0.1:$ALERTMANAGER_PORT" ]] || fail "URL/port mismatch"

# The running config is ours, with the placeholders expanded (amtool
# redacts URLs, so read the launcher's expanded copy).
"${AM[@]}" config show | grep -q "name: db-pager" || fail "running config lacks db-pager"
expanded="$TEST_TMPDIR/alertmanager-api_test_alertmanager/config/alertmanager.yml"
grep -qF "url: \"$ALERTMANAGER_WEBHOOK_URL\"" "$expanded" || fail "webhook URL placeholder not expanded"
grep -qF 'api_url: "http://127.0.0.1:9/"' "$expanded" || fail "SLACK_URL (from env) not expanded"
grep -q '\${' "$expanded" && fail "unexpanded placeholder left in $expanded"
echo "PASS: running config has expanded placeholders"

# 1. team=db routes to db-pager and (continue: true) audit.
am_post_alert alertname=DiskFull team=db severity=page -- summary="disk full"
am_wait_notifications 2 >/dev/null || fail "no db notifications"
all=$(am_notifications)
grep -q '"receiver":"db-pager"' <<<"$all" || fail "no db-pager notification"
grep -q '"receiver":"audit"' <<<"$all" || fail "no audit notification"
grep -q '"summary":"disk full"' <<<"$all" || fail "annotation missing from payload"
! grep -q '"receiver":"pager"' <<<"$all" || fail "team=db also reached pager"
echo "PASS: team=db -> db-pager + audit"

# 2. Inhibition: a page suppresses the warn with the same alertname.
am_post_alert alertname=Latency severity=page
am_post_alert alertname=Latency severity=warn
deadline=$(( $(date +%s) + 30 ))
until "${AM[@]}" -o json alert query --inhibited alertname=Latency severity=warn \
        | grep -q '"inhibitedBy":\["'; do
  (( $(date +%s) < deadline )) || fail "severity=warn Latency not inhibited"
  sleep 0.5
done
echo "PASS: warn inhibited by page"

# 3. Silence: a silenced alert is muted and not notified.
sid=$("${AM[@]}" silence add alertname=Quiet --comment="api_test" --author=rules_alertmanager)
"${AM[@]}" silence query -q | grep -qx "$sid" || fail "silence $sid not listed"
am_post_alert alertname=Quiet team=web
deadline=$(( $(date +%s) + 30 ))
until "${AM[@]}" -o json alert query --silenced alertname=Quiet | grep -q "\"silencedBy\":\[\"$sid\"\]"; do
  (( $(date +%s) < deadline )) || fail "Quiet not silenced by $sid"
  sleep 0.5
done
echo "PASS: silence $sid mutes alertname=Quiet"

# 4. Resolution: an alert that ends is notified as resolved (default
#    receiver has send_resolved: true).
am_post_alert alertname=Flap team=web
before=$(am_notifications | grep -c '"alertname":"Flap"' || true)
"${AM[@]}" alert add alertname=Flap team=web --end="$(date -u -d '-1 second' +%Y-%m-%dT%H:%M:%SZ)"
deadline=$(( $(date +%s) + 30 ))
until am_notifications | grep '"alertname":"Flap"' | grep -q '"status":"resolved"'; do
  (( $(date +%s) < deadline )) || fail "no resolved notification for Flap (had $before firing)"
  sleep 0.5
done
echo "PASS: resolved notification for Flap"

# Silenced alerts never notified.
! am_notifications | grep -q '"alertname":"Quiet"' || fail "silenced alert was notified"
echo "PASS: api_test"
