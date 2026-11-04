# rules_alertmanager

Bazel rules for Prometheus Alertmanager: build-time config validation,
routing tests, a hermetic per-test Alertmanager (with a webhook sink), and
a cluster install over the pinned prometheus-community chart. Designed for
use with [rules_itest](https://github.com/dzbarsky/rules_itest) and
[rules_kind](https://github.com/collider-bazel-extensions/rules_kind).

## Commit requirements

- All tests must pass before any commit with code changes
  (`bazel test //tests/...`; the kind smoke
  `//tests/install_smoke:smoke_test` too when install code changes).
- All documentation (`README.md`, `DESIGN.md`, `CLAUDE.md`) must be updated
  to reflect any code changes before committing: new rules, changed
  attributes, new public API surface, behaviour changes.

## Repo layout

```
rules_alertmanager/
├── MODULE.bazel              # module; toolchain registration; dev deps (helm, itest, kind)
├── defs.bzl                  # public API re-exports
├── extensions.bzl            # `alertmanager.version()` → alertmanager_<ver>_<plat> repos (is_root-guarded)
├── private/
│   ├── versions.bzl          # ALERTMANAGER_VERSIONS: url / sha256 / strip_prefix per platform
│   ├── repositories.bzl      # per-platform repo: release tarball → alertmanager + amtool
│   ├── providers.bzl         # AlertmanagerBinaryInfo, AlertmanagerConfigInfo
│   ├── config.bzl            # alertmanager_config (+ validation action), alertmanager_routes_test
│   ├── check_config.sh       # placeholder resolution + `amtool check-config`
│   ├── routes_test.sh.tmpl   # `amtool config routes test --verify.receivers` per case
│   ├── server.bzl            # alertmanager_server, alertmanager_health_check, AlertmanagerServerInfo
│   ├── server.sh.tmpl        # runfiles resolution → launcher.py
│   ├── launcher.py           # stage + expand config, port, /-/ready, env file, SIGTERM
│   ├── test.bzl              # alertmanager_test macro
│   ├── alertmanager_test_trampoline.sh  # sink → server → env → test
│   ├── webhook_sink.py       # records each notification as <n>.json
│   ├── testlib.sh            # am_post_alert, am_wait_notifications, am_notifications
│   ├── default_config.yml    # server default: one silent receiver
│   ├── default_test_config.yml  # test default: everything to the sink, group_wait 0s
│   ├── install.bzl           # alertmanager_install(+config), alertmanager_install_health_check
│   ├── install_config.awk    # replaces the chart ConfigMap's data with a config + templates
│   └── manifests/alertmanager.yaml  # rendered chart (committed; do not hand-edit)
├── toolchain/                # toolchain_type, per-platform toolchains, :current
├── config/alertmanager-values.yaml  # chart render values (fullnameOverride)
├── tools/                    # chart pin + render flow, update_checksums.sh
└── tests/
    ├── BUILD.bazel
    ├── analysis_tests.bzl    # install macros + server provider (analysis only)
    ├── testdata/             # test config (continue, inhibit, template, SLACK_URL), bad configs
    ├── api_test.sh           # alertmanager_test: routing, inhibition, silences, resolved
    ├── default_config_test.sh  # default sink config; args forwarded
    ├── no_sink_test.sh       # webhook_sink = False
    ├── server_test.sh        # env file, readiness, extra_args, SIGTERM, unset placeholder
    ├── health_check_test.sh
    ├── routes_failure_test.sh  # wrong expectation fails with the routing tree
    ├── invalid_config_test.sh  # check_config.sh: good / bad receiver / unresolved placeholder
    ├── install_config_test.sh  # configured manifest: only the ConfigMap changes
    ├── checksums_test.sh     # 64-hex SHA-256 for every pinned URL
    └── install_smoke/        # kind + alertmanager_install(config) + amtool in the pod
```

## Key concepts

- **One config, three uses.** An `alertmanager_config` is checked at build
  time (validation action), route-tested, run by `alertmanager_server` /
  `alertmanager_test`, and installed by `alertmanager_install(config = ...)`.
- **Templates beside the config.** They are staged under their basenames
  next to `alertmanager.yml`, so `templates: ["*.tmpl"]` resolves the same
  way locally and in the chart (which mounts its ConfigMap at
  /etc/alertmanager).
- **`${NAME}` placeholders.** The hermetic server expands them from its
  environment (unset is an error naming them). Build-time uses (check,
  routes tests, install) use the target's `placeholders`, where
  `ALERTMANAGER_WEBHOOK_URL` has a default.
- **Hermetic server.** It runs on a free 127.0.0.1 port with
  `--cluster.listen-address=` (no gossip) and its own storage. The env file
  (`ALERTMANAGER_URL`, `_HOST`, `_PORT`, `AMTOOL`) is written only after
  `/-/ready` returns 200, within `ready_timeout` (default 30 s). The SIGTERM
  handler only terminates and arms a kill timer; it must not `wait()`,
  because the main thread holds Popen's wait lock.
- **alertmanager_test.** The trampoline starts the sink first (the server
  expands its URL), then the server, then runs (not execs) the test so its
  trap can stop both. A `-` argument means "no sink", since Bazel drops
  empty-string args.
- **Install.** The rendered manifest is pinned to namespace `alertmanager`
  and the object names to `alertmanager`. Its health check waits for
  `sts/alertmanager`. With `config`, `install_config.awk` swaps only the
  ConfigMap's `data:`.

## Public API

```python
load("@rules_alertmanager//:defs.bzl",
    "alertmanager_config",          # src, templates, placeholders
    "alertmanager_routes_test",     # config, routes = {"k=v k2=v2": "recv" | ["r1", "r2"]}
    "alertmanager_server",          # config, ready_timeout, extra_args
    "alertmanager_health_check",    # server
    "alertmanager_test",            # srcs, config, webhook_sink, ready_timeout, extra_args, args, env, ...
    "alertmanager_install",         # namespace, config, wait_timeout
    "alertmanager_install_health_check",
    "AlertmanagerBinaryInfo", "AlertmanagerConfigInfo", "AlertmanagerServerInfo",
)
```

## Development

```sh
bazel test //tests/...                                  # no container runtime
# kind smoke (rootless podman needs a delegated scope):
systemd-run --scope --user --property=Delegate=yes -- \
    bazel test //tests/install_smoke:smoke_test --test_output=streamed
tools/update_checksums.sh 0.34.2      # re-pin binaries; --check to verify
tools/render_alertmanager.sh 2.1.4    # re-render the chart manifest
```

### Test results (last full run: 2026-11-03)

All 15 test targets pass on Linux x86_64 (Alertmanager 0.34.2): 14 in
`//tests/...`, and the kind smoke on rootless podman. The 32-run parallel
stress of the server tests is clean.

| Test target | What it verifies | Result |
|---|---|---|
| `//tests:routes_test` | 5 routing cases incl. `continue` (two receivers) | PASSED |
| `//tests:routes_failure_test` | wrong expectation fails, naming actual receivers + tree | PASSED |
| `//tests:invalid_config_test` | check accepts good config, rejects undefined receiver and unresolved placeholder | PASSED |
| `//tests:api_test` | routing + continue, inhibition, silence, resolved notification via sink; env placeholders expanded | PASSED |
| `//tests:default_config_test` | default config delivers each alert to the sink; args forwarded | PASSED |
| `//tests:no_sink_test` | no sink variables; default receiver; clustering disabled | PASSED |
| `//tests:server_test` | env file keys, /-/ready, extra_args, SIGTERM exit 0 + env removed, unset placeholder named | PASSED |
| `//tests:health_check_test` | exits non-zero without env file, 0 with | PASSED |
| `//tests:install_config_test` | configured manifest: one ConfigMap with config + template, rest unchanged | PASSED |
| `//tests:analysis_tests` (4) | install (with/without config), health check executables; server provider | PASSED |
| `//tests:checksums_test` | every pinned URL has a 64-hex SHA-256 | PASSED |
| `//tests/install_smoke:smoke_test` | kind: our config running, template mounted, alert routed in-cluster | PASSED |

An invalid `alertmanager_config` fails `bazel build`; this was checked by
hand with `bad_receiver.yml`.

## Known limitations

- `python3` is required on the host for the server, test trampoline and sink.
- One Alertmanager per test, no HA; the chart renders one replica.
- `alertmanager_test` wraps `sh_test`; other languages use
  `alertmanager_server` through rules_itest.
- The install namespace is fixed to `alertmanager` by the rendered manifest.
