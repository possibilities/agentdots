#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

fail() {
    printf 'validate: %s\n' "$*" >&2
    exit 1
}

shell_files="
scripts/install.sh
scripts/sync-skills
scripts/install-agent-clis
scripts/install-agentvoice-cli
scripts/install-agentsurface-shims
scripts/configure-orca
tests/validate.sh
tests/fixtures/npx
"

for file in $shell_files; do
    /bin/bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    shellcheck --shell=bash $shell_files
fi

for script in scripts/install.sh scripts/sync-skills scripts/install-agent-clis \
    scripts/install-agentvoice-cli scripts/install-agentsurface-shims \
    scripts/configure-orca; do
    [ -x "$script" ] || fail "installer script is not executable: $script"
done

# The llm model configuration and the Orca overlay are linked or merged from
# these sources; a missing or invalid one converges nothing, silently.
[ -s config/llm/extra-openai-models.yaml ] \
    || fail "llm model configuration is missing or empty: config/llm/extra-openai-models.yaml"
for orca_overlay in settings.json keybindings.json; do
    /usr/bin/jq -e . "config/orca/$orca_overlay" >/dev/null \
        || fail "Orca overlay is missing or invalid JSON: config/orca/$orca_overlay"
done

# The installer links these into ~/.config/arthack and Art Hack renders every
# skill against them, so an empty or missing prompt ships broken skills to a
# fresh account.
for prompt in SYSTEM.md GUIDELINES.md TOOLS.md; do
    [ -s "prompts/arthack/$prompt" ] \
        || fail "extension prompt is missing or empty: prompts/arthack/$prompt"
done

# The AgentVoice doctrine is linked into ~/.config/agentvoice and read once
# at server boot; a missing or empty file primes nothing, silently.
for doctrine in ORCHESTRATOR.md ORCHESTRATOR_SESSION_START.md server.json; do
    [ -s "prompts/agentvoice/$doctrine" ] \
        || fail "AgentVoice doctrine is missing or empty: prompts/agentvoice/$doctrine"
done
/usr/bin/jq -e . prompts/agentvoice/server.json >/dev/null \
    || fail "AgentVoice server.json is not valid JSON"

# Global advice belongs in the operator extension prompts, so the shared home
# guidance stays deliberately empty; the tripwire keeps advice from accreting
# back into every session.
[ -f prompts/AGENTS.md ] \
    || fail "the shared home guidance source is missing: prompts/AGENTS.md"
[ ! -s prompts/AGENTS.md ] \
    || fail "prompts/AGENTS.md should stay empty — global advice belongs in the operator extension prompts"

# This checkout participates in its own agent* scan: the fleet skill is how a
# session reads the dependency map, and the map is the skill's payload. The
# fleet convention ships agents/openai.yaml beside every SKILL.md and the
# skill directory must be self-contained — the skills tool ships it whole.
[ -f skills/fleet/SKILL.md ] \
    || fail "the fleet skill is missing: skills/fleet/SKILL.md"
grep -q '^name: fleet$' skills/fleet/SKILL.md \
    || fail "the fleet skill frontmatter does not name itself"
[ -f skills/fleet/agents/openai.yaml ] \
    || fail "the fleet skill is missing its agents/openai.yaml manifest"
grep -q 'allow_implicit_invocation: true' skills/fleet/agents/openai.yaml \
    || fail "the fleet skill manifest does not allow implicit invocation"
[ -s skills/fleet/MAP.md ] \
    || fail "the fleet dependency map is missing: skills/fleet/MAP.md"
grep -q '```mermaid' skills/fleet/MAP.md \
    || fail "the fleet dependency map has no mermaid diagram"
if grep -F '../' skills/fleet/SKILL.md >/dev/null; then
    fail "the fleet skill reaches outside its own directory and would ship broken"
fi

# Cross-project guidance lives in the wiki, not in this repository; a
# guidance/ directory reappearing here means the decision reversed silently.
[ ! -e guidance ] \
    || fail "cross-project guidance moved to the wiki (funk-boundary, tool-advertisement-policy); do not grow guidance/ back"

