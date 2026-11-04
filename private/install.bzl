"""alertmanager_install + alertmanager_install_health_check — cluster
primitives wrapping rules_kubectl's `kubectl_apply` over the pinned,
pre-rendered prometheus-community `alertmanager` Helm chart.

Wait shape: StatefulSet `<namespace>/alertmanager` rolled out (the chart
is rendered with release name `alertmanager`).

With `config = ":my_config"` (an alertmanager_config), the chart's
`alertmanager` ConfigMap is replaced at build time by your config — its
placeholders resolved with the target's build-time `placeholders` values
— plus its templates, keyed by basename and mounted beside the config
(/etc/alertmanager), so a `templates: ["*.tmpl"]` glob works unchanged.
"""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")
load(":providers.bzl", "AlertmanagerConfigInfo")

_STS = "sts/alertmanager"
_MANIFEST = Label("//private/manifests:alertmanager.yaml")

def _configured_manifest_impl(ctx):
    cfg = ctx.attr.config[AlertmanagerConfigInfo]
    out = ctx.actions.declare_file(ctx.label.name + ".yaml")
    data = [cfg.resolved_config] + cfg.templates
    ctx.actions.run_shell(
        inputs = data + [ctx.file.manifest, ctx.file._awk],
        outputs = [out],
        command = 'awk -v cm_name=alertmanager -v ndata="$1" -f "$2" "${@:4}" "$3" > "$OUT"',
        arguments = [str(len(data)), ctx.file._awk.path, ctx.file.manifest.path] + [f.path for f in data],
        env = {"OUT": out.path},
        mnemonic = "AlertmanagerInstallConfig",
        progress_message = "Applying %{label}'s config to the Alertmanager chart manifest",
    )
    return [DefaultInfo(files = depset([out]))]

alertmanager_configured_manifest = rule(
    implementation = _configured_manifest_impl,
    doc = "The pinned chart manifest with its ConfigMap replaced by `config`.",
    attrs = {
        "config": attr.label(mandatory = True, providers = [AlertmanagerConfigInfo]),
        "manifest": attr.label(default = _MANIFEST, allow_single_file = True),
        "_awk": attr.label(default = "//private:install_config.awk", allow_single_file = True),
    },
)

def alertmanager_install(
        name,
        namespace = "alertmanager",
        config = None,
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned Alertmanager chart into `namespace` and block until
    `sts/alertmanager` has rolled out.

    Drops into `itest_service.exe`.

    Args:
      name: target name.
      namespace: namespace to install into (created if missing).
      config: optional alertmanager_config to run instead of the chart's
        default config.
      wait_timeout: rollout wait. The image is ~30 MB; cold pulls clear
        well inside 300s.
      **kwargs: forwarded to kubectl_apply (tags, visibility,
        wait_for_rollouts, ...).
    """
    manifest = _MANIFEST
    if config:
        manifest = ":" + name + "_manifest"
        alertmanager_configured_manifest(
            name = name + "_manifest",
            config = config,
            tags = kwargs.get("tags"),
            visibility = ["//visibility:private"],
        )
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    kubectl_apply(
        name = name,
        manifests = [manifest],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_rollouts = [_STS] + list(extra_rollouts),
        wait_timeout = wait_timeout,
        **kwargs
    )

def alertmanager_install_health_check(
        name,
        namespace = "alertmanager",
        **kwargs):
    """Readiness probe paired with `alertmanager_install`: same wait shape
    with `--timeout=0s`. Drops into `itest_service.health_check`."""
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_rollouts = [_STS] + list(extra_rollouts),
        **kwargs
    )
