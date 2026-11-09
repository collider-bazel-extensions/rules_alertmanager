"""Bzlmod extension. Single `version` tag — fetches the upstream
alertmanager release tarball (alertmanager + amtool) for each supported
platform.
"""

load("//private:repositories.bzl", "alertmanager_binary_repo")
load("//private:versions.bzl", "ALERTMANAGER_VERSIONS", "PLATFORMS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),  # e.g. "0.34.2"
})

def _impl(mctx):
    # Every module's `version` tags, deduplicated. The repos are named by
    # version (`alertmanager_<ver>_<plat>`), so tags from different modules
    # can't collide; the only clash was this extension creating a repo
    # twice. rules_alertmanager's own MODULE.bazel imports
    # alertmanager_0_34_2_* and registers the toolchain for every consumer,
    # so its own tag must always count: through v0.1.2 only the root's tags
    # did, and a root without alertmanager.version() failed to resolve. A
    # consumer's extra version adds repos it can use_repo; the registered
    # toolchain stays rules_alertmanager's.
    versions = {}
    for mod in mctx.modules:
        for tag in mod.tags.version:
            versions[tag.version] = None
    for version in sorted(versions.keys()):
        if version not in ALERTMANAGER_VERSIONS:
            fail("rules_alertmanager: alertmanager.version(version = \"{}\") is not supported. Supported: {}".format(
                version,
                ", ".join(sorted(ALERTMANAGER_VERSIONS.keys())),
            ))
        for plat in PLATFORMS.keys():
            alertmanager_binary_repo(
                name = "alertmanager_{}_{}".format(
                    version.replace(".", "_"),
                    plat,
                ),
                version = version,
                platform = plat,
            )

alertmanager = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