# Public-repo hygiene: everything resolves from $HOME, so a literal /Users/
# path is an account-name assumption leaking back in.
if grep -rn '/Users/' scripts prompts config skills README.md AGENTS.md CONTEXT.md 2>/dev/null; then
    fail "a literal /Users/ path assumes an account name; resolve from \$HOME instead"
fi
[ -s LICENSE ] || fail "public repository is missing its LICENSE"

# Art Hack follows the checkout convention: absent is a skip, present but
# incomplete dies.
grep -F 'art_hack_present=0' scripts/install.sh >/dev/null \
    || fail "installer no longer treats a missing Art Hack checkout as a skip"
grep -F 'no Art Hack checkout at' scripts/install.sh >/dev/null \
    || fail "installer does not report a skipped Art Hack checkout clearly"

# A machine that has not cloned AgentVoice is a skip, not a failure: the CLI is
# one of several optional checkout-backed tools and an install must not stop
# for a machine that simply does not have it.
skip_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/agentdots-validate.XXXXXX")
trap 'rm -rf "$skip_test_dir"' EXIT
agentvoice_missing_home="$skip_test_dir/agentvoice-missing-home"
mkdir -p "$agentvoice_missing_home"
set +e
agentvoice_missing_output=$(
    HOME="$agentvoice_missing_home" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        "$root/scripts/install-agentvoice-cli" 2>&1
)
agentvoice_missing_status=$?
set -e
[ "$agentvoice_missing_status" -eq 0 ] \
    || fail "AgentVoice CLI installer did not skip a machine without a checkout"
printf '%s\n' "$agentvoice_missing_output" \
    | grep -F \
        "no checkout at $agentvoice_missing_home/code/agentvoice; skipping." \
        >/dev/null \
    || fail "AgentVoice CLI installer did not report the skipped checkout clearly"

# The Orca overlay must merge without adopting: unrelated state survives,
# every overlay key converges, a running divergent Orca defers with
# EX_TEMPFAIL instead of racing its writer, and a fresh profile is seeded.
orca_home="$skip_test_dir/orca-home"
orca_state="$orca_home/Library/Application Support/orca/orca-data.json"
mkdir -p "$(dirname "$orca_state")"
printf '%s\n' \
    '{"repos":[{"id":"preserve-me"}],"settings":{"showMenuBarIcon":false,"notifications":{"enabled":false}}}' \
    >"$orca_state"
HOME="$orca_home" AGENTDOTS_TEST_ORCA_RUNNING=0 "$root/scripts/configure-orca" >/dev/null
jq -e '
  .repos == [{"id":"preserve-me"}] and
  .settings.showMenuBarIcon == false and
  .settings.notifications.enabled == false and
  .settings.defaultTuiAgent == "claude" and
  .settings.mobilePairingConnectionMode == "local-only" and
  .settings.openLinksInApp == true and
  .settings.openLinksInAppPreferencePrompted == true and
  .settings.refreshLocalBaseRefOnWorktreeCreate == true and
  .settings.showMobileButton == false and
  .settings.tabAutoGenerateTitle == true and
  .settings.terminalFontFamily == "0xProto Nerd Font" and
  .settings.terminalFontSize == 20 and
  .settings.terminalMacOptionAsAlt == "true" and
  .settings.terminalMacOptionAsAltMigrated == true and
  .settings.notifications.terminalBell == true and
  .settings.theme == "dark"
' "$orca_state" >/dev/null || fail "Orca settings overlay did not preserve unrelated state"
jq -e 'type == "object" and .version == 1' "$orca_home/.orca/keybindings.json" >/dev/null \
    || fail "Orca keybindings overlay was not merged into the live file"
