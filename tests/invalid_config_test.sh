#!/usr/bin/env bash
# The alertmanager_config check (private/check_config.sh) accepts the test
# config and rejects an invalid one and an unresolved placeholder.
set -euo pipefail

root="$TEST_SRCDIR/$TEST_WORKSPACE"
CHECK="$root/$1"; shift
AMTOOL=""
for p in "$@"; do [[ "$p" == */amtool ]] && AMTOOL="$(cd "$root" && realpath "$p")"; done
[[ -x "$AMTOOL" ]] || { echo "FAIL: amtool not in runfiles" >&2; exit 1; }
data="$root/tests/testdata"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Stage like alertmanager_config does: config + templates in one dir.
stage="$TEST_TMPDIR/stage"
mkdir -p "$stage"
cp "$data/alertmanager.yml" "$data/rules_alertmanager.tmpl" "$stage/"
"$CHECK" "$AMTOOL" "$stage/alertmanager.yml" "$TEST_TMPDIR/ok.yml" \
  ALERTMANAGER_WEBHOOK_URL=http://127.0.0.1:9/ SLACK_URL=https://hooks.slack.invalid/x \
  || fail "valid config rejected"
grep -q "https://hooks.slack.invalid/x" "$TEST_TMPDIR/ok.yml" || fail "placeholder not resolved in output"
echo "PASS: valid config accepted, placeholders resolved"

if "$CHECK" "$AMTOOL" "$data/bad_receiver.yml" "$TEST_TMPDIR/bad.yml" 2>"$TEST_TMPDIR/bad.log"; then
  fail "bad_receiver.yml accepted"
fi
cat "$TEST_TMPDIR/bad.log"
grep -q 'undefined receiver "nowhere"' "$TEST_TMPDIR/bad.log" || fail "amtool error not shown"
[[ ! -e "$TEST_TMPDIR/bad.yml" ]] || fail "output written for an invalid config"
echo "PASS: undefined receiver rejected"

if "$CHECK" "$AMTOOL" "$data/needs_placeholder.yml" "$TEST_TMPDIR/ph.yml" 2>"$TEST_TMPDIR/ph.log"; then
  fail "unresolved placeholder accepted"
fi
cat "$TEST_TMPDIR/ph.log"
grep -q 'MISSING_URL' "$TEST_TMPDIR/ph.log" || fail "unresolved placeholder not named"
echo "PASS: unresolved placeholder rejected"
