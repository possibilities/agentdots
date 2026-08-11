# AgentStart agent guidance

## Repository context

- `~/code/agentstart` owns AI-toolchain installation for this machine. The
  machine layer itself — Homebrew, Stow, launchd, macOS settings, account
  migration — is owned elsewhere and is not this repository's concern; its
  installer invokes this checkout, and that call is the whole relationship.
  When a change straddles the two, the scope test decides: depended on by or
  deeply related to the fleet → here; the machine itself → not here. Every
  path here resolves from `$HOME` — nothing may assume a particular account
  name.
- The fleet lives beside this checkout: every `~/code/agent*` checkout
  without exception — including `~/code/agentguidance`, the general guidance
  skills and their renderer — plus `~/code/codex-swap`, the first-party
  account-swapping launcher for codex and pi. Each fleet repo owns its own
  hardened installer and exports its own skills; AgentStart invokes
  contracts, it does not reach inside — but it decides that every
  one of them is installed. `install-agent-clis` runs each checkout's own
  installer, and `config/launchd/` defines every fleet service, because a
  service with two owners has them racing to render it. A fleet checkout
  ships the code; this repository decides that it is present and when it
  runs. Nothing outside this repository installs a fleet component.
- `claude-swap` is the one fleet dependency that is not ours. Upstream is a
  third-party project, so the machine currently runs a patched fork
  (`possibilities/claude-swap`, `main`) cloned to `~/src/claude-swap` under
  the `~/src` convention for other people's code. Agentusage's
  `scripts/install-providers.sh` provisions it and refuses a checkout whose
  fork remote is not ours. This is temporary: once the outstanding PRs land
  upstream, the fork collapses back to a plain upstream install, and that
  change belongs in agentusage, not here. Neither swap tool goes in
  `install-agent-clis` — both arrive through agentusage's installer, which
  is why that loop runs agentusage before agentsurface.
- Every fleet repo's `AGENTS.md` ends with the same "The fleet" section
  pointing back here: the skills scan and its cadence, the fleet-map rule,
  and agentguidance as the home of general doctrine. Changing any of those
  conventions updates that section in every fleet checkout in the same
  change — the uniformity is what keeps twelve copies maintainable.

## Fix-forward installation

Every durable AI-stack change belongs in this repository and converges by
rerunning `scripts/install.sh --install`. Do not hand-configure the live
machine, and do not grow a second installer or synchronization path here or
in `~/code/agentguidance`.

The external interface is exactly `scripts/install.sh` (`--install`,
`--check`), `scripts/sync-skills` (`--check`), and
`scripts/install-agentsurface-shims`. The machine's installer and scheduled
updater call these by path with fixed semantics: a missing optional fleet
checkout is a skip inside the script, a present-but-broken one fails, and
the updater path (`sync-skills`) must stay unattended-safe — no sudo, no
uninstalls, no application restarts. That caller's own test suite greps
these scripts, so renaming or resemanticizing them breaks it.

Where things go:

- A new AI tool, harness configuration, npm global, or external skill pack:
  `scripts/install.sh`, with its plan line in the `--check` output and
  assertions in `tests/validate.sh`.
- A new fleet tool: add the checkout to the `install-agent-clis` loop if it
  has a CLI installer, and note the ordering constraint in the comment there
  if it has one. The `agent*` skills scan needs nothing. A loop member's
  installer must be rerunnable, because a present checkout that fails stops
  the whole install.
- A new long-running fleet service: a template in `config/launchd/`, an
  entry in the manifest at the top of `scripts/install-launchagents`, and
  assertions in `tests/validate.sh`. `config/launchd/README.md` is the
  contract — what every service shares and what is deliberately
  per-service. Labels are bare `<tool>.<service>`; a reverse-DNS label is a
  machine service and does not belong here.
- A statusline change: `config/statusline/`, converged by
  `scripts/install-statusline`. One bar in three harness idioms, because
  that is all the harnesses offer — claude runs a render command per frame,
  pi replaces its footer from an extension, and codex draws its own bar and
  only lets an operator choose and order a fixed set of items. A field
  added to one renderer belongs in the others wherever they can know it;
  each renderer's comments record what its harness cannot.
- An operator extension prompt edit: `prompts/agentguidance/`, then
  `scripts/install.sh --install` (or wait for the six-hour sync plus the
  next render) so the rendered skills pick it up.
- A cross-project decision that belongs to no single repo: the wiki
  (`agentwiki new`), one page per subject, wikilinked to its neighbours
  and pointed at from wherever it constrains. `tool-advertisement-policy`
  is the standing example.
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
with its agentguidance source template — the same convergence check the
fleet's guidance prescribes. `AGENTS.md` is the canonical guidance file;
`CLAUDE.md` is a symlink to it.
