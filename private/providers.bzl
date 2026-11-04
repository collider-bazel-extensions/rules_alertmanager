"""Providers exposed by rules_alertmanager."""

AlertmanagerBinaryInfo = provider(
    doc = "Alertmanager toolchain binaries (one upstream tarball).",
    fields = {
        "version":          "string — pinned Alertmanager version",
        "alertmanager_bin": "File — the alertmanager server executable",
        "amtool_bin":       "File — the amtool CLI executable",
    },
)

AlertmanagerConfigInfo = provider(
    doc = "A validated Alertmanager configuration (alertmanager_config).",
    fields = {
        "config":           "File — the staged alertmanager.yml, ${VAR} placeholders intact",
        "templates":        "list of File — notification templates staged beside `config`",
        "files":            "depset of File — `config` + `templates` (one directory)",
        "resolved_config":  "File — copy with placeholders replaced by their build-time " +
                            "`placeholders` values; what amtool checked",
        "placeholders":     "dict string→string — build-time value for each ${VAR}",
    },
)