HOME="$orca_home" AGENTDOTS_TEST_ORCA_RUNNING=1 "$root/scripts/configure-orca" >/dev/null
orca_state_tmp="$orca_state.tmp"
jq '.settings.theme = "system"' "$orca_state" >"$orca_state_tmp"
mv "$orca_state_tmp" "$orca_state"
set +e
orca_running_output=$(
    HOME="$orca_home" AGENTDOTS_TEST_ORCA_RUNNING=1 \
        "$root/scripts/configure-orca" 2>&1
)
orca_running_status=$?
set -e
[ "$orca_running_status" -ne 0 ] \
    || fail "Orca settings reconciliation raced a running divergent profile"
# EX_TEMPFAIL distinguishes "repeat this after quitting Orca" from a broken
# installation, so Funk's ./install can report it instead of failing the run.
[ "$orca_running_status" -eq 75 ] \
    || fail "running-Orca guard did not exit EX_TEMPFAIL: $orca_running_status"
printf '%s\n' "$orca_running_output" | grep -F 'quit Orca' >/dev/null \
    || fail "Orca running-profile guard did not explain how to reconcile"
HOME="$orca_home" AGENTDOTS_TEST_ORCA_RUNNING=0 "$root/scripts/configure-orca" >/dev/null
jq -e '.settings.theme == "dark"' "$orca_state" >/dev/null \
    || fail "Orca settings did not reconcile after the running-profile guard cleared"
mv "$orca_state" "$orca_state.merged-test"
HOME="$orca_home" AGENTDOTS_TEST_ORCA_RUNNING=0 "$root/scripts/configure-orca" >/dev/null
jq -e '
  .settings.defaultTuiAgent == "claude" and
  .settings.mobilePairingConnectionMode == "local-only" and
  .settings.openLinksInApp == true and
  .settings.openLinksInAppPreferencePrompted == true and
  .settings.refreshLocalBaseRefOnWorktreeCreate == true and
  .settings.showMobileButton == false and
  .settings.tabAutoGenerateTitle == true and
  .settings.terminalMacOptionAsAltMigrated == true and
  .settings.notifications == {"terminalBell":true}
' "$orca_state" >/dev/null || fail "Orca settings did not seed a fresh profile"
HOME="$orca_home" "$root/scripts/configure-orca" --check >/dev/null

# The agent* skill scan finds participants by convention instead of by list:
# an agent* checkout that exports skills/<name>/SKILL.md is a participant, and
# everything else under the root is not. The scan must batch one invocation
# per project naming every skill it found, and no participant is exempt.
code_skills_root="$skip_test_dir/code-root"
code_skills_log="$skip_test_dir/npx.log"
mkdir -p \
    "$code_skills_root/agentdemo/skills/demo" \
    "$code_skills_root/agentdemo/skills/second" \
    "$code_skills_root/agentquiet/src" \
    "$code_skills_root/agentvoice/skills/story" \
    "$code_skills_root/notagent/skills/x"
for code_skills_fixture in \
    agentdemo/skills/demo \
    agentdemo/skills/second \
    agentvoice/skills/story \
    notagent/skills/x; do
    printf '# fixture skill\n' >"$code_skills_root/$code_skills_fixture/SKILL.md"
done

sync_plan=$(
    AGENTDOTS_CODE_ROOT="$code_skills_root" \
        AGENTDOTS_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTDOTS_TEST_NPX_LOG="$code_skills_log" \
        "$root/scripts/sync-skills" --check
)
[ ! -s "$code_skills_log" ] \
    || fail "skill sync plan invoked the skills tool instead of only printing"
printf '%s\n' "$sync_plan" \
    | grep -F 'npx --yes skills add https://github.com/stablyai/orca --agent codex claude-code pi --skill orca-cli orchestration computer-use --global --yes' \
        >/dev/null \
    || fail "skill sync plan omits the Orca harness skills"
printf '%s\n' "$sync_plan" \
    | grep -F "npx --yes skills add \"$code_skills_root/agentdemo\" --agent codex claude-code pi --skill demo second --global --yes" \
        >/dev/null \
    || fail "skill sync plan omits the skills discovered in a participating checkout"
