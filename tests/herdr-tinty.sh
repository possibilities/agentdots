#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/scripts/herdr-tinty"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-herdr-tinty.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf 'herdr-tinty test: %s\n' "$*" >&2
    exit 1
}

test_home="$test_root/home"
test_code_root="$test_root/code"
test_bin="$test_root/bin"
test_log="$test_root/herdr.log"
test_tinty_log="$test_root/tinty.log"
test_active="$test_root/check-active"
base_config="$test_root/base-config.toml"
theme_fragment="$test_root/theme.toml"
alternate_fragment="$test_root/theme-alternate.toml"
invalid_fragment="$test_root/theme-invalid.toml"
config_target="$test_home/.config/herdr/config.toml"
theme_state="$test_home/.local/state/agentstart/herdr-theme.toml"
legacy_config="$test_code_root/funk/herdr/.config/herdr/config.toml"

mkdir -p "$test_home" "$test_bin" "$(dirname -- "$legacy_config")" \
    "$(dirname -- "$config_target")"

cat >"$base_config" <<'EOF'
[keys]
prefix = "ctrl+space"

[theme]
name = "custom"
auto_switch = false
EOF

cat >"$theme_fragment" <<'EOF'
# Tinty base16 scheme: Fixture One (fixture-one)
[theme.custom]
accent = "#010101"
panel_bg = "#020202"
sidebar_bg = "#030303"
active_row_bg = "#040404"
selection_bg = "#050505"
surface0 = "#060606"
surface1 = "#070707"
surface_dim = "#080808"
overlay0 = "#090909"
overlay1 = "#101010"
text = "#111111"
subtext0 = "#121212"
mauve = "#131313"
green = "#141414"
yellow = "#151515"
red = "#161616"
blue = "#171717"
teal = "#181818"
peach = "#191919"

[ui.sidebar.agents]
rows = [[
  "state_icon",
  { token = "$project", fg = "#121212", bold = true, dim = false },
], [
  { token = "$conversation", fg = "#080808", dim = false },
]]
EOF
sed -e 's/Fixture One (fixture-one)/Fixture Two (fixture-two)/' \
    -e 's/#010101/#abcdef/' "$theme_fragment" >"$alternate_fragment"
{
    cat "$theme_fragment"
    printf 'INVALID\n'
} >"$invalid_fragment"
cp "$base_config" "$legacy_config"
ln -s "$legacy_config" "$config_target"

cat >"$test_bin/herdr" <<'EOF'
#!/bin/bash
set -euo pipefail

case "${1:-}:${2:-}" in
    config:check)
        printf 'check %s\n' "${HERDR_CONFIG_PATH:?}" >>"${TEST_HERDR_LOG:?}"
        if grep -F INVALID "$HERDR_CONFIG_PATH" >/dev/null; then
            printf 'invalid fixture config\n' >&2
            exit 1
        fi
        if [ "${TEST_HERDR_CHECK_DELAY:-0}" = 1 ]; then
            active_owned=0
            if mkdir "${TEST_HERDR_ACTIVE:?}" 2>/dev/null; then
                active_owned=1
            else
                printf 'overlap\n' >>"$TEST_HERDR_LOG"
            fi
            sleep 0.1
            if [ "$active_owned" -eq 1 ]; then
                rmdir "$TEST_HERDR_ACTIVE"
            fi
        fi
        ;;
    server:reload-config)
        printf 'reload\n' >>"${TEST_HERDR_LOG:?}"
        if [ "${TEST_HERDR_RELOAD_FAIL:-0}" = 1 ]; then
            printf 'server is not running\n' >&2
            exit 1
        fi
        if [ "${TEST_HERDR_RELOAD_PARTIAL:-0}" = 1 ]; then
            printf '%s\n' '{"id":"fixture:reload","result":{"diagnostics":["unknown config key theme.custom.selection_bg; ignoring key"],"status":"partial","type":"config_reload"}}'
        fi
        ;;
    *)
        printf 'unexpected herdr fixture invocation: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
chmod +x "$test_bin/herdr"

cat >"$test_bin/tinty" <<'EOF'
#!/bin/bash
set -euo pipefail

