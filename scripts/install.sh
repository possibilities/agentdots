#!/bin/bash

set -euo pipefail

check_only=0
script_dir=$(cd -P -- "$(dirname -- "$0")" && pwd)
repo_root=$(cd -P -- "$script_dir/.." && pwd)

# The fleet root. AGENTSTART_CODE_ROOT relocates it as a unit — the tests point
# it at a fixture tree — but it deliberately does not resolve relative to this
# script: the installer converges the machine, not the checkout it was invoked
# from, and a worktree run must still find the real fleet rather than silently
# skipping every tool.
code_root="${AGENTSTART_CODE_ROOT:-$HOME/code}"

usage() {
    cat <<'EOF'
Usage: scripts/install.sh [--install|--check]

Install the AI command-line tools, harness configuration, and agent skills
owned by AgentStart. The machine's installer invokes this after converging
Homebrew and the AI desktop applications; it is also safe to run standalone.

Options:
  --install  Install or upgrade everything
  --check    Print the installation plan without changing the system
EOF
}

die() {
    printf 'AgentStart installer: %s\n' "$*" >&2
    exit 1
}

find_brew() {
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return
    fi
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    return 1
}

install_official() {
    local name="$1"
    local url="$2"
    local interpreter="$3"
    shift 3

    printf 'Installing %s with its official installer.\n' "$name"
    /usr/bin/curl -fsSL "$url" | "$interpreter" "$@"
}

# Pi's installer reads its prompts from /dev/tty instead of stdin, so redirecting
# input does not make it unattended: run from a terminal it stops on its
# install/reinstall menu and offers to append a PATH line to the shell profile
# that the machine's zsh package owns. Running it in its own session leaves it with no
# controlling terminal, which is exactly the condition its documented
# "No terminal detected; continuing without confirmation" path tests for.
run_without_controlling_terminal() {
    /usr/bin/perl -e '
        use POSIX ();
        my $pid = fork();
        die "fork failed: $!\n" unless defined $pid;
        if ($pid == 0) {
            POSIX::setsid();
            exec { $ARGV[0] } @ARGV or exit 127;
        }
        waitpid($pid, 0);
        exit($? >> 8);
    ' -- "$@"
}

configure_shadcn_mcp() {
    printf 'Configuring the shadcn registry MCP server for Codex.\n'
    codex mcp remove shadcn >/dev/null 2>&1 || true
    codex mcp add shadcn -- npx shadcn@latest mcp

    printf 'Configuring the shadcn registry MCP server for Claude Code.\n'
    claude mcp remove --scope user shadcn >/dev/null 2>&1 || true
    claude mcp add --scope user shadcn -- npx shadcn@latest mcp
}

# AgentStart owns the shared home guidance file: ~/AGENTS.md links at
# prompts/AGENTS.md, which stays deliberately empty — global advice belongs
# in the extension prompts below, rendered into the collab and build skills,
# not in a file loaded into every session. Claude Code reads only CLAUDE.md,
# Codex skips empty guidance files, and pi's designated global slot is
# ~/.pi/agent/AGENTS.md — its startup walk from cwd through every ancestor
# reaches ~/AGENTS.md only for sessions under the home directory, and under
# the home directory it loads both copies, harmless while they are the same
# file. Link each harness's global guidance location at it so future
# guidance has a delivery path. An independent non-symlink file with content
# at any of the four locations is preserved and reported — the same
# conflict rule the guidance file itself prescribes for repositories.
link_agent_guidance() {
    local source="$repo_root/prompts/AGENTS.md"
    local home_guidance="$HOME/AGENTS.md"
    local target

    [ -f "$source" ] \
        || die "shared agent guidance source is missing: $source"

    if [ ! -L "$home_guidance" ] && [ -s "$home_guidance" ]; then
        die "refusing to replace independent guidance: $home_guidance"
    fi
    ln -sfn "$source" "$home_guidance"
    cmp -s "$source" "$home_guidance" \
        || die "linked guidance does not resolve to $source: $home_guidance"

    for target in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"; do
        if [ ! -L "$target" ] && [ -s "$target" ]; then
            die "refusing to replace independent guidance: $target"
        fi
        mkdir -p "$(dirname "$target")"
        ln -sfn "$home_guidance" "$target"
        cmp -s "$source" "$target" \
            || die "linked guidance does not resolve to $source: $target"
    done
}

