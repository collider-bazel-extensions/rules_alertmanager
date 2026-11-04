#!/usr/bin/env bash
# alertmanager_config validation action (also used by
# //tests:invalid_config_test).
#
#   check_config.sh <amtool> <config> <out_resolved> [NAME=VALUE ...]
#
# Copies <config> (and the templates beside it) to a scratch dir,
# replaces each ${NAME} with VALUE, fails if any ${...} is left, runs
# `amtool check-config`, and writes the resolved config to
# <out_resolved>. Templates are resolved relative to the config file, so
# they must sit beside it — alertmanager_config stages them that way.
set -euo pipefail

amtool="$1"; config="$2"; out="$3"; shift 3

work="$(mktemp -d)"
trap 'rm -r -f -- "$work"' EXIT
cp -L "$(dirname "$config")"/* "$work"/ 2>/dev/null || true
cp -L "$config" "$work/alertmanager.yml"

# Placeholder substitution: literal string replacement (no regex, no
# escaping concerns in VALUE).
for pair in "$@"; do
    name="${pair%%=*}"
    value="${pair#*=}"
    NAME="\${$name}" VALUE="$value" awk '
        BEGIN { n = ENVIRON["NAME"]; v = ENVIRON["VALUE"] }
        {
            line = $0; res = ""
            while ((i = index(line, n)) > 0) {
                res = res substr(line, 1, i - 1) v
                line = substr(line, i + length(n))
            }
            print res line
        }' "$work/alertmanager.yml" > "$work/resolved.yml"
    mv "$work/resolved.yml" "$work/alertmanager.yml"
done

if left=$(grep -noE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$work/alertmanager.yml"); then
    echo "alertmanager_config: $config uses placeholders with no build-time value:" >&2
    echo "$left" | sed 's/^/  line /' >&2
    echo "Add them to the target's \`placeholders\` attribute." >&2
    exit 1
fi

if ! report=$("$amtool" check-config "$work/alertmanager.yml" 2>&1); then
    echo "alertmanager_config: amtool check-config failed for $config:" >&2
    echo "$report" >&2
    exit 1
fi
cp "$work/alertmanager.yml" "$out"
