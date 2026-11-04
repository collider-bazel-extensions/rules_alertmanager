#!/usr/bin/env bash
# alertmanager_install(config = ...) replaces exactly the chart's
# `alertmanager` ConfigMap data with the resolved config + templates and
# leaves every other document byte-for-byte unchanged.
set -euo pipefail

root="$TEST_SRCDIR/$TEST_WORKSPACE"
orig="$root/$1"
got="$root/$2"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $(grep -c '^kind: ' "$got") -eq $(grep -c '^kind: ' "$orig") ]] || fail "document count changed"
[[ $(grep -c '^kind: ConfigMap' "$got") -eq 1 ]] || fail "want exactly one ConfigMap"

cm=$(awk '/^kind: ConfigMap/{p=1} p && /^---/{exit} p' "$got")
grep -q '^  alertmanager.yml: |$' <<<"$cm" || fail "no alertmanager.yml key"
grep -q '^  rules_alertmanager.tmpl: |$' <<<"$cm" || fail "template not added under its basename"
grep -q '^    route:$' <<<"$cm" || fail "config body not indented under the key"
grep -q 'receiver: db-pager$' <<<"$cm" || fail "config routes missing"
grep -q 'https://hooks.slack.invalid/T000/B000/XXX' <<<"$cm" || fail "SLACK_URL not resolved"
grep -q 'http://127.0.0.1:9/' <<<"$cm" || fail "ALERTMANAGER_WEBHOOK_URL not resolved"
grep -q 'default-receiver' <<<"$cm" && fail "chart's default config still present"
grep -q '^  namespace: alertmanager$' <<<"$cm" || fail "ConfigMap metadata lost"

# Everything outside the ConfigMap is unchanged.
strip_cm() { awk '/^kind: ConfigMap/{skip=1} /^---/{skip=0} !skip' "$1"; }
diff <(strip_cm "$orig") <(strip_cm "$got") || fail "documents other than the ConfigMap changed"
echo "PASS"