# The extra model records are retired. Remove only the exact symlink this
# checkout previously created; an independent file or differently-targeted
# symlink belongs to its owner and is left alone.
remove_retired_llm_config() {
    local retired_source="$repo_root/config/llm/extra-openai-models.yaml"
    local target="$HOME/Library/Application Support/io.datasette.llm/extra-openai-models.yaml"

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$retired_source" ]; then
        rm -- "$target"
        printf 'Removed retired AgentStart-owned llm model configuration: %s.\n' "$target"
    elif [ -e "$target" ] || [ -L "$target" ]; then
        printf 'Leaving independent llm model configuration untouched: %s.\n' "$target"
    fi
}


# The voice server configuration is fleet wiring, so AgentStart owns it:
# prompts/agentvoice/server.json is the source of truth. The orchestrator
# doctrine is general agent doctrine: agentguidance renders it into
# ~/.agents/prompts/agentvoice/ — shared orchestrator fragments spliced by
# its post-sync hook — and this installer decides only that AgentVoice
# discovers the result, which is why link_agentvoice_config runs after
# sync-skills has rendered.
# The filenames — ORCHESTRATOR.md, ORCHESTRATOR_SESSION_START.md,
# server.json — are AgentVoice's discovery contract
# (~/code/agentvoice/docs/field-guide.md documents every lever); a file it
# does not recognize primes nothing. The AgentVoice server reads them once
# at boot, so changes apply on its next start — the six-hourly sync may
# re-render doctrine content unattended, and no restart is needed. Per-file
# links, never the directory: the target also holds files this checkout
# does not own.
link_agentvoice_config() {
    local config_dir="$HOME/.config/agentvoice"
    local rendered_dir="$HOME/.agents/prompts/agentvoice"
    local name
    local source
    local target

    for name in ORCHESTRATOR.md ORCHESTRATOR_SESSION_START.md server.json; do
        case "$name" in
        server.json) source="$repo_root/prompts/agentvoice/$name" ;;
        *) source="$rendered_dir/$name" ;;
        esac
        target="$config_dir/$name"
        [ -s "$source" ] \
            || die "AgentVoice doctrine source is missing or empty: $source"
        if [ ! -L "$target" ] && [ -s "$target" ]; then
            die "refusing to replace independent AgentVoice configuration: $target"
        fi
        mkdir -p "$config_dir"
        ln -sfn "$source" "$target"
        cmp -s "$source" "$target" \
            || die "linked AgentVoice configuration does not resolve to $source: $target"
    done
}

# The operator extension prompts are cross-project guidance, so AgentStart
# owns them: prompts/agentguidance/ here is the source of truth, and
# ~/.config/agentguidance is links into this checkout. Agentguidance's
# renderer reads that directory when composing the collab and build skills,
# so these links must exist before its post-sync hook fires in sync-skills.
# The recognized names — SYSTEM.md, GUIDELINES.md, TOOLS.md — are
# agentguidance's contract; an unrecognized file renders to nothing. An
# independent non-symlink file with content is preserved and reported, the
# same conflict rule as the guidance links above.
link_extension_prompts() {
    local config_dir="$HOME/.config/agentguidance"
    local name
    local source
    local target

    for name in SYSTEM.md GUIDELINES.md TOOLS.md; do
        source="$repo_root/prompts/agentguidance/$name"
        target="$config_dir/$name"
        [ -f "$source" ] \
            || die "extension prompt source is missing: $source"
        [ -s "$source" ] \
            || die "extension prompt source is empty: $source"
        if [ ! -L "$target" ] && [ -s "$target" ]; then
            die "refusing to replace independent extension prompt: $target"
        fi
        mkdir -p "$config_dir"
        ln -sfn "$source" "$target"
        cmp -s "$source" "$target" \
            || die "linked extension prompt does not resolve to $source: $target"
    done
}

case "${1:-}" in
    --install)
        ;;
    --check)
        check_only=1
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
[ "$#" -eq 1 ] || {
    usage >&2
    exit 64
}

if [ "$check_only" -eq 1 ]; then
    cat <<'EOF'
