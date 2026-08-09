# Agentdots agent guidance

## Repository context

- `~/code/agentdots` owns AI-toolchain installation for this machine. Funk
  (`~/code/funk`) owns the machine itself and invokes this checkout; the
  rubric and its case law live in the wiki (`agentwiki get funk-boundary`).
  When a change straddles the boundary, decide with the rubric, then record
  the call in that page if it sets precedent. Every path here resolves from
  `$HOME` — nothing may assume a particular account name.
- The fleet lives beside this checkout: `~/code/agent*` plus `~/code/arthack`
  (personal skills) and `~/code/funk`. Each fleet repo owns its own hardened
  installer and exports its own skills; Agentdots invokes contracts, it does
  not reach inside.

## Fix-forward installation

Every durable AI-stack change belongs in this repository and converges by
rerunning `scripts/install.sh --install`. Do not hand-configure the live
machine, and do not grow a second installer or synchronization path here,
in Funk, or in `~/code/arthack`.

The external interface is exactly `scripts/install.sh` (`--install`,
`--check`), `scripts/sync-skills` (`--check`), and
`scripts/install-agentsurface-shims`. Funk's `./install` and scheduled
updater call these by path with fixed semantics: a missing optional fleet
checkout is a skip inside the script, a present-but-broken one fails, and
the updater path (`sync-skills`) must stay unattended-safe — no sudo, no
uninstalls, no application restarts. Funk's own test suite greps these
scripts, so renaming or resemanticizing them is a two-repository change.

Where things go:

- A new AI tool, harness configuration, npm global, or external skill pack:
  `scripts/install.sh`, with its plan line in the `--check` output and
  assertions in `tests/validate.sh`.
- A new fleet tool: usually nothing — the `agent*` skills scan and the
  `install-agent-clis` loop are conventions. Add the checkout to the loop
  only if it has a CLI installer.
- An operator extension prompt edit: `prompts/arthack/`, then
  `scripts/install.sh --install` (or wait for the six-hour sync plus the
  next render) so the rendered skills pick it up.
- A cross-project decision that belongs to no single repo: the wiki
  (`agentwiki new`), one page per subject, wikilinked to its neighbours
  and pointed at from wherever it constrains. `funk-boundary` and
  `tool-advertisement-policy` are the standing examples.
- A change in who calls what between fleet apps: update the map the
  `fleet` skill serves (`skills/fleet/MAP.md`) in the same change.

## Skills

This checkout participates in the same convention it administers: skills
under `skills/<name>/SKILL.md` ship globally through the scan in
`scripts/sync-skills`. The `fleet` skill is the dependency map of the
ecosystem; its `MAP.md` claims to be current, so a stale edge there is a
bug, not a doc nit.

## Validation

```sh
tests/validate.sh
```

After changing installation behavior, also run
`scripts/install.sh --install` and compare the installed `collab` manifest
with its Art Hack source manifest — the same convergence check Funk's
guidance prescribes. `AGENTS.md` is the canonical guidance file; `CLAUDE.md`
is a symlink to it.