printf '%s\n' "$sync_plan" \
    | grep -F "npx --yes skills add \"$code_skills_root/agentvoice\" --agent codex claude-code pi --skill story --global --yes" \
        >/dev/null \
    || fail "skill sync plan exempts AgentVoice instead of scanning it like any other participant"
if printf '%s\n' "$sync_plan" | grep -Eq 'agentquiet|notagent'; then
    fail "skill sync plan includes a checkout that is not a participant"
fi

AGENTDOTS_CODE_ROOT="$code_skills_root" \
    AGENTDOTS_NPX_BIN="$root/tests/fixtures/npx" \
    AGENTDOTS_TEST_NPX_LOG="$code_skills_log" \
    "$root/scripts/sync-skills" >/dev/null
grep -F 'npx-stub <--yes> <skills> <add> <https://github.com/stablyai/orca> <--agent> <codex> <claude-code> <pi> <--skill> <orca-cli> <orchestration> <computer-use> <--global> <--yes>' \
    "$code_skills_log" >/dev/null \
    || fail "skill sync did not synchronize the Orca harness skills"
grep -F 'npx-stub <--yes> <skills> <list> <--global> <--json>' \
    "$code_skills_log" >/dev/null \
    || fail "skill sync did not verify the Orca skill records"
grep -F "npx-stub <--yes> <skills> <add> <$code_skills_root/agentdemo> <--agent> <codex> <claude-code> <pi> <--skill> <demo> <second> <--global> <--yes>" \
    "$code_skills_log" >/dev/null \
    || fail "skill sync did not ship both discovered skills in one invocation"
grep -F "npx-stub <--yes> <skills> <add> <$code_skills_root/agentvoice> <--agent> <codex> <claude-code> <pi> <--skill> <story> <--global> <--yes>" \
    "$code_skills_log" >/dev/null \
    || fail "skill sync skipped AgentVoice instead of synchronizing it"
if grep -E 'agentquiet|notagent' "$code_skills_log" >/dev/null; then
    fail "skill sync synchronized a checkout that is not a participant"
fi
[ "$(grep -c 'skills> <add>' "$code_skills_log")" -eq 3 ] \
    || fail "skill sync did not invoke the skills tool exactly once per source"

# A checkout without skills is silently not a participant, but a participant
# whose synchronization fails is a real error, and the message has to name the
# project: the operator is being asked to go fix that repository. The stub
# fails only local-path adds so the run reaches the scan through a healthy
# Orca step.
set +e
scan_failure=$(
    AGENTDOTS_CODE_ROOT="$code_skills_root" \
        AGENTDOTS_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTDOTS_TEST_NPX_LOCAL_EXIT=9 \
        "$root/scripts/sync-skills" 2>&1
)
scan_failure_status=$?
set -e
[ "$scan_failure_status" -ne 0 ] \
    || fail "skill sync ignored a failing skills tool"
printf '%s\n' "$scan_failure" | grep -F 'agentdemo' >/dev/null \
    || fail "skill sync failure does not name the project to fix"

# A failure on the Orca step itself must also propagate, before any scanning.
set +e
orca_failure_output=$(
    AGENTDOTS_CODE_ROOT="$code_skills_root" \
        AGENTDOTS_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTDOTS_TEST_NPX_EXIT=7 \
        "$root/scripts/sync-skills" 2>&1
)
orca_failure_status=$?
set -e
[ "$orca_failure_status" -ne 0 ] \
    || fail "skill sync ignored a failing Orca synchronization"
: "$orca_failure_output"

# shellcheck disable=SC2016 # Match the exclusion guard the scan must not have.
if grep -F '[ "$project_name" != agentvoice ] || continue' scripts/sync-skills >/dev/null; then
    fail "the skill scan exempts AgentVoice by name"
fi