Command-line tools:
  curl -fsSL https://claude.ai/install.sh | bash
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
  curl -fsSL https://pi.dev/install.sh | sh  # in its own session, no controlling terminal
  brew install or upgrade zig  # AgentVoice's native duplex audio path builds against it
  brew install or upgrade llm  # an AI CLI, so AgentStart's outright — moved out of the machine's Brewfile
  brew install or upgrade herdr  # the agent terminal multiplexer; homebrew-core, so no tap and no second update path
  herdr integration install claude, codex, and pi  # the harness agent-state hooks, reinstalled every run because a herdr upgrade stales them
  npm install --global @native-sdk/cli@0.7  # the line the native-sdk skill documents
  npm install --global agent-browser@0.33.2  # Agentweb's config.json digest-locks this exact build
  ln -sfn "$(command -v agent-browser)" ~/.local/bin/agent-browser  # the candidate Agentscrape resolves before PATH

Agent documentation:
  codex mcp add shadcn -- npx shadcn@latest mcp
  claude mcp add --scope user shadcn -- npx shadcn@latest mcp
  native skills list

Agent guidance:
  ln -sfn prompts/AGENTS.md ~/AGENTS.md  # deliberately empty; advice belongs in the extension prompts
  ln -sfn ~/AGENTS.md ~/.claude/CLAUDE.md  # Claude Code reads CLAUDE.md, not AGENTS.md
  ln -sfn ~/AGENTS.md ~/.codex/AGENTS.md  # Codex skips empty guidance files
  ln -sfn ~/AGENTS.md ~/.pi/agent/AGENTS.md  # pi's global slot; its cwd walk reaches ~/AGENTS.md only under $HOME
  ln -sfn prompts/agentguidance/{SYSTEM,GUIDELINES,TOOLS}.md into ~/.config/agentguidance  # the extension prompts agentguidance renders against
  ln -sfn prompts/agentvoice/server.json into ~/.config/agentvoice  # the voice server configuration, read at server boot
  ln -sfn ~/.agents/prompts/agentvoice/{ORCHESTRATOR.md,ORCHESTRATOR_SESSION_START.md} into ~/.config/agentvoice  # the voice orchestrator's doctrine; agentguidance renders it, so this links after sync-skills
  remove AgentStart-owned ~/Library/Application Support/io.datasette.llm/extra-openai-models.yaml symlink  # its extra model records are obsolete
  remove ownership-verified AgentSurface, AgentBus, and Orca harness integrations
  npx --yes skills remove --global --yes bus orca-cli orchestration computer-use  # retired skills; full install only

Agent skills:
  npx --yes skills add https://github.com/vercel-labs/skills --agent codex claude-code pi --skill find-skills --global --yes
  npx --yes skills add https://github.com/anthropics/skills --agent codex claude-code pi --skill frontend-design --global --yes
  npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code pi --skill web-design-guidelines --global --yes
  npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code pi --skill vercel-react-best-practices --global --yes
  npx --yes skills add https://github.com/vercel/ai --agent codex claude-code pi --skill ai-sdk --global --yes
  npx --yes skills add https://github.com/vercel/ai-elements --agent codex claude-code pi --skill ai-elements --global --yes
  npx --yes skills add https://github.com/shadcn/ui --agent codex claude-code pi --skill shadcn --global --yes
  npx --yes skills add https://github.com/vercel-labs/native --agent codex claude-code pi --skill native-sdk --global --yes
  herdr --skill, rendered to ~/.local/share/agentstart/herdr-skill/skills/herdr/SKILL.md  # the surface skill ships inside the binary, so it converges with the formula, never a checkout
  npx --yes skills add ~/.local/share/agentstart/herdr-skill --agent codex claude-code pi --skill herdr --global --yes
EOF
    "$script_dir/install-statusline" --check
    "$script_dir/install-launchagents" --check
    "$script_dir/sync-skills" --check
    if [ -f "$code_root/agentchats/scripts/install.sh" ]; then
        "$code_root/agentchats/scripts/install.sh" --check
    fi
    exit 0
fi

[ "$(uname -s)" = Darwin ] || die "macOS is required"
[ "$(id -u)" -ne 0 ] || die "run as the target user, not root"

brew_bin=$(find_brew) || die "Homebrew is not installed"
brew_prefix=$("$brew_bin" --prefix)
brew_owner=$(stat -f '%Su' "$brew_prefix")
[ "$brew_owner" = "$(id -un)" ] \
    || die "Homebrew prefix $brew_prefix is owned by $brew_owner, not $(id -un)"

