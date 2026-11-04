"""Per-platform Alertmanager repo: downloads the release tarball at the
pinned sha and exposes `alertmanager` + `amtool` as filegroups.
"""

load(":versions.bzl", "ALERTMANAGER_VERSIONS")

_BUILD_TMPL = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "alertmanager_bin",
    srcs = ["alertmanager"],
)

filegroup(
    name = "amtool_bin",
    srcs = ["amtool"],
)

filegroup(
    name = "all_bins",
    srcs = [
        ":alertmanager_bin",
        ":amtool_bin",
    ],
)
"""

def _impl(rctx):
    version = rctx.attr.version
    platform = rctx.attr.platform

    if version not in ALERTMANAGER_VERSIONS:
        fail("rules_alertmanager: unknown Alertmanager version '{}'. Known: {}".format(
            version, sorted(ALERTMANAGER_VERSIONS.keys()),
        ))
    pin = ALERTMANAGER_VERSIONS[version].get(platform)
    if not pin:
        fail("rules_alertmanager: platform '{}' missing for version {}".format(platform, version))

    rctx.download_and_extract(
        url = pin["url"],
        sha256 = pin["sha256"],
        stripPrefix = pin["strip_prefix"],
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD_TMPL)

alertmanager_binary_repo = repository_rule(
    implementation = _impl,
    attrs = {
        "version":  attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
    },
)