# The installation plan embeds the skill sync's own plan, pointed at the
# fixture tree so the asserted lines are the same on every machine.
install_plan=$(AGENTDOTS_CODE_ROOT="$code_skills_root" "$root/scripts/install.sh" --check)
# shellcheck disable=SC2016 # The plan lines are asserted literally, $-signs and all.
for required_install in \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh' \
    'curl -fsSL https://pi.dev/install.sh | sh  # in its own session, no controlling terminal' \
    'brew install or upgrade zig  # AgentVoice'"'"'s native duplex audio path builds against it' \
    'brew install or upgrade llm  # an AI CLI, so Agentdots'"'"' outright — moved out of Funk'"'"'s Brewfile' \
    'ln -sfn config/llm/extra-openai-models.yaml into ~/Library/Application Support/io.datasette.llm  # llm'"'"'s model configuration' \
    'scripts/configure-orca  # apply the Orca settings overlay; Funk'"'"'s ./install runs it via funk configure-orca' \
    'npm install --global @native-sdk/cli@0.7  # the line the native-sdk skill documents' \
    'npm install --global agent-browser@0.33.2  # Agentweb'"'"'s config.json digest-locks this exact build' \
    'ln -sfn "$(command -v agent-browser)" ~/.local/bin/agent-browser  # the candidate Agentscrape resolves before PATH' \
    'codex mcp add shadcn -- npx shadcn@latest mcp' \
    'claude mcp add --scope user shadcn -- npx shadcn@latest mcp' \
    'native skills list' \
    'ln -sfn prompts/AGENTS.md ~/AGENTS.md  # deliberately empty; advice belongs in the extension prompts' \
    'ln -sfn ~/AGENTS.md ~/.claude/CLAUDE.md  # Claude Code reads CLAUDE.md, not AGENTS.md' \
    'ln -sfn ~/AGENTS.md ~/.codex/AGENTS.md  # Codex skips empty guidance files' \
    'ln -sfn prompts/agentvoice/{ORCHESTRATOR.md,ORCHESTRATOR_SESSION_START.md,server.json} into ~/.config/agentvoice  # the voice orchestrator'"'"'s doctrine, read at server boot' \
    'ln -sfn prompts/arthack/{SYSTEM,GUIDELINES,TOOLS}.md into ~/.config/arthack  # the extension prompts Art Hack renders against' \
    'npx --yes skills add https://github.com/stablyai/orca --agent codex claude-code pi --skill orca-cli orchestration computer-use --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/skills --agent codex claude-code pi --skill find-skills --global --yes' \
    'npx --yes skills add https://github.com/anthropics/skills --agent codex claude-code pi --skill frontend-design --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code pi --skill web-design-guidelines --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code pi --skill vercel-react-best-practices --global --yes' \
    'npx --yes skills add https://github.com/vercel/ai --agent codex claude-code pi --skill ai-sdk --global --yes' \
    'npx --yes skills add https://github.com/vercel/ai-elements --agent codex claude-code pi --skill ai-elements --global --yes' \
    'npx --yes skills add https://github.com/shadcn/ui --agent codex claude-code pi --skill shadcn --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/native --agent codex claude-code pi --skill native-sdk --global --yes' \
    "npx --yes skills add \"\$HOME/code/arthack\" --agent codex claude-code pi --skill collab build resource-create resource-update story --global --yes" \
    "npx --yes skills add \"$code_skills_root/agentdemo\" --agent codex claude-code pi --skill demo second --global --yes" \
    "\"\$HOME/code/arthack/scripts/render\""; do
    printf '%s\n' "$install_plan" | grep -F "$required_install" >/dev/null \
        || fail "installation plan is missing: $required_install"
done
if printf '%s\n' "$install_plan" | grep -Eq -- '--skill ([^[:space:]]+ )*funk([[:space:]]|$)'; then
    fail "installation plan still installs the retired Funk priming skill"
fi
if printf '%s\n' "$install_plan" | grep -qi 'livekit'; then
    fail "installation plan still includes LiveKit setup"
fi
# AgentVoice exports skills/ like the other agent tools and is scanned like
# them; nothing about it is special to this plan.
printf '%s\n' "$install_plan" \
    | grep -F "skills add \"$code_skills_root/agentvoice\"" >/dev/null \
    || fail "installation plan omits the skills AgentVoice exports by convention"