case "${1:-}" in
    apply)
        [ "$#" -eq 2 ] || exit 2
        printf 'apply %s\n' "$2" >>"${TEST_TINTY_LOG:?}"
        TINTY_THEME_FILE_PATH="${TEST_THEME_FRAGMENT:?}" \
            "${TEST_HELPER:?}" apply-theme "$TEST_THEME_FRAGMENT"
        ;;
    install)
        printf 'install\n' >>"${TEST_TINTY_LOG:?}"
        ;;
    update)
        printf 'update\n' >>"${TEST_TINTY_LOG:?}"
        ;;
    build)
        [ "$#" -ge 2 ] || exit 2
        mkdir -p "$2/themes"
        cp "${TEST_THEME_FRAGMENT:?}" "$2/themes/base16-fixture.toml"
        printf 'build %s\n' "$2" >>"${TEST_TINTY_LOG:?}"
        ;;
    *)
        printf 'unexpected tinty fixture invocation: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
chmod +x "$test_bin/tinty"

export HOME="$test_home"
export AGENTSTART_CODE_ROOT="$test_code_root"
export AGENTSTART_HERDR_CONFIG_SOURCE="$base_config"
export AGENTSTART_HERDR_CONFIG_TARGET="$config_target"
export AGENTSTART_HERDR_THEME_STATE="$theme_state"
export AGENTSTART_HERDR_LOCK_DIR="$test_home/.local/state/agentstart/herdr-tinty.lock"
export AGENTSTART_HERDR_BIN="$test_bin/herdr"
export AGENTSTART_TINTY_BIN="$test_bin/tinty"
export AGENTSTART_TINTY_TEMPLATE_TARGET="$test_home/.local/share/agentstart/tinted-herdr"
export AGENTSTART_TINTY_CONFIG_TARGET="$test_home/.config/tinted-theming/tinty/config.toml"
export AGENTSTART_HERDR_TINTY_BIN_TARGET="$test_home/.local/bin/herdr-tinty"
export TEST_HERDR_LOG="$test_log"
export TEST_HERDR_ACTIVE="$test_active"
export TEST_TINTY_LOG="$test_tinty_log"
export TEST_THEME_FRAGMENT="$theme_fragment"
export TEST_HELPER="$helper"

# Installation builds themes outside the checkout, links only owned files, and
# migrates the exact Funk-owned Herdr symlink while applying Base16 Chalk.
"$helper" install >/dev/null
[ -L "$AGENTSTART_HERDR_TINTY_BIN_TARGET" ] \
    || fail "install did not link the herdr-tinty command"
[ -L "$AGENTSTART_TINTY_CONFIG_TARGET" ] \
    || fail "install did not link Tinty configuration"
[ -f "$AGENTSTART_TINTY_TEMPLATE_TARGET/themes/base16-fixture.toml" ] \
    || fail "install did not activate built Base16 themes"
[ -f "$config_target" ] && [ ! -L "$config_target" ] \
    || fail "the Funk-owned Herdr symlink was not migrated to a generated file"
grep -Fqx "# Generated by AgentStart's herdr-tinty. Do not edit." "$config_target" \
    || fail "generated Herdr config is missing its ownership marker"
cmp -s "$theme_fragment" "$theme_state" \
    || fail "the applied Tinty fragment was not persisted"
grep -Fqx 'apply base16-chalk' "$test_tinty_log" \
    || fail "install did not deterministically apply Base16 Chalk"

for token in accent panel_bg sidebar_bg active_row_bg selection_bg surface0 \
    surface1 surface_dim overlay0 overlay1 text subtext0 mauve green yellow \
    red blue teal peach; do
    grep -q "^$token = " "$config_target" \
        || fail "generated Herdr config is missing theme token: $token"
done
grep -Fqx "  { token = \"\$project\", fg = \"#121212\", bold = true, dim = false }," \
    "$config_target" \
    || fail "generated Herdr config is missing the styled AgentSurface project token"
grep -Fqx "  { token = \"\$conversation\", fg = \"#080808\", dim = false }," "$config_target" \
    || fail "generated Herdr config is missing the undimmed branch-grey conversation token"

