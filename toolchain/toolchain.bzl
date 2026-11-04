"""alertmanager_toolchain — exposes the platform-resolved alertmanager +
amtool binaries as a `ToolchainInfo`, so rules resolve them via
`ctx.toolchains["@rules_alertmanager//toolchain:alertmanager"]`.

`current_alertmanager_toolchain` forwards the resolved binaries as a
plain target (files + runfiles) for `data = [...]` use in tests.
"""

load("//private:providers.bzl", "AlertmanagerBinaryInfo")

ALERTMANAGER_TOOLCHAIN_TYPE = Label("//toolchain:alertmanager")

def _toolchain_impl(ctx):
    info = AlertmanagerBinaryInfo(
        version          = ctx.attr.version,
        alertmanager_bin = ctx.file.alertmanager_bin,
        amtool_bin       = ctx.file.amtool_bin,
    )
    files = [ctx.file.alertmanager_bin, ctx.file.amtool_bin]
    return [
        platform_common.ToolchainInfo(alertmanager = info),
        DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files)),
    ]

alertmanager_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "version":          attr.string(mandatory = True),
        "alertmanager_bin": attr.label(allow_single_file = True, mandatory = True),
        "amtool_bin":       attr.label(allow_single_file = True, mandatory = True),
    },
)

def _current_impl(ctx):
    info = ctx.toolchains[ALERTMANAGER_TOOLCHAIN_TYPE].alertmanager
    files = [info.alertmanager_bin, info.amtool_bin]
    return [
        info,
        DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files)),
    ]

current_alertmanager_toolchain = rule(
    implementation = _current_impl,
    toolchains = [ALERTMANAGER_TOOLCHAIN_TYPE],
    doc = "The resolved alertmanager + amtool, as files and runfiles.",
)
