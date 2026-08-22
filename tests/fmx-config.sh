#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/scripts/fmx-config"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-fmx-config.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf 'fmx-config test: %s\n' "$*" >&2
    exit 1
}

source_config="$test_root/source.toml"
target_config="$test_root/home/.config/fmx/config.toml"
cat >"$source_config" <<'EOF'
[keys]
prefix = "ctrl+space"
EOF

export HOME="$test_root/home"
export AGENTSTART_FMX_CONFIG_SOURCE="$source_config"
export AGENTSTART_FMX_CONFIG_TARGET="$target_config"

"$helper" install
[ -L "$target_config" ] || fail "install did not link the fmx config"
cmp -s "$source_config" "$target_config" || fail "linked fmx config does not resolve to the tracked source"
grep -Fqx 'prefix = "ctrl+space"' "$target_config" \
    || fail "installed fmx config does not use Ctrl-Space"

# The converge is rerunnable.
"$helper" install

# Independent regular files are never replaced.
independent_target="$test_root/independent/config.toml"
mkdir -p "$(dirname -- "$independent_target")"
printf 'keep me\n' >"$independent_target"
if AGENTSTART_FMX_CONFIG_TARGET="$independent_target" "$helper" install >/dev/null 2>&1; then
    fail "an independent regular fmx config was replaced"
fi
[ "$(cat "$independent_target")" = "keep me" ] || fail "independent fmx config changed"

empty_target="$test_root/empty/config.toml"
mkdir -p "$(dirname -- "$empty_target")"
: >"$empty_target"
if AGENTSTART_FMX_CONFIG_TARGET="$empty_target" "$helper" install >/dev/null 2>&1; then
    fail "an independent empty fmx config was replaced"
fi
[ -f "$empty_target" ] && [ ! -L "$empty_target" ] || fail "independent empty fmx config changed"

# fmx's own top-level settings are its business; only the [keys] table has to
# stay inside Herdr's public key schema, because the two configs share a
# prefix and an operator who reads them as one set of bindings.
awk '
    /^#/ || /^[[:space:]]*$/ { next }
    /^\[/ { section = $0; next }
    section == "[keys]" && /^prefix[[:space:]]*=/ { next }
    section == "[keys]" { exit 1 }
' "$root/config/fmx/config.toml" \
    || fail "tracked fmx [keys] is not a strict subset of Herdr keys"

printf 'fmx-config tests passed\n'
