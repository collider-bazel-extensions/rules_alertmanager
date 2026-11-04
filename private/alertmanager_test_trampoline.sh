#!/usr/bin/env bash
# alertmanager_test trampoline — webhook sink (optional) + server, then
# execs the user's test.
#
# Argv: <server> <inner> <server_name> <webhook_sink.py or "-"> <testlib.sh> [user args...]
set -euo pipefail

SERVER_SHORT="$1"; INNER_SHORT="$2"; SERVER_NAME="$3"; SINK_SHORT="$4"; LIB_SHORT="$5"
shift 5

: "${TEST_TMPDIR:?alertmanager_test: TEST_TMPDIR not set (expected under bazel test)}"
if [[ -z "${RUNFILES_DIR:-}" ]]; then
  RUNFILES_DIR="${TEST_SRCDIR:-$0.runfiles}"
  export RUNFILES_DIR
fi

resolve() {
  local p="$1"
  for c in "${RUNFILES_DIR}/_main/${p}" "${RUNFILES_DIR}/${p}" "${RUNFILES_DIR}/${p#../}"; do
    [[ -e "$c" ]] && { printf '%s\n' "$c"; return; }
  done
  echo "alertmanager_test: not in runfiles: ${p}" >&2
  exit 1
}

pids=()
cleanup() {
  local pid
  for pid in "${pids[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Wait up to $2 seconds for file $1; $3 is a pid that must stay alive.
wait_for() {
  local deadline=$(( $(date +%s) + $2 ))
  until [[ -f "$1" ]]; do
    if ! kill -0 "$3" 2>/dev/null; then
      echo "alertmanager_test: process $3 exited before writing $1" >&2
      return 1
    fi
    if (( $(date +%s) >= deadline )); then
      echo "alertmanager_test: timed out after $2 s waiting for $1" >&2
      return 1
    fi
    sleep 0.1
  done
}

if [[ "$SINK_SHORT" != "-" ]]; then
  export ALERTMANAGER_WEBHOOK_DIR="$TEST_TMPDIR/${SERVER_NAME}_webhook"
  port_file="$TEST_TMPDIR/${SERVER_NAME}_webhook.port"
  python3 "$(resolve "$SINK_SHORT")" "$ALERTMANAGER_WEBHOOK_DIR" "$port_file" &
  pids+=($!)
  wait_for "$port_file" 30 "${pids[-1]}"
  export ALERTMANAGER_WEBHOOK_URL="http://127.0.0.1:$(cat "$port_file")/"
fi

env_file="$TEST_TMPDIR/${SERVER_NAME}.env"
rm -f "$env_file"
"$(resolve "$SERVER_SHORT")" &
pids+=($!)
# The server enforces its own ready_timeout; this outer bound only
# guards against a hung launcher.
wait_for "$env_file" 600 "${pids[-1]}"

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a
ALERTMANAGER_TESTLIB="$(resolve "$LIB_SHORT")"
export ALERTMANAGER_TESTLIB

# Not exec: the trap must stop the server and sink when the test ends.
"$(resolve "$INNER_SHORT")" "$@"
