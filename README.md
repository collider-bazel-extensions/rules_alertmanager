# rules_alertmanager

Bazel rules for [Prometheus Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/): validate configs at build time, test routing, run a hermetic Alertmanager in tests (with a webhook sink that records notifications), and install it into a cluster. Three families in one repo:

- **Config (build time)**
  - `alertmanager_config` — `alertmanager.yml` + notification templates. `amtool check-config` runs as a validation action, so a broken config fails `bazel build`.
  - `alertmanager_routes_test` — asserts which receivers a label set routes to (`amtool config routes test`).
- **Hermetic server (test-time)**
  - `alertmanager_server` — long-running `alertmanager` on a free port; writes `$TEST_TMPDIR/<name>.env` once `/-/ready` answers.
  - `alertmanager_health_check` — pairs with `alertmanager_server` for `itest_service`.
  - `alertmanager_test` — sh_test macro: auto-launches a server and a webhook sink, then runs your test with `ALERTMANAGER_URL`, `AMTOOL` and the sink's location in its environment.
- **Cluster install (kind / production)**
  - `alertmanager_install` — applies the pinned prometheus-community chart, optionally with your `alertmanager_config`, and waits for `sts/alertmanager`.
  - `alertmanager_install_health_check` — paired readiness probe.

No host `alertmanager`, `amtool`, `helm` or Go needed: binaries come from the pinned, SHA-256-verified upstream release tarballs.

## Install (Bzlmod)

```python
bazel_dep(name = "rules_alertmanager", version = "0.1.3")
git_override(
    module_name = "rules_alertmanager",
    remote = "https://github.com/collider-bazel-extensions/rules_alertmanager",
    commit = "9cbc2ec5fe0b5c2fcf583bbc649013ddc8cb396f",  # v0.1.2
)
```

To pin by archive and integrity instead of a git commit, replace the `git_override` with:

```python
archive_override(
    module_name = "rules_alertmanager",
    urls = ["https://github.com/collider-bazel-extensions/rules_alertmanager/archive/refs/tags/v0.1.2.tar.gz"],
    strip_prefix = "rules_alertmanager-0.1.2",
    integrity = "sha256-wflh6O8sCF5fHrYkr/BWqVdqAw8s+EyzeKkeRPW4S2Y=",
)
```

rules_kubectl isn't in the BCR either, so a consumer overrides it too:

```python
bazel_dep(name = "rules_kubectl", version = "0.2.0")
git_override(
    module_name = "rules_kubectl",
    remote = "https://github.com/collider-bazel-extensions/rules_kubectl",
    commit = "81b60ab80df46b64c612f2576ffef0a7af98ccb6",  # v0.2.0
)
```

rules_alertmanager's own `MODULE.bazel` fetches Alertmanager 0.34.2 and registers the toolchain, so no `alertmanager` extension wiring is needed.

The `alertmanager` extension creates `@alertmanager_<ver>_<plat>` repos for every module's `alertmanager.version(...)` tags, deduplicated. A version you add yourself gives you repos to `use_repo`; the registered toolchain stays on rules_alertmanager's pinned version. A version not pinned in `private/versions.bzl` fails with a message naming `alertmanager.version`. Before v0.1.3 only the root module's tags counted, so a root without `alertmanager.version(version = "0.34.2")` failed with `does not generate repository "alertmanager_0_34_2_darwin_amd64"`; the `alertmanager.version(...)` / `use_repo(...)` / `register_toolchains(...)` lines earlier READMEs asked for are harmless but no longer needed.

The release archive leaves out `tests/` and `tools/`, which load dev-only modules (rules_itest, rules_kind, rules_helm), so `bazel query @rules_alertmanager//...` works with `archive_override`. A `git_override` checks out the whole repository, and `@rules_alertmanager//...` then fails to load; name packages instead (`@rules_alertmanager//:all`, `@rules_alertmanager//toolchain:all`).