# The machine already owns these PATH entries in its Stow-managed zsh config.
# Supplying them here prevents vendor installers from appending equivalent lines
# to shell startup files during this run.
original_path=$PATH
export PATH="$HOME/.local/bin:$brew_prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin:$original_path"

install_or_upgrade_formula() {
    local formula="$1"

    if "$brew_bin" list --formula --versions "$formula" >/dev/null 2>&1; then
        "$brew_bin" upgrade --formula --yes "$formula"
    else
        "$brew_bin" install --formula --yes "$formula"
    fi
    "$brew_bin" list --formula --versions "$formula" >/dev/null \
        || die "Homebrew formula verification failed: $formula"
}

export HOMEBREW_NO_ASK=1

install_official "Claude Code" \
    https://claude.ai/install.sh \
    /bin/bash

printf 'Installing Codex CLI with its official installer.\n'
/usr/bin/curl -fsSL https://chatgpt.com/codex/install.sh \
    | CODEX_NON_INTERACTIVE=1 /bin/sh

# Pi requires Node.js 22.19 or newer. The machine initializes the pinned NVM
# default before its Brewfile converges; load that default into this subprocess so
# Pi's official installer can use it.
nvm_script="$brew_prefix/opt/nvm/nvm.sh"
if [ -s "$nvm_script" ]; then
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1090
    source "$nvm_script" --no-use
    if nvm version default >/dev/null 2>&1; then
        nvm use --silent default
    fi
fi

printf 'Installing Pi with its official installer.\n'
/usr/bin/curl -fsSL https://pi.dev/install.sh \
    | run_without_controlling_terminal /bin/sh

# Zig builds Native SDK applications and AgentVoice's opt-in native duplex
# audio device, and the machine's Brewfile alone cannot guarantee it is
# present in a session that only runs this script (intentional duplicate of
# that Brewfile).
printf 'Installing or upgrading Zig for Native SDK packaging (intentional duplicate of the machine'\''s Brewfile).\n'
install_or_upgrade_formula zig

# llm is an AI CLI, so it is AgentStart's outright — moved out of the
# machine's Brewfile rather than duplicated from it.
printf 'Installing or upgrading the llm CLI.\n'
install_or_upgrade_formula llm

# herdr is the terminal multiplexer agent sessions run inside — an AI tool by
# the boundary rubric, so AgentStart's, not the machine's. It ships in
# homebrew-core, so no tap is needed and the formula is the only update path:
# `herdr update` belongs to the direct install this deliberately does not use,
# and a second updater is the synchronization path this repository forbids.
printf 'Installing or upgrading herdr.\n'
install_or_upgrade_formula herdr

# The harness integrations wire each agent into herdr — pi's is a lifecycle
# authority, while claude's and codex's report session identity (for native
# restore) and deliberately leave lifecycle to herdr's screen detection.
# They install after the three harness CLIs above, because each one
# writes inside a harness's own configuration directory that those installers
# create. Reinstalled unconditionally on every run: a herdr upgrade can leave
# an integration stale — the reason `herdr integration status --outdated-only`
# exists — and reinstalling is how it converges. Unlike the harness
# configuration this installer writes itself, these files belong to herdr, so
# ownership and conflict rules are its installer's to enforce, exactly as they
# are for a fleet checkout's own installer. The harnesses are the three the
# fleet runs; herdr supports more, and adding one here is a deliberate edit.
install_herdr_integrations() {
    local harness

    for harness in claude codex pi; do
        printf 'Installing the herdr %s integration.\n' "$harness"
        herdr integration install "$harness" \
            || die "herdr integration install failed: $harness"
    done
}

install_herdr_integrations

command -v npm >/dev/null 2>&1 || die "npm is required to install the Native SDK CLI"

# The native-sdk skill documents the 0.7 line and its agent helpers are
# version-matched to it, so pin that line here instead of tracking latest.
native_sdk_version=0.7
printf 'Installing the Native SDK CLI %s and its version-matched agent helpers.\n' \
    "$native_sdk_version"
npm install --global "@native-sdk/cli@$native_sdk_version"

