#!/usr/bin/env bash
# Full E2E install smoke for alertmanager_install(config = ...):
#
#   1. The itest chain (kind → alertmanager_install) has applied the chart
#      with our ConfigMap and waited for sts/alertmanager to roll out.
#   2. kubectl exec amtool inside the pod (the image ships it):
#      - the running config is ours (smoke-receiver), not the chart's
#      - our template is mounted beside the config
#      - an alert round-trips: add, then query routes it to smoke-receiver.
set -euo pipefail

env_file="$TEST_TMPDIR/cluster.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")
NS=alertmanager
POD=alertmanager-0
fail() {
  echo "smoke: FAIL — $*" >&2
  "${KCTL[@]}" -n "$NS" get pods -o wide >&2 || true
  "${KCTL[@]}" -n "$NS" logs "$POD" -c alertmanager --tail=100 >&2 || true
  exit 1
}

"${KCTL[@]}" -n "$NS" wait "pod/$POD" --for=condition=Ready --timeout=180s
KEXEC=("${KCTL[@]}" -n "$NS" exec "$POD" -c alertmanager --)
AM=("${KEXEC[@]}" amtool --alertmanager.url=http://127.0.0.1:9093)

config=$("${AM[@]}" config show) || fail "amtool config show"
grep -q "name: smoke-receiver" <<<"$config" || fail "running config is not ours: $config"
grep -q "default-receiver" <<<"$config" && fail "chart's default config still running"
echo "smoke: running config has smoke-receiver"

"${KEXEC[@]}" ls /etc/alertmanager | grep -qx smoke.tmpl || fail "smoke.tmpl not mounted"
echo "smoke: template mounted at /etc/alertmanager/smoke.tmpl"

"${AM[@]}" alert add alertname=InstallSmoke severity=info >/dev/null || fail "alert add"
deadline=$(( $(date +%s) + 60 ))
until "${AM[@]}" -o json alert query alertname=InstallSmoke | grep -q '"receivers":\[{"name":"smoke-receiver"}\]'; do
  (( $(date +%s) < deadline )) || fail "InstallSmoke not routed to smoke-receiver"
  sleep 1
done
echo "smoke: OK — alert routed to smoke-receiver in the cluster"
