# AgentStart

[![CI](https://github.com/possibilities/agentstart/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/possibilities/agentstart/actions/workflows/ci.yml)

AgentStart is the AI half of this machine: the installer and home for
everything the agent fleet in `~/code` depends on. The machine layer —
Homebrew, Stow, launchd, macOS settings — is owned separately and calls into
this checkout for the rest. The boundary rubric is one sentence:

> Depended on by, or deeply related to, the agent\* fleet → AgentStart.
> Otherwise → the machine layer, and not this repository's concern.

This is one operator's machine layer, published as working reference beside
the agent* fleet it installs. It is orderly — contracts, tests, recorded
decisions — and deliberately opinionated: the judgment calls stay in, stated
plainly, rather than generalized away.

If you are not that operator: the platform is macOS, every path resolves from
`$HOME`, and the installers drive sibling checkouts under `~/code` — the
agent* fleet and `agentguidance` for the general skills, with the machine's
own installer calling in. A checkout you do not have is a skip, not a
failure.
A vendor CLI installs by its own official installer, which reaches the
network. Run `scripts/install.sh --check` to see the whole plan before
believing any of this.

## Layout

- `scripts/` — the installers the machine invokes; the whole external
  interface.
- `prompts/` — the operator guidance the installer links into the home:
  - `agentguidance/` — the extension prompts `SYSTEM.md`, `GUIDELINES.md`,
    and `TOOLS.md`, which agentguidance renders into the collab and build
    skills. Linked into `~/.config/agentguidance/`.
  - `agentvoice/` — the voice orchestrator's doctrine and `server.json`,
    linked into `~/.config/agentvoice/` and read at server boot.
  - `AGENTS.md` — the deliberately empty harness guidance source, linked
    directly into the Claude Code, Codex, and Pi global slots. Advice belongs
    in the extension prompts.
- `config/` — harness configuration, the Herdr/Tinty theme integration, and
  the launchd templates for fleet services AgentStart owns.
- `skills/` — skills this checkout exports through the agent* scan, like any
  other fleet repo. `fleet/` is the dependency map of the whole ecosystem.
- `tests/validate.sh` — the assertions; run it before committing.

Cross-project decisions and policy live in the wiki, not here — the
`tool-advertisement-policy` page (`agentwiki get <slug>`).

## Contracts

The machine's installer relies on exactly these entry points; their paths,
flags, and skip-versus-fail semantics are load-bearing:

- `scripts/install.sh --install` — the whole AI toolchain, each piece by its
  own checkout's contract, skipping checkouts that are absent:

  - Claude Code, Codex, and Pi, by their official installers;
  - Zig (an intentional duplicate of the machine's Brewfile) and `llm`;
  - Tinty, its Herdr templates, and the generated live Herdr config;
  - the pinned `@native-sdk/cli` and `agent-browser` npm globals;
  - the shadcn MCP registration for Codex and Claude Code;
  - the `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` guidance links, and
    the extension prompt links;
  - the external skill packs;
  - the AgentVoice CLI, and the agentwiki, agentboard, agentsearch,
    agentkeys, codex-swap, agentusage, and agentlaunch CLIs;
  - the public `possibilities/claude-swap` fork and the codex-swap provider
    shim, through agentusage's installer;
  - ownership-verified cleanup of the retired AgentSurface, AgentBus, and Orca
    harness integrations and skills;
  - cass, the fleet launch agents, and finally `sync-skills`.

  The machine's installer calls this and refuses to finish without it.
  `--check` prints the plan without changing anything.
- `scripts/sync-skills` — the cheap convergence path: the agent* checkout
  skill scan. The scheduled updater calls this every six hours. It never
  uninstalls skills or restarts services. `--check` prints the plan.
- `scripts/install-agentlaunch-shims` — the balanced-launch shims for bare
  `claude`/`codex`/`pi`; the machine's wrapper of the same name delegates
  here.
AI desktop applications are not here by design: the claude and chatgpt casks
belong to the machine layer, as does the `gh` credential migration.

## Herdr themes

AgentStart owns Herdr's behavior config and composes it with the last palette
Tinty applied. The live `~/.config/herdr/config.toml` is generated and checked
with `herdr config check` before replacement; the palette itself stays under
`~/.local/state/agentstart`, and the hundreds of built theme files stay under
`~/.local/share/agentstart`. Neither belongs in Git.

Inside Herdr, `prefix+[` applies the previous theme and `prefix+]` the next,
wrapping across every Base16, Base24, and Tinted8 scheme from `tinty list`.
The same operations are available as `herdr-tinty previous` and
`herdr-tinty next`. Use `tinty gallery` to browse visually or
`tinty apply <scheme-id>` to jump directly; Tinty's hook validates, rewrites,
and live-reloads Herdr without changing Herdr itself. A successful palette
change also shows a silent system notification with the scheme name. On macOS,
Herdr delivers it through `terminal-notifier` when available.

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