The install primitives also pull in [rules_kubectl](https://github.com/collider-bazel-extensions/rules_kubectl) (they wrap `kubectl_apply`). The server and test rules need `python3` on the host, as rules_nats and rules_pg do.

## Config

```python
load("@rules_alertmanager//:defs.bzl", "alertmanager_config", "alertmanager_routes_test")

alertmanager_config(
    name = "am_config",
    src = "alertmanager.yml",
    templates = glob(["templates/*.tmpl"]),
    placeholders = {"SLACK_URL": "https://hooks.slack.invalid/x"},
)

alertmanager_routes_test(
    name = "routes_test",
    config = ":am_config",
    routes = {
        "team=db severity=page": ["db-pager", "audit"],  # in order; `continue: true`
        "severity=page": "pager",
        "alertname=Anything": "default",
    },
)
```

- **Templates** are staged beside `alertmanager.yml` under their basenames. Reference them as `templates: ["*.tmpl"]`, which resolves relative to the config the same way locally and in the cluster.
- **`${NAME}` placeholders** let one config serve several environments:
  - `alertmanager_server` (and so `alertmanager_test`) expands them from its environment at start. An unset one fails the start and names it.
  - The build-time check, routes tests and `alertmanager_install` use the values in `placeholders`. A placeholder with no value fails the build.
  - `ALERTMANAGER_WEBHOOK_URL` needs no entry; its default is `http://127.0.0.1:9/`.
- **`alertmanager_routes_test`** runs every case and reports all mismatches, each with the matching routing tree:

  ```
  FAIL: {team=web} routes to [default], want [pager]
  ```

| `alertmanager_config` attribute | Description |
|---|---|
| `src` | `alertmanager.yml` (required). |
| `templates` | Notification template files, staged beside the config by basename. |
| `placeholders` | Build-time value for each `${NAME}` (check, routes tests, install). |

## Hermetic server

### `alertmanager_test`

```python
load("@rules_alertmanager//:defs.bzl", "alertmanager_test")

alertmanager_test(
    name = "alerting_test",
    srcs = ["alerting_test.sh"],
    config = ":am_config",             # optional; default: everything to the sink
    env = {"SLACK_URL": "http://127.0.0.1:9/"},  # placeholders the server expands
)
```

```sh
# alerting_test.sh
source "$ALERTMANAGER_TESTLIB"
am_post_alert alertname=DiskFull team=db severity=page -- summary="disk full"
am_wait_notifications 2                       # paths of the first 2 payloads
am_notifications | grep -q '"receiver":"db-pager"'
"$AMTOOL" --alertmanager.url="$ALERTMANAGER_URL" silence add alertname=Quiet --comment=test
```

Environment of the test:

| Variable | Example | |
|---|---|---|
| `ALERTMANAGER_URL` | `http://127.0.0.1:36627` | API base URL |
| `ALERTMANAGER_HOST` / `ALERTMANAGER_PORT` | `127.0.0.1` / `36627` | |
| `AMTOOL` | `/…/amtool` | the toolchain's amtool |
| `ALERTMANAGER_WEBHOOK_URL` | `http://127.0.0.1:40121/` | the sink (also expanded into the config) |
| `ALERTMANAGER_WEBHOOK_DIR` | `$TEST_TMPDIR/…_webhook` | one `<n>.json` per notification received |
| `ALERTMANAGER_TESTLIB` | `/…/testlib.sh` | `am_post_alert`, `am_wait_notifications`, `am_notifications` |

| Argument | Default | |
|---|---|---|
| `srcs` | — | the test script |
| `config` | everything to the sink, `group_wait: 0s` | an `alertmanager_config` |
| `webhook_sink` | `True` | `False`: no sink variables; default config has one silent receiver |
| `ready_timeout` | `30` | seconds to wait for `/-/ready` |
| `extra_args` | `[]` | extra `alertmanager` flags |
| `args`, `env`, `data`, `deps`, `size`, `timeout`, `tags`, … | | as for `sh_test` |

Each test gets its own server: its own port and storage, with clustering off. Tests are safe under `--jobs=N`.

### `alertmanager_server` + `alertmanager_health_check` (rules_itest)

```python
load("@rules_alertmanager//:defs.bzl", "alertmanager_health_check", "alertmanager_server")
load("@rules_itest//:itest.bzl", "itest_service")

alertmanager_server(name = "am", config = ":am_config", tags = ["manual"])
alertmanager_health_check(name = "am_health", server = ":am", tags = ["manual"])

itest_service(
    name = "am_svc",
    exe = ":am",
    health_check = ":am_health",
    env = {"SLACK_URL": "http://127.0.0.1:9/"},
)
```

The server writes `$TEST_TMPDIR/am.env` (`ALERTMANAGER_URL`, `ALERTMANAGER_HOST`, `ALERTMANAGER_PORT`, `AMTOOL`) once `/-/ready` answers. It stops on SIGTERM and removes the file.

| `alertmanager_server` attribute | Default | |
|---|---|---|
| `config` | one `default` receiver, no notifiers | an `alertmanager_config` |
| `ready_timeout` | `"30"` | seconds to wait for `/-/ready` |
| `extra_args` | `[]` | extra flags, e.g. `["--data.retention=1h"]` |

## Cluster install

```python
load("@rules_alertmanager//:defs.bzl", "alertmanager_install", "alertmanager_install_health_check")

alertmanager_install(
    name = "am_install",
    config = ":am_config",      # optional: replaces the chart's default config
    tags = ["manual"],
)

alertmanager_install_health_check(name = "am_install_health", tags = ["manual"])

itest_service(
    name = "am_install_svc",
    exe = ":am_install",
    health_check = ":am_install_health",
    deps = [":kind_svc"],
    tags = ["manual"],
)
```

- **Your config in the chart:** `config` replaces the chart's `alertmanager` ConfigMap at build time with your resolved config (placeholders take their `placeholders` values) plus your templates. They are mounted at `/etc/alertmanager`, beside the config.
- **Config reloads:** the chart's configmap-reload sidecar picks up later edits to the ConfigMap.
- **Namespace:** the rendered manifest is pinned to the `alertmanager` namespace.
- **Smoke test:** `tests/install_smoke/` deploys to kind and runs `amtool` inside the pod. It checks that the running config is ours, that the template is mounted, and that an alert routes to our receiver.

## Pinned versions

| Component | Version | Source |
|---|---|---|
| alertmanager + amtool | `0.34.2` | https://github.com/prometheus/alertmanager/releases (`sha256sums.txt`) |
| Helm chart | `alertmanager-2.1.4` (appVersion v0.34.2) | https://github.com/prometheus-community/helm-charts/releases |

Maintainer flows:
- **New binaries:** `tools/update_checksums.sh <version>` pins the four platforms from `sha256sums.txt`, cross-checked against the downloads. `--check` verifies the pins without writing anything.
- **Chart:** edit `tools/versions.bzl` and `tools/BUILD.bazel`, then run `tools/render_alertmanager.sh <version>`. This uses [rules_helm](https://github.com/collider-bazel-extensions/rules_helm), so no host helm is needed. CI fails if the committed manifest drifts from the render.

## Development

```sh
bazel test //tests/...                                   # no container runtime
bazel test //tests/install_smoke:smoke_test --test_output=streamed   # needs Docker or podman
```

See [DESIGN.md](DESIGN.md) for the architecture and trade-offs.