# agent-browser is the browser Agentscrape and Agentweb both drive, and it is
# pinned rather than tracked: Agentweb records a SHA-256 digest and version lock
# in its config.json and refuses to launch a browser whose binary does not match,
# so an unannounced upgrade here would take Agentweb's browser offline until an
# operator re-locked it. Raising this version means re-locking that config too.
agent_browser_version=0.33.2
printf 'Installing agent-browser %s for Agentscrape and Agentweb.\n' \
    "$agent_browser_version"
npm install --global "agent-browser@$agent_browser_version"

# Publish the stable candidate Agentscrape resolves before falling back to PATH.
# Both consumers run under launchd, whose minimal PATH never reaches a tool
# installed under a Node version manager, and the version-manager path itself
# changes with every Node upgrade. This link is the one address that does not.
link_agent_browser() {
    local source
    local target="$HOME/.local/bin/agent-browser"

    source=$(command -v agent-browser) \
        || die "agent-browser is not on PATH after installing it"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        die "refusing to replace independent file: $target"
    fi
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$source" "$target"
    [ -x "$target" ] || die "linked agent-browser is not executable: $target"
}

printf 'Linking the stable agent-browser candidate into ~/.local/bin.\n'
link_agent_browser

command -v npx >/dev/null 2>&1 || die "npx is required to install agent skills"

configure_shadcn_mcp

printf 'Linking the shared agent guidance for Claude Code, Codex, and pi.\n'
link_agent_guidance

printf 'Linking the operator extension prompts into ~/.config/agentguidance.\n'
link_extension_prompts

printf 'Removing the retired llm model configuration if AgentStart owns it.\n'
remove_retired_llm_config

printf 'Removing retired AgentSurface, AgentBus, and Orca harness integrations.\n'
retired_integrations_status=0
"$script_dir/remove-retired-integrations" || retired_integrations_status=$?
if [ "$retired_integrations_status" -ne 0 ]; then
    printf 'AgentStart installer: retired integration cleanup failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or scripts/remove-retired-integrations.\n' \
        "$retired_integrations_status" >&2
    exit "$retired_integrations_status"
fi

# This uninstall belongs only to the explicit full installer. sync-skills is
# the six-hour unattended path and remains additive: it never uninstalls a
# skill that may be in use by a live session.
printf 'Removing the retired AgentBus and Orca skills.\n'
npx --yes skills remove --global --yes \
    bus orca-cli orchestration computer-use

# The fleet statusline is harness configuration in each CLI's own idiom, so
# it converges here rather than from a launcher. It runs after the three CLIs
# are installed above: the codex step edits config.toml, which the Codex
# installer creates.
"$script_dir/install-statusline" --install

printf 'Installing the global skill discovery helper.\n'
npx --yes skills add https://github.com/vercel-labs/skills \
    --agent codex claude-code pi \
    --skill find-skills \
    --global --yes

printf 'Installing the globally managed design skills.\n'
npx --yes skills add https://github.com/anthropics/skills \
    --agent codex claude-code pi \
    --skill frontend-design \
    --global --yes
npx --yes skills add https://github.com/vercel-labs/agent-skills \
    --agent codex claude-code pi \
    --skill web-design-guidelines \
    --global --yes

printf 'Installing Vercel React engineering guidance.\n'
npx --yes skills add https://github.com/vercel-labs/agent-skills \
    --agent codex claude-code pi \
    --skill vercel-react-best-practices \
    --global --yes

printf 'Installing the official Vercel AI SDK and AI Elements skills.\n'
npx --yes skills add https://github.com/vercel/ai \
    --agent codex claude-code pi \
    --skill ai-sdk \
    --global --yes
npx --yes skills add https://github.com/vercel/ai-elements \
    --agent codex claude-code pi \
    --skill ai-elements \
    --global --yes

printf 'Installing the official shadcn skill.\n'
npx --yes skills add https://github.com/shadcn/ui \
    --agent codex claude-code pi \
    --skill shadcn \
    --global --yes

printf 'Installing the Native SDK discovery skill.\n'
npx --yes skills add https://github.com/vercel-labs/native \
    --agent codex claude-code pi \
    --skill native-sdk \
    --global --yes

