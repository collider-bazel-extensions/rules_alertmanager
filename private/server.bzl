"""alertmanager_server + alertmanager_health_check — hermetic Alertmanager
test fixtures.

`alertmanager_server` is a long-running executable (see launcher.py) that
starts one isolated alertmanager (no clustering) on a free 127.0.0.1
port, waits for GET /-/ready, then writes `$TEST_TMPDIR/<name>.env`:

    ALERTMANAGER_URL=http://127.0.0.1:<port>
    ALERTMANAGER_HOST=127.0.0.1
    ALERTMANAGER_PORT=<port>
    AMTOOL=/abs/path/to/amtool

and runs until SIGTERM. `alertmanager_health_check` exits 0 iff that
file exists; it drops into `itest_service.health_check`.
"""

load(":providers.bzl", "AlertmanagerConfigInfo")

_TOOLCHAIN = "//toolchain:alertmanager"

AlertmanagerServerInfo = provider(
    doc = "An alertmanager_server target.",
    fields = {
        "binary": "AlertmanagerBinaryInfo: the toolchain's binaries.",
        "config": "AlertmanagerConfigInfo: the config it runs.",
    },
)

def _shell_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def _check_timeout(label, value):
    raw = value.strip()
    digits = raw.replace(".", "", 1)
    if not raw or not digits.isdigit() or not digits.replace("0", ""):
        fail("{}: ready_timeout = {}: expected a positive number of seconds.".format(
            label, repr(value)))
    return raw

def _alertmanager_server_impl(ctx):
    am = ctx.toolchains[_TOOLCHAIN].alertmanager
    cfg = ctx.attr.config[AlertmanagerConfigInfo]

    wrapper = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = wrapper,
        substitutions = {
            "__NAME__":          ctx.label.name,
            "__CONFIG__":        cfg.config.short_path,
            "__LAUNCHER__":      ctx.file._launcher.short_path,
            "__ALERTMANAGER__":  am.alertmanager_bin.short_path,
            "__AMTOOL__":        am.amtool_bin.short_path,
            "__READY_TIMEOUT__": _check_timeout(ctx.label, ctx.attr.ready_timeout),
            "__EXTRA_ARGS__":    " ".join([_shell_quote(a) for a in ctx.attr.extra_args]),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [wrapper, ctx.file._launcher, am.alertmanager_bin, am.amtool_bin],
        transitive_files = cfg.files,
    )
    return [
        DefaultInfo(executable = wrapper, runfiles = runfiles),
        AlertmanagerServerInfo(binary = am, config = cfg),
    ]

alertmanager_server = rule(
    implementation = _alertmanager_server_impl,
    executable = True,
    doc = """\
Long-running Alertmanager for tests and rules_itest compositions. Writes
`$TEST_TMPDIR/<name>.env` (ALERTMANAGER_URL, ALERTMANAGER_HOST,
ALERTMANAGER_PORT, AMTOOL) once /-/ready answers.

`${NAME}` placeholders in the config are expanded from the server's
environment at start; an unset one fails the start, naming it.
""",
    attrs = {
        "config": attr.label(
            default = "//private:default_config",
            providers = [AlertmanagerConfigInfo],
            doc = "An alertmanager_config target. Default: one `default` " +
                  "receiver with no notifiers.",
        ),
        "ready_timeout": attr.string(
            default = "30",
            doc = "Seconds to wait for /-/ready. A positive number.",
        ),
        "extra_args": attr.string_list(
            doc = "Extra alertmanager flags, e.g. " +
                  "[\"--data.retention=1h\", \"--log.level=debug\"].",
        ),
        "_launcher": attr.label(
            default = "//private:launcher.py",
            allow_single_file = True,
        ),
        "_tmpl": attr.label(
            default = "//private:server.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = [_TOOLCHAIN],
)

# ---- alertmanager_health_check -------------------------------------------------

def _alertmanager_health_check_impl(ctx):
    wrapper = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = wrapper,
        substitutions = {"__ENV_FILE_NAME__": ctx.attr.server.label.name + ".env"},
        is_executable = True,
    )
    return [DefaultInfo(executable = wrapper)]

alertmanager_health_check = rule(
    implementation = _alertmanager_health_check_impl,
    executable = True,
    attrs = {
        "server": attr.label(
            mandatory = True,
            providers = [AlertmanagerServerInfo],
            doc = "The alertmanager_server this check pairs with.",
        ),
        "_tmpl": attr.label(
            default = "//private:health_check.sh.tmpl",
            allow_single_file = True,
        ),
    },
)