# The agentchats checkout ships its chats skill through the scan; an explicit
# line would be the second synchronization path its guidance forbids.
if printf '%s\n' "$install_plan" \
    | grep -F '/code/agentchats"' >/dev/null; then
    fail "installation plan still synchronizes chats explicitly beside the scan"
fi
# The Funk boundary: desktop applications and the GitHub CLI are Funk's, so a
# cask or gh line reappearing here means the seam is leaking back.
if printf '%s\n' "$install_plan" | grep -Eq -- '--cask|brew install or upgrade gh'; then
    fail "installation plan crossed the Funk boundary: desktop casks and gh are Funk's"
fi

# shellcheck disable=SC2016 # Match the literal helper invocations in the script.
for sync_invocation in \
    '"$script_dir/sync-skills" --check' \
    '"$script_dir/sync-skills"'; do
    grep -F "$sync_invocation" scripts/install.sh >/dev/null \
        || fail "installer does not run the skill sync: $sync_invocation"
done
# The sync must follow the explicit lines it deliberately does not replace.
install_sync_line=$(
    # shellcheck disable=SC2016 # Match the literal helper invocation.
    grep -n -F '"$script_dir/sync-skills"' scripts/install.sh \
        | grep -v -F -- '--check' | cut -d: -f1
)
install_render_line=$(
    # shellcheck disable=SC2016 # Match the literal render invocation; the
    # string also appears in its earlier -x precondition, so the last match is
    # the invocation itself.
    grep -n -F '"$art_hack_root/scripts/render"' scripts/install.sh \
        | tail -1 | cut -d: -f1
)
[ "$install_render_line" -lt "$install_sync_line" ] \
    || fail "installer runs the skill sync before the explicit Art Hack lines"
grep -F "art_hack_root=\"\$HOME/code/arthack\"" scripts/install.sh >/dev/null \
    || fail "installer does not own the Art Hack skill source"
grep -F "npx --yes skills add \"\$art_hack_root\"" scripts/install.sh >/dev/null \
    || fail "installer does not synchronize the Art Hack skills"
grep -F "for art_hack_skill in collab build; do" scripts/install.sh >/dev/null \
    || fail "installer does not validate the collab and build skill sources"
grep -F "\$art_hack_root/\$art_hack_skill/agents/openai.yaml" scripts/install.sh >/dev/null \
    || fail "installer does not validate the Art Hack skill manifests"
grep -F 'link_agent_guidance' scripts/install.sh >/dev/null \
    || fail "installer does not link the shared agent guidance"
# shellcheck disable=SC2016 # Match the literal target paths in the script.
grep -F '"$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"' scripts/install.sh >/dev/null \
    || fail "installer does not target both CLI guidance locations"
grep -F 'refusing to replace independent guidance' scripts/install.sh >/dev/null \
    || fail "installer would replace independent guidance files"
grep -F 'link_extension_prompts' scripts/install.sh >/dev/null \
    || fail "installer does not link the operator extension prompts"
grep -F 'refusing to replace independent extension prompt' scripts/install.sh >/dev/null \
    || fail "installer would replace an independent extension prompt"
for prompt_name in SYSTEM.md GUIDELINES.md TOOLS.md; do
    grep -F "$prompt_name" scripts/install.sh >/dev/null \
        || fail "installer does not link the $prompt_name extension prompt"
done
grep -F 'link_agentvoice_config' scripts/install.sh >/dev/null \
    || fail "installer does not link the AgentVoice doctrine"
grep -F 'refusing to replace independent AgentVoice configuration' scripts/install.sh >/dev/null \
    || fail "installer would replace independent AgentVoice configuration"
for doctrine_name in ORCHESTRATOR.md ORCHESTRATOR_SESSION_START.md server.json; do
    grep -F "$doctrine_name" scripts/install.sh >/dev/null \
        || fail "installer does not link the AgentVoice $doctrine_name"
