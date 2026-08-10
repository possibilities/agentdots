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
scripts/install-launchagents
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
    scripts/install-launchagents \
    scripts/install-agentvoice-cli scripts/install-agentsurface-shims \
    scripts/configure-orca; do
    [ -x "$script" ] || fail "installer script is not executable: $script"
done

# The obsolete llm model records stay gone; the Orca overlay remains the only
# AI-tool configuration source this checkout carries.
[ ! -e config/llm/extra-openai-models.yaml ] \
    || fail "obsolete llm model records returned"
for orca_overlay in settings.json keybindings.json; do
    /usr/bin/jq -e . "config/orca/$orca_overlay" >/dev/null \
        || fail "Orca overlay is missing or invalid JSON: config/orca/$orca_overlay"
done

# The installer links these into ~/.config/agentguidance and agentguidance
# renders every skill against them, so an empty or missing prompt ships
# broken skills to a fresh account.
for prompt in SYSTEM.md GUIDELINES.md TOOLS.md; do
    [ -s "prompts/agentguidance/$prompt" ] \
        || fail "extension prompt is missing or empty: prompts/agentguidance/$prompt"
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

# The post-sync hook is how agentguidance's templates survive the scan:
# sync-skills must run a participant's executable scripts/post-sync right
# after its skills land, and a failing hook must name the project.
# shellcheck disable=SC2016 # Match the literal hook invocation.
grep -F '"$project/scripts/post-sync"' scripts/sync-skills >/dev/null \
    || fail "sync-skills does not run a participant's post-sync hook"
grep -F 'post-sync hook failed' scripts/sync-skills >/dev/null \
    || fail "sync-skills does not propagate a failing post-sync hook"

