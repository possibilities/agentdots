# Agentdots context

**The fleet** — the agent apps in `~/code` whose checkouts are named
`agent*` — `agentguidance` carries the general skills — plus `cass` from
`agentchats`.
Each fleet repo owns its own hardened installer and exports its own skills;
Agentdots invokes contracts and never reaches inside a sibling checkout.
_Avoid_: suite, monorepo, workspace.

**The boundary rubric** — the one-sentence ownership test between this
repository and Funk: depended on by or deeply related to the fleet →
Agentdots; the machine itself (Homebrew, Stow, launchd, macOS settings,
account migration) → Funk. Recorded with its case law in the wiki
(`agentwiki get funk-boundary`). _Avoid_: split, refactor, migration
(those name the event; the rubric names the rule).

**The toolchain** — everything `scripts/install.sh --install` converges:
harness CLIs, pinned npm globals, MCP registration, guidance links,
extension prompts, and every globally managed skill. The AI *desktop
applications* are not toolchain; they are Homebrew casks and Funk's.
_Avoid_: stack, setup.

**Harness** — an agent CLI a session runs inside: Claude Code, Codex, Pi.
Skills install into harnesses; agentsurface shims balance their bare
launches. _Avoid_: agent (ambiguous with the fleet apps), IDE.

**Extension prompts** — the operator's `SYSTEM.md`, `GUIDELINES.md`, and
`TOOLS.md` under `prompts/agentguidance/`, linked into
`~/.config/agentguidance` and rendered by agentguidance into the
collab/build skills. Their three names are agentguidance's contract; an
unrecognized file renders to nothing. _Avoid_:
config files, dotfiles.

**Advertisement** — a tool's one line in `TOOLS.md` saying when to load its
skill. A line is attention spent in every session and has to earn it; the
policy and its standing decisions live in the wiki
(`agentwiki get tool-advertisement-policy`). _Avoid_: documentation,
listing (an installed, unadvertised tool is still fully documented by its
skill).

**The sync path** — `scripts/sync-skills`: the unattended-safe convergence
Funk's updater runs every six hours — Orca harness skills plus the
participant scan, no downloads beyond the skills tool, no elevation, no
restarts. _Avoid_: update, upgrade (binaries never move on this path).

**Participant** — an `agent*` checkout that exports
`skills/<name>/SKILL.md` and is therefore discovered by the scan. A
checkout without one is not misconfigured; it is simply not a participant.
This repository is itself a participant (the `fleet` skill). _Avoid_:
registered, enrolled (there is no registry — the convention is the whole
interface).