done
# shellcheck disable=SC2016 # Match the literal home-guidance source path.
grep -F 'source="$repo_root/prompts/AGENTS.md"' scripts/install.sh >/dev/null \
    || fail "installer does not own the shared home guidance"
grep -F 'install_or_upgrade_formula llm' scripts/install.sh >/dev/null \
    || fail "installer does not converge the llm CLI"
grep -F 'link_llm_config' scripts/install.sh >/dev/null \
    || fail "installer does not link the llm model configuration"
grep -F 'refusing to replace independent llm configuration' scripts/install.sh >/dev/null \
    || fail "installer would replace independent llm configuration"

# The native-sdk skill documents the 0.7 line and Zig builds both Native SDK
# applications and AgentVoice's opt-in native duplex audio device, so both
# stay pinned rather than tracking latest. agent-browser is pinned because
# Agentweb digest-locks the exact build in its config.json.
grep -F 'native_sdk_version=0.7' scripts/install.sh >/dev/null \
    || fail "installer does not pin the Native SDK CLI to the compatible 0.7 line"
if grep -F '@native-sdk/cli@latest' scripts/install.sh >/dev/null; then
    fail "installer tracks the latest Native SDK CLI release"
fi
grep -F 'install_or_upgrade_formula zig' scripts/install.sh >/dev/null \
    || fail "installer does not converge the Zig toolchain"
grep -F 'agent_browser_version=0.33.2' scripts/install.sh >/dev/null \
    || fail "installer does not pin agent-browser to the Agentweb-locked build"
grep -F 'refusing to replace independent file' scripts/install.sh >/dev/null \
    || fail "installer would replace an independent ~/.local/bin/agent-browser"

# Pi reads its prompts from /dev/tty, so only removing the controlling
# terminal keeps the run unattended and stops it editing the Stow-managed
# shell profile.
grep -F 'run_without_controlling_terminal /bin/sh' scripts/install.sh >/dev/null \
    || fail "Pi installer is not detached from the controlling terminal"
grep -F 'POSIX::setsid()' scripts/install.sh >/dev/null \
    || fail "Pi installer detachment does not start a new session"

# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-agentvoice-cli"' scripts/install.sh >/dev/null \
    || fail "installer does not install the AgentVoice voice CLI"
# shellcheck disable=SC2016 # Match the literal status variable in the script.
grep -F 'exit "$agentvoice_cli_status"' scripts/install.sh >/dev/null \
    || fail "installer does not propagate an AgentVoice CLI installation failure"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-agent-clis"' scripts/install.sh >/dev/null \
    || fail "installer does not install the agent CLIs"
# shellcheck disable=SC2016 # Match the literal status variable in the script.
grep -F 'exit "$agent_clis_status"' scripts/install.sh >/dev/null \
    || fail "installer does not propagate an agent CLI installation failure"
# shellcheck disable=SC2016 # Match the literal checkout resolution in the script.
grep -F 'agentchats_root="$HOME/code/agentchats"' scripts/install.sh >/dev/null \
    || fail "installer does not own the cass installation call"
# shellcheck disable=SC2016 # Match the literal invocation in the script.
grep -F '"$agentchats_root/scripts/install.sh" --install' scripts/install.sh >/dev/null \
    || fail "installer does not invoke the agentchats contract"

# The Funk boundary, from this side: nothing here may install a desktop cask,
# migrate gh credentials, or grow launchd machinery — those are Funk's.
if grep -Eq -- '--cask' scripts/install.sh scripts/sync-skills; then
    fail "an Agentdots script crossed the Funk boundary: casks are Funk's"
fi
if grep -F 'oauth_token' scripts/install.sh >/dev/null; then
    fail "an Agentdots script crossed the Funk boundary: gh migration is Funk's"
fi
# Operations, not prose: comments may name launchd context, but invoking
# launchctl or writing a plist is machine integration and belongs to Funk.
if grep -Eq 'launchctl|\.plist' scripts/install.sh scripts/sync-skills; then
    fail "an Agentdots script crossed the Funk boundary: launchd is Funk's"
fi

printf 'ok\n'