# A machine that has not cloned AgentVoice is a skip, not a failure: the CLI is
# one of several optional checkout-backed tools and an install must not stop
# for a machine that simply does not have it.
skip_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-validate.XXXXXX")
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
HOME="$orca_home" AGENTSTART_TEST_ORCA_RUNNING=0 "$root/scripts/configure-orca" >/dev/null
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
HOME="$orca_home" AGENTSTART_TEST_ORCA_RUNNING=1 "$root/scripts/configure-orca" >/dev/null
orca_state_tmp="$orca_state.tmp"
jq '.settings.theme = "system"' "$orca_state" >"$orca_state_tmp"
mv "$orca_state_tmp" "$orca_state"
set +e
orca_running_output=$(
    HOME="$orca_home" AGENTSTART_TEST_ORCA_RUNNING=1 \
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
HOME="$orca_home" AGENTSTART_TEST_ORCA_RUNNING=0 "$root/scripts/configure-orca" >/dev/null
jq -e '.settings.theme == "dark"' "$orca_state" >/dev/null \
    || fail "Orca settings did not reconcile after the running-profile guard cleared"
mv "$orca_state" "$orca_state.merged-test"
HOME="$orca_home" AGENTSTART_TEST_ORCA_RUNNING=0 "$root/scripts/configure-orca" >/dev/null
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
# agentdemo carries a post-sync hook (the agentguidance pattern): it must
# appear in the plan, fire after the real sync, and fail the run when it
# fails.
mkdir -p "$code_skills_root/agentdemo/scripts"
cat >"$code_skills_root/agentdemo/scripts/post-sync" <<'EOF'
#!/bin/bash
set -euo pipefail
[ -z "${AGENTSTART_TEST_HOOK_EXIT:-}" ] || exit "$AGENTSTART_TEST_HOOK_EXIT"
touch "$(cd -P -- "$(dirname -- "$0")/.." && pwd)/post-sync-ran"
EOF
chmod +x "$code_skills_root/agentdemo/scripts/post-sync"

sync_plan=$(
    AGENTSTART_CODE_ROOT="$code_skills_root" \
        AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTSTART_TEST_NPX_LOG="$code_skills_log" \
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
printf '%s\n' "$sync_plan" \
    | grep -F "\"$code_skills_root/agentdemo/scripts/post-sync\"" >/dev/null \
    || fail "skill sync plan omits a participant's post-sync hook"
[ ! -e "$code_skills_root/agentdemo/post-sync-ran" ] \
    || fail "skill sync plan ran a post-sync hook instead of only printing"

AGENTSTART_CODE_ROOT="$code_skills_root" \
    AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
    AGENTSTART_TEST_NPX_LOG="$code_skills_log" \
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
[ -e "$code_skills_root/agentdemo/post-sync-ran" ] \
    || fail "skill sync did not run a participant's post-sync hook after its skills landed"

# A failing hook is a failing sync, and the message names the project.
set +e
hook_failure=$(
    AGENTSTART_CODE_ROOT="$code_skills_root" \
        AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTSTART_TEST_HOOK_EXIT=9 \
        "$root/scripts/sync-skills" 2>&1
)
hook_failure_status=$?
set -e
[ "$hook_failure_status" -ne 0 ] \
    || fail "skill sync ignored a failing post-sync hook"
printf '%s\n' "$hook_failure" | grep -F 'agentdemo post-sync hook failed' >/dev/null \
    || fail "post-sync hook failure does not name the project to fix"

# A checkout without skills is silently not a participant, but a participant
# whose synchronization fails is a real error, and the message has to name the
# project: the operator is being asked to go fix that repository. The stub
# fails only local-path adds so the run reaches the scan through a healthy
# Orca step.
set +e
scan_failure=$(
    AGENTSTART_CODE_ROOT="$code_skills_root" \
        AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTSTART_TEST_NPX_LOCAL_EXIT=9 \
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
    AGENTSTART_CODE_ROOT="$code_skills_root" \
        AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTSTART_TEST_NPX_EXIT=7 \
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
install_plan=$(AGENTSTART_CODE_ROOT="$code_skills_root" "$root/scripts/install.sh" --check)
# shellcheck disable=SC2016 # The plan lines are asserted literally, $-signs and all.
for required_install in \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh' \
    'curl -fsSL https://pi.dev/install.sh | sh  # in its own session, no controlling terminal' \
    'brew install or upgrade zig  # AgentVoice'"'"'s native duplex audio path builds against it' \
    'brew install or upgrade llm  # an AI CLI, so AgentStart'"'"'s outright — moved out of Funk'"'"'s Brewfile' \
    'remove AgentStart-owned ~/Library/Application Support/io.datasette.llm/extra-openai-models.yaml symlink  # its extra model records are obsolete' \
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
    'ln -sfn prompts/agentguidance/{SYSTEM,GUIDELINES,TOOLS}.md into ~/.config/agentguidance  # the extension prompts agentguidance renders against' \
    'npx --yes skills add https://github.com/stablyai/orca --agent codex claude-code pi --skill orca-cli orchestration computer-use --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/skills --agent codex claude-code pi --skill find-skills --global --yes' \
    'npx --yes skills add https://github.com/anthropics/skills --agent codex claude-code pi --skill frontend-design --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code pi --skill web-design-guidelines --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code pi --skill vercel-react-best-practices --global --yes' \
    'npx --yes skills add https://github.com/vercel/ai --agent codex claude-code pi --skill ai-sdk --global --yes' \
    'npx --yes skills add https://github.com/vercel/ai-elements --agent codex claude-code pi --skill ai-elements --global --yes' \
    'npx --yes skills add https://github.com/shadcn/ui --agent codex claude-code pi --skill shadcn --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/native --agent codex claude-code pi --skill native-sdk --global --yes' \
    "npx --yes skills add \"$code_skills_root/agentdemo\" --agent codex claude-code pi --skill demo second --global --yes" \
    "\"$code_skills_root/agentdemo/scripts/post-sync\""; do
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
# Agentguidance ships through the scan like every participant; an explicit
# line for it here would be the second synchronization path its guidance
# forbids, and the render belongs to its post-sync hook, not to this
# installer.
if grep -En 'arthack|agentguidance' scripts/install.sh \
    | grep -vF 'prompts/agentguidance' \
    | grep -vF '.config/agentguidance' \
    | grep -vF 'agentguidance renders' \
    | grep -vF "agentguidance's" >/dev/null; then
    fail "installer grew agentguidance handling beyond the extension prompts; the scan and post-sync hook own the rest"
fi
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
grep -F 'remove_retired_llm_config' scripts/install.sh >/dev/null \
    || fail "installer does not retire its obsolete llm model configuration"
# shellcheck disable=SC2016 # Match the literal ownership check in the script.
grep -F 'readlink "$target"' scripts/install.sh >/dev/null \
    || fail "installer does not verify ownership before removing the retired llm configuration"
if grep -F 'link_llm_config' scripts/install.sh >/dev/null; then
    fail "installer still links the obsolete llm model configuration"
fi

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

# The fleet statusline is one bar in three harness idioms: a render command
# for claude, a footer extension for pi, and an ordered pick from codex's
# fixed item set — codex has no custom renderer to install.
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-statusline" --install' scripts/install.sh >/dev/null \
    || fail "installer does not converge the fleet statusline"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-statusline" --check' scripts/install.sh >/dev/null \
    || fail "installation plan omits the fleet statusline"
[ -x scripts/install-statusline ] \
    || fail "the statusline installer is not executable"
for renderer in config/statusline/claude-statusline.sh config/statusline/pi-statusline.ts; do
    [ -s "$renderer" ] \
        || fail "statusline renderer is missing or empty: $renderer"
done
# Every step preserves a file it does not own, the same conflict rule the
# guidance links follow.
[ "$(grep -c 'refusing to replace an independent' scripts/install-statusline)" -eq 2 ] \
    || fail "the statusline installer would replace an independent claude or pi file"
# Orca writes its own statusLine entry pointing at its telemetry sink;
# replacing that entry is only safe because the renderer forwards the payload
# to it first. Losing the forward blanks Orca's view of every claude session.
grep -F 'agent-hooks/claude-statusline.sh' config/statusline/claude-statusline.sh >/dev/null \
    || fail "the claude renderer does not forward its payload to Orca's telemetry sink"
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
# The list spans two lines, so the order is checked on the joined text rather
# than by matching one literal line. agentusage must precede agentsurface (the
# launcher shells its balance contract), agentweb must precede agentbrain
# (whose worker spawns the agentscrape children that ask agentweb's conduit),
# and codex-swap must precede agentusage so its own shim — the one carrying the
# managed codex-multi-auth fork path — wins over the legacy shim agentusage
# still writes.
agent_cli_order=$(tr '\n' ' ' <scripts/install-agent-clis | tr -s ' ')
case "$agent_cli_order" in
    *"for tool in agentwiki agentboard agentsearch agentkeys agentbus \\ agentweb agentscrape agentbrain codex-swap agentusage agentsurface"*) ;;
    *) fail "agent CLI installer changed its tool list or ordering" ;;
esac
# Every checkout with an installer is in the loop; a name missing from it is a
# tool nothing installs.
for expected_tool in agentwiki agentboard agentsearch agentkeys agentweb \
    agentscrape agentbrain agentusage agentsurface; do
    case "$agent_cli_order" in
        *" $expected_tool "*) ;;
        *) fail "agent CLI loop no longer installs $expected_tool" ;;
    esac
