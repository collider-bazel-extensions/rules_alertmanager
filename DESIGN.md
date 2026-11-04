# rules_alertmanager — design notes

## Three families in one repo

Alertmanager users test three different things:

- **The config.** Does it parse? Do alerts route where we think they do? This needs only `amtool`: no server, no cluster.
- **Their code against a live Alertmanager.** Does the service fire the right alerts, do silences work, does a notification arrive? This needs a per-test server, as rules_nats, rules_pg and rules_spicedb provide.
- **A cluster install.** This is the rules_nats / rules_loki pattern: a pinned chart, rendered at maintainer time and applied with rules_kubectl.

Keeping all three in one repo means one toolchain and one config rule (`alertmanager_config`) feed all of them. The config a team validates and route-tests is the same file that runs in its tests and that gets installed.

## Toolchain

The upstream release tarball ships `alertmanager` and `amtool` together, so there is one repo per platform and no separate CLI pin (rules_nats has to pair two releases). Checksums are the release's `sha256sums.txt`. `tools/update_checksums.sh` re-derives them and cross-checks each against a download. `//tests:checksums_test` fails on any empty or malformed pin.

The extension is `mod.is_root`-guarded, which avoids `@alertmanager_<ver>_<plat>` collisions when the module is consumed transitively.

## Config validation as a validation action

`alertmanager_config` returns the checked, resolved config in `OutputGroupInfo(_validation = ...)`. Bazel runs validation actions for every build of a target that depends on the config. So `bazel build //...` catches a typo'd receiver without anyone running a test, and the check isn't a separate `*_test` target that has to be remembered.

The check copies the staged directory to a scratch dir before resolving
placeholders. Generated inputs (a config from a genrule) are read-only in
the output tree, so the copies are made writable first; v0.1.0 failed with
"Permission denied" on a generated config (`//tests:generated_config_test`).

Templates resolve relative to the config file. `alertmanager_config` therefore stages them beside `alertmanager.yml` under their basenames. The chart mounts its ConfigMap keys at `/etc/alertmanager`, also beside the config. So `templates: ["*.tmpl"]` works unchanged in the check, in the hermetic server and in the cluster.

## `${NAME}` placeholders

Real configs carry environment-specific URLs: webhooks, Slack hooks, PagerDuty endpoints. In tests, a receiver must point at a port chosen at run time. Alertmanager doesn't expand environment variables itself, so:

- **Hermetic server:** the launcher expands `${NAME}` from its environment when it starts. This is how `alertmanager_test` points receivers at its webhook sink (`ALERTMANAGER_WEBHOOK_URL`). Consumers pass others through `env`. An unset name is an error that names it; it is never left as literal text.
- **Build time** (the check, routes tests, `alertmanager_install`): values come from `placeholders`. A placeholder without a value fails the build. `amtool` validates URL fields, so a silently left `${X}` would only fail later, with a less clear message.

Only `${NAME}` (letters, digits and `_`) is a placeholder. Alertmanager's own templating uses `{{ }}`, so the two can't collide.

## Hermetic server: `launcher.py`

The launcher is written in Python rather than shell (rules_nats uses a shell template) because it has more to do: config staging and expansion, readiness over HTTP, retrying on a port clash, and signal handling.

- **Port:** a free port from bind-then-close, as in rules_nats and rules_pg. On "address already in use" the launcher retries with a new port, up to 5 times.
- **Clustering off:** `--cluster.listen-address=` stops each test's instance from gossiping with others on the host, and avoids the cluster settle delay.
- **Readiness:** the launcher polls `GET /-/ready` until it answers 200, or `ready_timeout` passes (default 30 s). The timeout is configurable from the start, a lesson from rules_temporal #10.
- **Env file:** written atomically (tmp + rename) only after the server is ready, so `alertmanager_health_check` is simply "the file exists".
- **Shutdown:** the SIGTERM handler only calls `terminate()` and arms a 10 s kill timer. The main thread is blocked in `proc.wait()`, which holds Popen's wait lock, so a `wait()` inside the handler would stall for its full timeout. That was the first version of this code: every test took 10 s to shut down.

## `alertmanager_test`

The macro creates an `alertmanager_server`, an inner `sh_binary` and an `sh_test` whose source is a static trampoline (the rules_nats pattern). The trampoline:

1. Starts `webhook_sink.py` (unless `webhook_sink = False`) and exports `ALERTMANAGER_WEBHOOK_URL` / `_DIR`. It starts before the server, so the server can expand the URL into the config.
2. Starts the server, waits for the env file and sources it.
3. Runs the test with the target's `args`. The trampoline doesn't `exec` the test, so its trap can stop the server and sink when the test ends. Its first five positional arguments are removed before the test sees `"$@"`. (rules_nats's trampoline passes its own arguments through to the test.)

The sink writes each POST body as `<n>.json` via tmp + rename, so `am_wait_notifications` never reads a partial payload. The default test config uses `group_by: ["..."]` and `group_wait: 0s`, so each distinct alert is notified at once.

Empty-string `args` are dropped by Bazel. The trampoline therefore takes `-` (not `""`) to mean "no sink", so its positions stay fixed.

## Cluster install

- **Chart and values:** the chart is the prometheus-community `alertmanager` chart, downloaded as its release `.tgz` and rendered at maintainer time by rules_helm. `fullnameOverride: alertmanager` fixes the object names whatever the release name. The rollout wait (`sts/alertmanager`) and the config overlay rely on that.
- **Custom config:** `alertmanager_install(config = ...)` doesn't re-render the chart. An awk pass (`private/install_config.awk`) replaces the data of the single ConfigMap named `alertmanager` in the committed manifest with the resolved config and templates as YAML literal blocks. Every other document passes through byte-for-byte, which `//tests:install_config_test` checks. Doing it at build time means the pod starts with the right config: there is no window running the chart default, and no reliance on the reload sidecar.
- **Drift check:** CI re-renders the chart and fails if the committed manifest differs.

## What this repo does not (yet) do

- **Prometheus rule testing.** `promtool test rules` belongs with Prometheus, not Alertmanager.
- **Alertmanager HA.** The chart renders one replica, and the hermetic server disables clustering. Multi-replica gossip isn't parameterized.
- **Non-shell `alertmanager_test`.** The macro wraps `sh_test`. Go and Python tests can use `alertmanager_server` + `alertmanager_health_check` through rules_itest, or read `ALERTMANAGER_URL` from a wrapper.
- **Namespaces other than `alertmanager` for the install.** The rendered manifest pins it, as rules_nats and rules_loki do.
