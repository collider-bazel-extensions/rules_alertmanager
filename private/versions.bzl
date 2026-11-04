"""Alertmanager binary pins.

One upstream tarball per platform carries both `alertmanager` and
`amtool`:

    https://github.com/prometheus/alertmanager/releases/download/v<ver>/alertmanager-<ver>.<os>-<arch>.tar.gz
    (extracts to `alertmanager-<ver>.<os>-<arch>/{alertmanager,amtool}`)

SHA-256s are the release's published `sha256sums.txt`. Maintainer flow:

    tools/update_checksums.sh <ver>     # add / re-pin <ver> from sha256sums.txt
    tools/update_checksums.sh --check   # verify every pin, no writes

//tests:checksums_test fails on an empty or malformed value.
"""

ALERTMANAGER_VERSIONS = {
    "0.34.2": {
        "linux_amd64": {
            "url": "https://github.com/prometheus/alertmanager/releases/download/v0.34.2/alertmanager-0.34.2.linux-amd64.tar.gz",
            "sha256": "17ee14acd0f6ba6e25a436ff223d9c17ddd5cf484f543ad12f0932eaa89ba186",
            "strip_prefix": "alertmanager-0.34.2.linux-amd64",
        },
        "linux_arm64": {
            "url": "https://github.com/prometheus/alertmanager/releases/download/v0.34.2/alertmanager-0.34.2.linux-arm64.tar.gz",
            "sha256": "5aaad82e3d167c30c06ce7d38677d2892a6f66f4c3613ea17af7481750fdd0b0",
            "strip_prefix": "alertmanager-0.34.2.linux-arm64",
        },
        "darwin_amd64": {
            "url": "https://github.com/prometheus/alertmanager/releases/download/v0.34.2/alertmanager-0.34.2.darwin-amd64.tar.gz",
            "sha256": "fa5a50303c58771c261fcbed4cf5f9a852cf2c6064942adbd92c6859c65c5f93",
            "strip_prefix": "alertmanager-0.34.2.darwin-amd64",
        },
        "darwin_arm64": {
            "url": "https://github.com/prometheus/alertmanager/releases/download/v0.34.2/alertmanager-0.34.2.darwin-arm64.tar.gz",
            "sha256": "dc1fcd4ad3e8bef111683eaf385aa5b2b02493277bca9126c129e0a39fc68a4f",
            "strip_prefix": "alertmanager-0.34.2.darwin-arm64",
        },
    },
}

PLATFORMS = {
    "linux_amd64":  ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "linux_arm64":  ["@platforms//os:linux", "@platforms//cpu:arm64"],
    "darwin_amd64": ["@platforms//os:osx",   "@platforms//cpu:x86_64"],
    "darwin_arm64": ["@platforms//os:osx",   "@platforms//cpu:arm64"],
}