done
# shellcheck disable=SC2016 # Match the literal checkout resolution in the script.
grep -F 'agentchats_root="$HOME/code/agentchats"' scripts/install.sh >/dev/null \
    || fail "installer does not own the cass installation call"
# shellcheck disable=SC2016 # Match the literal invocation in the script.
grep -F '"$agentchats_root/scripts/install.sh" --install' scripts/install.sh >/dev/null \
    || fail "installer does not invoke the agentchats contract"

# The Funk boundary, from this side: nothing here may install a desktop cask,
# migrate gh credentials, or grow launchd machinery — those are Funk's.
if grep -Eq -- '--cask' scripts/install.sh scripts/sync-skills; then
    fail "an AgentStart script crossed the Funk boundary: casks are Funk's"
fi
if grep -F 'oauth_token' scripts/install.sh >/dev/null; then
    fail "an AgentStart script crossed the Funk boundary: gh migration is Funk's"
fi
# launchd is now split rather than wholly Funk's: a bare <tool>.<service> label
# is a fleet service and this repository owns it; a reverse-DNS label is the
# machine's and stays with Funk. The boundary that remains is the naming, so
# what is tested is that nothing here installs a machine-shaped service.
if grep -Eq '<string>(com|org|net)\.' config/launchd/*.plist; then
    fail "an AgentStart launch agent used a reverse-DNS label: machine services are Funk's"
fi
# The updater path stays unattended-safe: sync-skills runs every six hours with
# no sudo and no service restarts, so it must never reach launchd.
if grep -Eq 'launchctl|\.plist' scripts/sync-skills; then
    fail "sync-skills must stay unattended-safe: launchd restarts do not belong there"
fi

# --- the fleet launch agents -------------------------------------------------

[ -x scripts/install-launchagents ] || fail "the launch agent installer is not executable"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-launchagents" --install' scripts/install.sh >/dev/null \
    || fail "installer does not converge the fleet launch agents"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-launchagents" --check' scripts/install.sh >/dev/null \
    || fail "installation plan omits the fleet launch agents"

for template in config/launchd/*.plist; do
    label=$(basename "$template" .plist)
    # The marker is what lets the installer tell its own service from a
    # stranger's, so a template whose marker does not match its own file name
    # would either be refused forever or adopt something it should not.
    grep -Fq "agentstart-installer-owned: $label.v1" "$template" \
        || fail "template is missing or misnaming its ownership marker: $template"
    grep -Fq "<string>$label</string>" "$template" \
        || fail "template Label does not match its file name: $template"
    # Every value is rendered from the manifest; a per-tool token is a leftover
    # from the checkout this service was migrated out of.
    if grep -Eq '__[A-Z]+_(PROGRAM|HOME|PATH|LOG)__' "$template"; then
        fail "template still carries a per-tool token: $template"
    fi
    for required in '<key>Umask</key>' \
        '<key>StandardOutPath</key>' '<key>StandardErrorPath</key>'; do
        grep -Fq "$required" "$template" \
            || fail "template omits $required: $template"
    done
    # Correct at login, by one route or the other: started outright, or started
    # by launchd because the directory it watches is not empty.
    if ! grep -Eq '<key>(RunAtLoad|QueueDirectories)</key>' "$template"; then
        fail "template declares neither RunAtLoad nor QueueDirectories: $template"
    fi
    grep -Fq '<string>__LOG__</string>' "$template" \
        || fail "template does not log through the standard token: $template"
    # A service is either resident or periodic; one of the two must say so.
    if ! grep -Eq '<key>(KeepAlive|StartInterval)</key>' "$template"; then
        fail "template declares neither KeepAlive nor StartInterval: $template"
    fi
    if command -v plutil >/dev/null 2>&1; then
        plutil -lint "$template" >/dev/null || fail "template is not a valid plist: $template"
    fi
    grep -Fq "\"$label|" scripts/install-launchagents \
        || fail "template has no manifest entry: $template"
done

# And the reverse, so a manifest entry can never name a template that is not here.
# The service half of a label may be hyphenated (codex-appserver, process-queue),
# so both halves match hyphens too — a character class that stopped at [a-z] read
# straight past those entries and checked nothing.
while IFS= read -r label; do
    [ -f "config/launchd/$label.plist" ] \
        || fail "manifest names a service with no template: $label"
done < <(sed -n 's/^ *"\([a-z-]*\.[a-z-]*\)|.*/\1/p' scripts/install-launchagents)

printf 'ok\n'
