# AgentDots

[![CI](https://github.com/possibilities/agentdots/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/possibilities/agentdots/actions/workflows/ci.yml)

Agentdots is the AI half of this machine: the installer and home for
everything the agent fleet in `~/code` depends on. Funk owns the machine —
Homebrew, Stow, launchd, macOS settings — and calls into this checkout for
the rest. The boundary rubric is one sentence, recorded with its case law
in the wiki (`agentwiki get funk-boundary`):

> Depended on by, or deeply related to, the agent\* fleet → Agentdots.
> Otherwise → Funk.

This is one operator's machine layer, published as working reference beside
the agent* fleet it installs. It is orderly — contracts, tests, recorded
decisions — and deliberately opinionated: the judgment calls stay in, stated
plainly, rather than generalized away.

If you are not that operator: the platform is macOS, every path resolves from
`$HOME`, and the installers drive sibling checkouts under `~/code` — the
agent* fleet, `agentguidance` for the general skills, and `funk` calling in
from the machine side. A checkout you do not have is a skip, not a failure.
A vendor CLI installs by its own official installer, which reaches the
network. Run `scripts/install.sh --check` to see the whole plan before
believing any of this.

## Layout

- `scripts/` — the installers Funk invokes; the whole external interface.
- `prompts/` — the operator guidance the installer links into the home:
  - `agentguidance/` — the extension prompts `SYSTEM.md`, `GUIDELINES.md`,
    and `TOOLS.md`, which agentguidance renders into the collab and build
    skills. Linked into `~/.config/agentguidance/`.
  - `agentvoice/` — the voice orchestrator's doctrine and `server.json`,
    linked into `~/.config/agentvoice/` and read at server boot.
  - `AGENTS.md` — the deliberately empty shared home guidance at
    `~/AGENTS.md`. Advice belongs in the extension prompts.
- `config/` — AI-tool configuration the installer converges: `orca/` (the
  settings and keybindings overlay `scripts/configure-orca`
  merges — never links — into Orca's live state).
- `skills/` — skills this checkout exports through the agent* scan, like any
  other fleet repo. `fleet/` is the dependency map of the whole ecosystem.
- `tests/validate.sh` — the assertions; run it before committing.

Cross-project decisions and policy live in the wiki, not here: the
`funk-boundary` and `tool-advertisement-policy` pages
(`agentwiki get <slug>`).

## Contracts

Funk relies on exactly these entry points; their paths, flags, and
skip-versus-fail semantics are load-bearing:

- `scripts/install.sh --install` — the whole AI toolchain, each piece by its
  own checkout's contract, skipping checkouts that are absent:

  - Claude Code, Codex, and Pi, by their official installers;
  - Zig (an intentional duplicate of Funk's Brewfile) and `llm`;
  - the pinned `@native-sdk/cli` and `agent-browser` npm globals;
  - the shadcn MCP registration for Codex and Claude Code;
  - the `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` guidance links, and
    the extension prompt links;
  - the external skill packs;
  - the AgentVoice CLI, and the agentwiki, agentboard, agentsearch,
    agentkeys, agentusage, and agentsurface CLIs;
  - the public `possibilities/claude-swap` fork and the codex-swap provider
    shim, through agentusage's installer;
  - cass, and finally `sync-skills`.

  Funk's `./install` calls this and refuses to finish without it. `--check`
  prints the plan without changing anything.
- `scripts/sync-skills` — the cheap convergence path: the Orca harness
  skills (synchronized and verified) plus the agent* checkout skill scan.
  Funk's scheduled updater calls this every six hours. `--check` prints the
  plan.
- `scripts/install-agentsurface-shims` — the balanced-launch shims for bare
  `claude`/`codex`/`pi`; `funk install-agentsurface-shims` delegates here.
- `scripts/configure-orca [--check]` — merges the `config/orca/` overlay
  into Orca's live keybindings and active-profile settings, deferring with
  EX_TEMPFAIL while a divergent Orca runs; `funk configure-orca` delegates
  here and Funk's `./install` invokes it through that delegation.

The AI desktop applications are not here by design: the claude and chatgpt
casks and the Orca cask are Homebrew, so they are Funk's, as is the `gh`
credential migration.

## Working on it

Fix forward. A durable change to the AI stack lands in this repository and
converges by rerunning `scripts/install.sh --install`; never configure the
live machine by hand and call it done. After changing anything here, run:

```sh
tests/validate.sh
```

A new fleet tool usually needs almost no edit here. Name the checkout
`agent*` and export `skills/<name>/SKILL.md`, and the skills scan ships it.
Only a tool with its own CLI installer joins the explicit loop in
`scripts/install-agent-clis`. Whether to advertise it in
`prompts/agentguidance/TOOLS.md` is a separate decision — make it
deliberately, per the `tool-advertisement-policy` wiki page.
