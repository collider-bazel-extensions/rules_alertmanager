#!/usr/bin/env bash
# alertmanager_server lifecycle:
#   - writes the env file once /-/ready answers, with all four keys
#   - extra_args reach alertmanager (--log.level=debug)
#   - SIGTERM: exits 0 and removes the env file
#   - an unset config placeholder fails the start, naming it
set -euo pipefail

root="$TEST_SRCDIR/$TEST_WORKSPACE"
SERVER="$root/$1"
PLACEHOLDER_SERVER="$root/$2"
env_file="$TEST_TMPDIR/test_server.env"
fail() { echo "FAIL: $*" >&2; exit 1; }

"$SERVER" 2>"$TEST_TMPDIR/server.log" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
for _ in $(seq 300); do
  [[ -f "$env_file" ]] && break
  kill -0 "$pid" 2>/dev/null || { cat "$TEST_TMPDIR/server.log" >&2; fail "server exited early"; }
  sleep 0.1
done
[[ -f "$env_file" ]] || fail "env file not written within 30 s"
cat "$env_file"
for k in ALERTMANAGER_URL ALERTMANAGER_HOST ALERTMANAGER_PORT AMTOOL; do
  grep -q "^$k=." "$env_file" || fail "env file lacks $k"
done
# shellcheck disable=SC1090
source "$env_file"
[[ "$(curl -fsS -o /dev/null -w '%{http_code}' "$ALERTMANAGER_URL/-/ready")" == 200 ]] || fail "/-/ready not 200"
[[ -x "$AMTOOL" ]] || fail "AMTOOL not executable"
"$AMTOOL" --alertmanager.url="$ALERTMANAGER_URL" config show | grep -q "name: default" \
  || fail "default config not running"
grep -q "level=debug\|level=DEBUG" "$TEST_TMPDIR/alertmanager-test_server/alertmanager.log" \
  || fail "extra_args --log.level=debug had no effect"
echo "PASS: env file, readiness, default config, extra_args"

kill -TERM "$pid"
rc=0; wait "$pid" || rc=$?
[[ $rc -eq 0 ]] || fail "SIGTERM exit status $rc, want 0"
[[ ! -e "$env_file" ]] || fail "env file left after SIGTERM"
curl -fsS "$ALERTMANAGER_URL/-/ready" >/dev/null 2>&1 && fail "alertmanager still serving after SIGTERM"
echo "PASS: SIGTERM shuts down cleanly"

rc=0
env -u MISSING_URL "$PLACEHOLDER_SERVER" 2>"$TEST_TMPDIR/placeholder.log" || rc=$?
cat "$TEST_TMPDIR/placeholder.log"
[[ $rc -ne 0 ]] || fail "server with an unset placeholder started"
grep -q "placeholders not set in the environment: MISSING_URL" "$TEST_TMPDIR/placeholder.log" \
  || fail "unset placeholder not named"
echo "PASS: unset placeholder is an error naming it"
