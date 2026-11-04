"""Bzlmod extension. Single `version` tag — fetches the upstream
alertmanager release tarball (alertmanager + amtool) for each supported
platform.
"""

load("//private:repositories.bzl", "alertmanager_binary_repo")
load("//private:versions.bzl", "PLATFORMS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),  # e.g. "0.34.2"
})

def _impl(mctx):
    # Only honor `version` tags from the root module — same is_root guard
    # as rules_nats / rules_kind. Without it, rules_alertmanager's own
    # MODULE.bazel and the consumer would each emit
    # `@alertmanager_<ver>_<plat>` repos and Bazel would collide them.
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            for plat in PLATFORMS.keys():
                alertmanager_binary_repo(
                    name = "alertmanager_{}_{}".format(
                        tag.version.replace(".", "_"),
                        plat,
                    ),
                    version = tag.version,
                    platform = plat,
                )

alertmanager = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
