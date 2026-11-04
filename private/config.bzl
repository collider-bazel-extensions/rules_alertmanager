"""alertmanager_config + alertmanager_routes_test.

`alertmanager_config` stages `alertmanager.yml` and its notification
templates into one directory (templates beside the config, so a
`templates: ["*.tmpl"]` glob resolves the same way locally and in a
cluster, where the chart mounts them beside the config too) and runs
`amtool check-config` as a validation action: a broken config fails
`bazel build`, not just `bazel test`.

Configs may contain `${NAME}` placeholders. alertmanager_server expands
them from its environment at start (that is how alertmanager_test points
a receiver at its webhook sink); the build-time check, routes tests and
alertmanager_install use the values in `placeholders`.
"""

load(":providers.bzl", "AlertmanagerConfigInfo")

_TOOLCHAIN = "//toolchain:alertmanager"

# Placeholders every config may use without declaring them.
DEFAULT_PLACEHOLDERS = {
    "ALERTMANAGER_WEBHOOK_URL": "http://127.0.0.1:9/",
}

def _alertmanager_config_impl(ctx):
    am = ctx.toolchains[_TOOLCHAIN].alertmanager

    config = ctx.actions.declare_file(ctx.label.name + "/alertmanager.yml")
    ctx.actions.symlink(output = config, target_file = ctx.file.src)

    templates = []
    seen = {}
    for t in ctx.files.templates:
        if t.basename == "alertmanager.yml" or t.basename in seen:
            fail("{}: template basenames must be unique and not alertmanager.yml: {}".format(
                ctx.label, t.basename))
        seen[t.basename] = True
        out = ctx.actions.declare_file(ctx.label.name + "/" + t.basename)
        ctx.actions.symlink(output = out, target_file = t)
        templates.append(out)

    placeholders = dict(DEFAULT_PLACEHOLDERS)
    placeholders.update(ctx.attr.placeholders)

    resolved = ctx.actions.declare_file(ctx.label.name + ".resolved.yml")
    args = ctx.actions.args()
    args.add(am.amtool_bin)
    args.add(config)
    args.add(resolved)
    args.add_all(["{}={}".format(k, v) for k, v in sorted(placeholders.items())])
    ctx.actions.run(
        executable = ctx.executable._check,
        arguments = [args],
        inputs = [config, am.amtool_bin] + templates,
        outputs = [resolved],
        mnemonic = "AlertmanagerCheckConfig",
        progress_message = "amtool check-config %{label}",
    )

    files = depset([config] + templates)
    return [
        DefaultInfo(files = files),
        AlertmanagerConfigInfo(
            config = config,
            templates = templates,
            files = files,
            resolved_config = resolved,
            placeholders = placeholders,
        ),
        OutputGroupInfo(_validation = depset([resolved])),
    ]

alertmanager_config = rule(
    implementation = _alertmanager_config_impl,
    doc = """\
An Alertmanager configuration, validated with `amtool check-config` at
build time.

Example:

    alertmanager_config(
        name = "am_config",
        src = "alertmanager.yml",
        templates = glob(["templates/*.tmpl"]),  # reference as "*.tmpl"
        placeholders = {"SLACK_URL": "https://hooks.slack.invalid/x"},
    )
""",
    attrs = {
        "src": attr.label(
            mandatory = True,
            allow_single_file = [".yml", ".yaml"],
            doc = "alertmanager.yml.",
        ),
        "templates": attr.label_list(
            allow_files = True,
            doc = "Notification template files, staged beside the config " +
                  "under their basenames (reference them as e.g. " +
                  "`templates: [\"*.tmpl\"]`).",
        ),
        "placeholders": attr.string_dict(
            doc = "Build-time value for each `${NAME}` in the config, used " +
                  "for the check, routes tests and alertmanager_install. " +
                  "ALERTMANAGER_WEBHOOK_URL has a default. A placeholder " +
                  "with no value fails the build.",
        ),
        "_check": attr.label(
            default = "//private:check_config",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [_TOOLCHAIN],
)

# ---- alertmanager_routes_test -------------------------------------------------

def _routes_test_impl(ctx):
    am = ctx.toolchains[_TOOLCHAIN].alertmanager
    info = ctx.attr.config[AlertmanagerConfigInfo]

    lines = []
    for labels, receivers in ctx.attr.cases.items():
        lines.append("{}\t{}".format(receivers, labels))
    cases = ctx.actions.declare_file(ctx.label.name + ".cases")
    ctx.actions.write(cases, "\n".join(lines) + "\n")

    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = script,
        substitutions = {
            "__AMTOOL__": am.amtool_bin.short_path,
            "__CONFIG__": info.resolved_config.short_path,
            "__CASES__":  cases.short_path,
        },
        is_executable = True,
    )
    return [DefaultInfo(
        executable = script,
        runfiles = ctx.runfiles(files = [am.amtool_bin, info.resolved_config, cases]),
    )]

_alertmanager_routes_test = rule(
    implementation = _routes_test_impl,
    test = True,
    attrs = {
        "config": attr.label(mandatory = True, providers = [AlertmanagerConfigInfo]),
        "cases": attr.string_dict(mandatory = True),
        "_tmpl": attr.label(
            default = "//private:routes_test.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = [_TOOLCHAIN],
)

def alertmanager_routes_test(name, config, routes, **kwargs):
    """Asserts where alerts route: `amtool config routes test` per case.

    Args:
      name: target name.
      config: an alertmanager_config target.
      routes: dict of label set → expected receivers. The key is
        space-separated `name=value` labels; the value is a receiver name
        or a list of them, in routing-tree order (several when routes
        `continue`). Every case runs; all mismatches are reported.
      **kwargs: forwarded to the test rule (size, tags, ...).

    Example:

        alertmanager_routes_test(
            name = "routes_test",
            config = ":am_config",
            routes = {
                "team=db severity=page": "db-pager",
                "team=web": ["web-slack", "audit"],
                "alertname=Unknown": "default",
            },
        )
    """
    cases = {}
    for labels, receivers in routes.items():
        if type(receivers) == type(""):
            receivers = [receivers]
        cases[labels] = ",".join(receivers)
    kwargs.setdefault("size", "small")
    _alertmanager_routes_test(
        name = name,
        config = config,
        cases = cases,
        **kwargs
    )
