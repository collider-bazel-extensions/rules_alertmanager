"""Maintainer-side: Alertmanager Helm chart pin for the helm-render flow.

Consumers don't see this — it's loaded only by the dev-only chart-fetch
extension under tools/. The committed manifest at
`//private/manifests:alertmanager.yaml` is what consumers apply.

The chart is the prometheus-community `alertmanager` chart, published as
a packaged `.tgz` on the helm-charts GitHub release.

Update flow:
    1. Add an entry (chart_url + chart_sha256):
           curl -fsSL "<url>" | sha256sum
    2. Add (or update) a `helm_template` + `sh_binary` block in
       tools/BUILD.bazel for the new version.
    3. `tools/render_alertmanager.sh <version>`.
"""

ALERTMANAGER_CHART_VERSIONS = {
    "2.1.4": {
        # appVersion v0.34.2 (matches the pinned binaries).
        "chart_url":    "https://github.com/prometheus-community/helm-charts/releases/download/alertmanager-2.1.4/alertmanager-2.1.4.tgz",
        "chart_sha256": "d28538c1f6352a995f1acdfbc605cf5dd5aef4896a5dae99950be6f4116d6661",
    },
}
