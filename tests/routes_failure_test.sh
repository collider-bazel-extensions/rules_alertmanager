#!/usr/bin/env bash
# alertmanager_routes_test with a wrong expectation fails, saying where
# the label set actually routes and printing the routing tree.
set -euo pipefail

out="$TEST_TMPDIR/out.log"
rc=0
"$TEST_SRCDIR/$TEST_WORKSPACE/$1" >"$out" 2>&1 || rc=$?
cat "$out"
[[ $rc -ne 0 ]] || { echo "FAIL: wrong expectation passed" >&2; exit 1; }
grep -q "FAIL: {team=web} routes to \[default\], want \[pager\]" "$out" \
  || { echo "FAIL: mismatch not reported" >&2; exit 1; }
grep -q "Matching routes:" "$out" || { echo "FAIL: routing tree not printed" >&2; exit 1; }
echo "PASS"