# The surface skill — herdr is the orchestrator doctrine's reference launch
# surface — ships inside the herdr binary (`herdr --skill`), so the installed
# skill converges with the formula on every run, exactly like the harness
# integrations above, and never tracks the GitHub head: the formula is
# herdr's one update path, and the skill follows it. The rendered pack lives
# in a managed state root shaped like a checkout (skills/herdr/) so the same
# `skills add` mechanism ships it globally. Deliberately not advertised in
# TOOLS.md: a role skill is named by the orchestrator doctrine, not by the
# always-on advertisement surface (the tool-advertisement-policy wiki page).
install_herdr_skill() {
    local pack_root="$HOME/.local/share/agentstart/herdr-skill"
    local skill_dir="$pack_root/skills/herdr"

    mkdir -p "$skill_dir"
    herdr --skill >"$skill_dir/SKILL.md" \
        || die "rendering the herdr skill from the installed binary failed"
    [ -s "$skill_dir/SKILL.md" ] \
        || die "the installed herdr rendered an empty skill"
    npx --yes skills add "$pack_root" \
        --agent codex claude-code pi \
        --skill herdr \
        --global --yes
}

printf 'Installing the herdr surface skill from the installed binary.\n'
install_herdr_skill

printf 'Verifying the installed Native SDK agent documentation helpers.\n'
native skills list >/dev/null

# The AgentVoice voice CLI is linked editable from its own checkout by its
# cli:install contract (dependencies, sox, a global bun link). AgentStart only
# invokes it; a machine without the checkout skips inside the script, so only
# a present-but-broken checkout fails here.
agentvoice_cli_status=0
"$script_dir/install-agentvoice-cli" || agentvoice_cli_status=$?
if [ "$agentvoice_cli_status" -ne 0 ]; then
    printf 'AgentStart installer: AgentVoice CLI install failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or scripts/install-agentvoice-cli.\n' \
        "$agentvoice_cli_status" >&2
    exit "$agentvoice_cli_status"
fi

# The fleet CLIs install by their own hardened
# contract (frozen deps, ~/.local/bin symlink, deployed-SHA receipt). AgentStart
# only invokes it; a machine without a checkout skips inside the script, so
# only a present-but-broken checkout fails here.
agent_clis_status=0
"$script_dir/install-agent-clis" || agent_clis_status=$?
if [ "$agent_clis_status" -ne 0 ]; then
    printf 'AgentStart installer: agent CLIs install failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or scripts/install-agent-clis.\n' \
        "$agent_clis_status" >&2
    exit "$agent_clis_status"
fi

# cass — the coding-agent session search CLI — installs by the agentchats
# checkout's own contract: the upstream checksummed release plus the index
# over the local Claude Code, Codex, and Pi session stores. Its chats skill
# ships through the agent* checkout skill scan like every other tool's. A
# machine without the checkout skips, like the agent CLIs above; a present
# checkout that fails to install is a real error.
agentchats_root="$code_root/agentchats"
if [ -f "$agentchats_root/scripts/install.sh" ]; then
    agentchats_status=0
    "$agentchats_root/scripts/install.sh" --install || agentchats_status=$?
    if [ "$agentchats_status" -ne 0 ]; then
        printf 'AgentStart installer: cass install failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or %s/scripts/install.sh --install.\n' \
            "$agentchats_status" "$agentchats_root" >&2
        exit "$agentchats_status"
    fi
else
    printf 'AgentStart installer: no agentchats checkout at %s; skipping cass.\n' \
        "$agentchats_root"
fi

# The fleet's long-running services. This runs after every CLI above, because
# a service is only installed once the binary it supervises exists — a tool
# that is absent is skipped, exactly like its checkout was. The fleet
# checkouts ship the code; this repository decides when it runs. The machine
# layer keeps its own services, which are the reverse-DNS labels.
printf 'Installing the fleet launch agents.\n'
"$script_dir/install-launchagents" --install

# Every agent tool publishes its skills by convention — skills/<name>/
# inside a checkout named agent* — so they are discovered rather than listed
# here, and a tool that adds or renames a skill needs no edit in this file.
# That includes this checkout's own skills and agentguidance's, whose
# post-sync hook re-renders the templates the scan ships against the
# operator extension prompts linked above.
"$script_dir/sync-skills"

# The sync above is where agentguidance renders the orchestrator doctrine,
# so only now can it be linked where the server discovers it.
printf 'Linking the AgentVoice doctrine into ~/.config/agentvoice.\n'
link_agentvoice_config
