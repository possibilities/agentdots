#!/bin/bash

set -euo pipefail

check_only=0
script_dir=$(cd -P -- "$(dirname -- "$0")" && pwd)
repo_root=$(cd -P -- "$script_dir/.." && pwd)

usage() {
    cat <<'EOF'
Usage: scripts/install.sh [--install|--check]

Install the AI command-line tools, harness configuration, and agent skills
owned by Agentdots. Funk's ./install invokes this after converging Homebrew
and the AI desktop applications; it is also safe to run standalone.

Options:
  --install  Install or upgrade everything
  --check    Print the installation plan without changing the system
EOF
}

die() {
    printf 'Agentdots installer: %s\n' "$*" >&2
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
# that Funk's zsh package owns. Running it in its own session leaves it with no
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

# Agentdots owns the shared home guidance file: ~/AGENTS.md links at
# prompts/AGENTS.md, which stays deliberately empty — global advice belongs
# in the extension prompts below, rendered into the collab and build skills,
# not in a file loaded into every session. Claude Code reads only CLAUDE.md,
# and Codex skips empty guidance files, so that home file is invisible to
# both CLIs outside sessions whose working directory sits under the home
# directory; link each CLI's global guidance location at it so future
# guidance has a delivery path. An independent non-symlink file with content
# at any of the three locations is preserved and reported — the same
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

    for target in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
        if [ ! -L "$target" ] && [ -s "$target" ]; then
            die "refusing to replace independent guidance: $target"
        fi
        mkdir -p "$(dirname "$target")"
        ln -sfn "$home_guidance" "$target"
        cmp -s "$source" "$target" \
            || die "linked guidance does not resolve to $source: $target"
    done
}

# llm's model configuration: one file linked into the application-support
# directory llm itself writes into (keys, logs), so the link is per-file and
# an independent non-symlink file with content is preserved and reported.
link_llm_config() {
    local source="$repo_root/config/llm/extra-openai-models.yaml"
    local target_dir="$HOME/Library/Application Support/io.datasette.llm"
    local target="$target_dir/extra-openai-models.yaml"

    [ -s "$source" ] \
        || die "llm model configuration source is missing or empty: $source"
    if [ ! -L "$target" ] && [ -s "$target" ]; then
        die "refusing to replace independent llm configuration: $target"
    fi
    mkdir -p "$target_dir"
    ln -sfn "$source" "$target"
    cmp -s "$source" "$target" \
        || die "linked llm configuration does not resolve to $source: $target"
}

# The voice orchestrator's doctrine and server configuration are fleet
# guidance, so Agentdots owns them: prompts/agentvoice/ is the source of
# truth and ~/.config/agentvoice is per-file links into this checkout. The
# filenames — ORCHESTRATOR.md, ORCHESTRATOR_SESSION_START.md, server.json —
# are AgentVoice's discovery contract (~/code/agentvoice/docs/field-guide.md
# documents every lever); a file it does not recognize primes nothing. The
# AgentVoice server reads them once at boot, so changes apply on its next
# start. Per-file links, never the directory: the target also holds files
# this checkout does not own.
link_agentvoice_config() {
    local config_dir="$HOME/.config/agentvoice"
    local name
    local source
    local target

    for name in ORCHESTRATOR.md ORCHESTRATOR_SESSION_START.md server.json; do
        source="$repo_root/prompts/agentvoice/$name"
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

# The operator extension prompts are cross-project guidance, so Agentdots
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
  brew install or upgrade llm  # an AI CLI, so Agentdots' outright — moved out of Funk's Brewfile
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
  ln -sfn prompts/agentguidance/{SYSTEM,GUIDELINES,TOOLS}.md into ~/.config/agentguidance  # the extension prompts agentguidance renders against
  ln -sfn prompts/agentvoice/{ORCHESTRATOR.md,ORCHESTRATOR_SESSION_START.md,server.json} into ~/.config/agentvoice  # the voice orchestrator's doctrine, read at server boot
  ln -sfn config/llm/extra-openai-models.yaml into ~/Library/Application Support/io.datasette.llm  # llm's model configuration

Related, not run by --install:
  scripts/configure-orca  # apply the Orca settings overlay; Funk's ./install runs it via funk configure-orca

Agent skills:
  npx --yes skills add https://github.com/vercel-labs/skills --agent codex claude-code pi --skill find-skills --global --yes
  npx --yes skills add https://github.com/anthropics/skills --agent codex claude-code pi --skill frontend-design --global --yes
  npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code pi --skill web-design-guidelines --global --yes
  npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code pi --skill vercel-react-best-practices --global --yes
  npx --yes skills add https://github.com/vercel/ai --agent codex claude-code pi --skill ai-sdk --global --yes
  npx --yes skills add https://github.com/vercel/ai-elements --agent codex claude-code pi --skill ai-elements --global --yes
  npx --yes skills add https://github.com/shadcn/ui --agent codex claude-code pi --skill shadcn --global --yes
  npx --yes skills add https://github.com/vercel-labs/native --agent codex claude-code pi --skill native-sdk --global --yes
EOF
    "$script_dir/sync-skills" --check
    if [ -f "$HOME/code/agentchats/scripts/install.sh" ]; then
        "$HOME/code/agentchats/scripts/install.sh" --check
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

# Funk already owns these PATH entries in its Stow-managed zsh configuration.
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

# Pi requires Node.js 22.19 or newer. Funk initializes the pinned NVM default
# before its Brewfile converges; load that default into this subprocess so
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
# audio device, and Funk's Brewfile alone cannot guarantee the toolchain is
# present in a session that only runs this script (intentional duplicate of
# that Brewfile).
printf 'Installing or upgrading Zig for Native SDK packaging (intentional duplicate of Funk'\''s Brewfile).\n'
install_or_upgrade_formula zig

