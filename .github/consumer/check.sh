#!/usr/bin/env bash
# Consumer checks against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do):
#   1. no alertmanager.version() in the root resolves, and an
#      alertmanager_routes_test runs amtool at rules_alertmanager's version
#   2. the same version set twice in the root resolves
#   3. an unsupported version fails, naming alertmanager.version
#   4. @rules_alertmanager//... loads (tests/ and tools/ are not shipped)
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_alertmanager"
rm -rf "$work"; mkdir -p "$src"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in tests tools; do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
pinned="$(sed -n 's/^alertmanager.version(version = "\(.*\)")$/\1/p' "$src/MODULE.bazel")"
kubectl_commit="$(grep -A3 'module_name = "rules_kubectl"' "$src/MODULE.bazel" | sed -n 's/.*commit = "\([0-9a-f]*\)".*/\1/p')"

consumer() { # <name> <extra MODULE.bazel lines>
    local c="$work/$1"
    mkdir -p "$c"
    if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
    cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_alertmanager")
local_path_override(module_name = "rules_alertmanager", path = "$src")
bazel_dep(name = "rules_kubectl", version = "0.2.0")
git_override(
    module_name = "rules_kubectl",
    remote = "https://github.com/collider-bazel-extensions/rules_kubectl",
    commit = "$kubectl_commit",
)
$2
MOD
    cat > "$c/alertmanager.yml" <<'YML'
route:
  receiver: default
  routes:
    - matchers: ['severity="page"']
      receiver: pager
receivers:
  - name: default
    webhook_configs:
      - url: "http://127.0.0.1:1/default"
  - name: pager
    webhook_configs:
      - url: "http://127.0.0.1:1/pager"
YML
    cat > "$c/BUILD.bazel" <<'BUILD'
load("@rules_alertmanager//:defs.bzl", "alertmanager_config", "alertmanager_routes_test")

alertmanager_config(
    name = "config",
    src = "alertmanager.yml",
)

alertmanager_routes_test(
    name = "routes_test",
    config = ":config",
    routes = {
        "severity=page": "pager",
        "team=web": "default",
    },
)
BUILD
    echo "$c"
}

# 1. No alertmanager.version(): resolves; the registered toolchain's amtool runs.
c="$(consumer untagged "")"
(cd "$c" && bazel mod deps >/dev/null)
(cd "$c" && bazel test //:routes_test --test_output=errors)
"$(cd "$c" && bazel info output_base)/external/rules_alertmanager++alertmanager+alertmanager_${pinned//./_}_linux_amd64/amtool" --version 2>&1 | tee "$work/untagged.out"
grep -q "version $pinned " "$work/untagged.out" || { echo "FAIL: untagged consumer did not get alertmanager $pinned" >&2; exit 1; }
echo "PASS: untagged root resolves, alertmanager $pinned"

# 2. The same version twice in the root.
c="$(consumer twice "alertmanager = use_extension(\"@rules_alertmanager//:extensions.bzl\", \"alertmanager\")
alertmanager.version(version = \"$pinned\")
alertmanager.version(version = \"$pinned\")")"
(cd "$c" && bazel mod deps >/dev/null)
echo "PASS: repeated identical alertmanager.version resolves"

# 3. An unsupported version fails with a message naming alertmanager.version.
c="$(consumer unsupported 'alertmanager = use_extension("@rules_alertmanager//:extensions.bzl", "alertmanager")
alertmanager.version(version = "0.0.1")')"
if (cd "$c" && bazel mod deps) > "$work/unsupported.out" 2>&1; then
    echo "FAIL: unsupported version resolved" >&2; exit 1
fi
grep -q 'alertmanager.version(version = "0.0.1") is not supported' "$work/unsupported.out" || {
    cat "$work/unsupported.out" >&2; echo "FAIL: unsupported version: wrong error" >&2; exit 1; }
echo "PASS: unsupported version fails clearly"

# 4. //... loads.
(cd "$work/untagged" && bazel query @rules_alertmanager//... >/dev/null)
echo "PASS: @rules_alertmanager//... loads"