# Reapplying or changing the palette reloads Herdr without sending a theme
# notification.
: >"$test_log"
"$helper" apply-theme "$theme_fragment" >/dev/null
"$helper" apply-theme "$alternate_fragment" >/dev/null
if grep -F 'notify ' "$test_log" >/dev/null; then
    fail "theme application sent a notification"
fi

# A rejected candidate must leave both the live config and persisted palette
# byte-for-byte unchanged.
cp "$config_target" "$test_root/config-before-invalid"
cp "$theme_state" "$test_root/state-before-invalid"
if "$helper" apply-theme "$invalid_fragment" >/dev/null 2>&1; then
    fail "an invalid Herdr candidate was accepted"
fi
cmp -s "$test_root/config-before-invalid" "$config_target" \
    || fail "invalid candidate changed the live Herdr config"
cmp -s "$test_root/state-before-invalid" "$theme_state" \
    || fail "invalid candidate changed persisted theme state"

# Independent files and unrelated links are never treated as migration input.
independent_target="$test_root/independent/config.toml"
mkdir -p "$(dirname -- "$independent_target")"
printf 'keep me\n' >"$independent_target"
if AGENTSTART_HERDR_CONFIG_TARGET="$independent_target" \
    "$helper" apply-theme "$alternate_fragment" >/dev/null 2>&1; then
    fail "an independent regular Herdr config was replaced"
fi
[ "$(cat "$independent_target")" = 'keep me' ] \
    || fail "independent regular Herdr config changed"

unrelated_source="$test_root/unrelated-source.toml"
unrelated_target="$test_root/unrelated/config.toml"
mkdir -p "$(dirname -- "$unrelated_target")"
printf 'keep this link\n' >"$unrelated_source"
ln -s "$unrelated_source" "$unrelated_target"
if AGENTSTART_HERDR_CONFIG_TARGET="$unrelated_target" \
    "$helper" apply-theme "$alternate_fragment" >/dev/null 2>&1; then
    fail "an unrelated Herdr config symlink was replaced"
fi
[ -L "$unrelated_target" ] \
    || fail "unrelated Herdr config symlink changed"

# Updating the config remains successful when no server is available; the next
# Herdr start will read the already-validated file.
TEST_HERDR_RELOAD_FAIL=1 "$helper" apply-theme "$alternate_fragment" \
    >/dev/null 2>&1 \
    || fail "a missing Herdr server made a valid theme update fail"
grep -F '#abcdef' "$config_target" >/dev/null \
    || fail "valid theme did not replace the live config"
cmp -s "$alternate_fragment" "$theme_state" \
    || fail "valid theme did not update persisted state"

# A running server can be older than the installed binary and accept only part
# of a config that `herdr config check` validates. Keep the update successful,
# but surface the server diagnostic instead of silently discarding it.
partial_stderr="$test_root/reload-partial.stderr"
TEST_HERDR_RELOAD_PARTIAL=1 "$helper" apply-theme "$alternate_fragment" \
    >/dev/null 2>"$partial_stderr" \
    || fail "a partial Herdr reload made a valid theme update fail"
grep -F 'live reload was partial' "$partial_stderr" >/dev/null \
    || fail "partial Herdr reload status was hidden"
grep -F 'unknown config key theme.custom.selection_bg' "$partial_stderr" >/dev/null \
    || fail "partial Herdr reload diagnostic was hidden"

# render-config reconstructs a missing live file from the persisted fragment.
rm -f "$config_target"
"$helper" render-config >/dev/null
grep -F '#abcdef' "$config_target" >/dev/null \
    || fail "render-config did not restore the persisted palette"

# Cycling is intentionally absent: the integration has one installed scheme.
for command in next previous; do
    if "$helper" "$command" >/dev/null 2>&1; then
        fail "$command theme cycling command is still accepted"
    fi
done

# Two direct hook invocations serialize their validation sections.
: >"$test_log"
TEST_HERDR_CHECK_DELAY=1 "$helper" apply-theme "$theme_fragment" >/dev/null &
first_pid=$!
TEST_HERDR_CHECK_DELAY=1 "$helper" apply-theme "$alternate_fragment" >/dev/null &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
if grep -F overlap "$test_log" >/dev/null; then
    fail "concurrent theme updates were not serialized"
fi

printf 'herdr-tinty tests passed\n'