# llm is an AI CLI, so it is Agentdots' outright — moved out of Funk's
# Brewfile rather than duplicated from it. Its model configuration is linked
# from config/llm below.
printf 'Installing or upgrading the llm CLI.\n'
install_or_upgrade_formula llm

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

printf 'Linking the shared agent guidance for Claude Code and Codex.\n'
link_agent_guidance

printf 'Linking the operator extension prompts into ~/.config/agentguidance.\n'
link_extension_prompts

printf 'Linking the AgentVoice doctrine into ~/.config/agentvoice.\n'
link_agentvoice_config

printf 'Linking the llm model configuration.\n'
link_llm_config

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

printf 'Verifying the installed Native SDK agent documentation helpers.\n'
native skills list >/dev/null

# The AgentVoice voice CLI is linked editable from its own checkout by its
# cli:install contract (dependencies, sox, a global bun link). Agentdots only
# invokes it; a machine without the checkout skips inside the script, so only
# a present-but-broken checkout fails here.
agentvoice_cli_status=0
"$script_dir/install-agentvoice-cli" || agentvoice_cli_status=$?
if [ "$agentvoice_cli_status" -ne 0 ]; then
    printf 'Agentdots installer: AgentVoice CLI install failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or scripts/install-agentvoice-cli.\n' \
        "$agentvoice_cli_status" >&2
    exit "$agentvoice_cli_status"
fi

# The agentwiki, agentboard, and agentsearch CLIs install by their own hardened
# contract (frozen deps, ~/.local/bin symlink, deployed-SHA receipt). Agentdots
# only invokes it; a machine without a checkout skips inside the script, so
# only a present-but-broken checkout fails here.
agent_clis_status=0
"$script_dir/install-agent-clis" || agent_clis_status=$?
if [ "$agent_clis_status" -ne 0 ]; then
    printf 'Agentdots installer: agent CLIs install failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or scripts/install-agent-clis.\n' \
        "$agent_clis_status" >&2
    exit "$agent_clis_status"
fi

# cass — the coding-agent session search CLI — installs by the agentchats
# checkout's own contract: the upstream checksummed release plus the index
# over the local Claude Code, Codex, and Pi session stores. Its chats skill
# ships through the agent* checkout skill scan like every other tool's. A
# machine without the checkout skips, like the agent CLIs above; a present
# checkout that fails to install is a real error.
agentchats_root="$HOME/code/agentchats"
if [ -f "$agentchats_root/scripts/install.sh" ]; then
    agentchats_status=0
    "$agentchats_root/scripts/install.sh" --install || agentchats_status=$?
    if [ "$agentchats_status" -ne 0 ]; then
        printf 'Agentdots installer: cass install failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or %s/scripts/install.sh --install.\n' \
            "$agentchats_status" "$agentchats_root" >&2
        exit "$agentchats_status"
    fi
else
    printf 'Agentdots installer: no agentchats checkout at %s; skipping cass.\n' \
        "$agentchats_root"
fi

# Every agent tool publishes its skills by convention — skills/<name>/
# inside a checkout named agent* — so they are discovered rather than listed
# here, and a tool that adds or renames a skill needs no edit in this file.
# That includes this checkout's own skills and agentguidance's, whose
# post-sync hook re-renders the templates the scan ships against the
# operator extension prompts linked above. sync-skills also refreshes the
# Orca harness skills; the Orca application itself is Funk's, installed as
# a Homebrew cask beside the other AI desktop applications.
"$script_dir/sync-skills"
