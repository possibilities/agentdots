# The fleet map

Every known dependency between the agent apps in `~/code`, with evidence.
Four kinds of edge:

- **calls** (solid): a runtime subprocess invocation of another tool's CLI.
  Breaking the callee's flags or output breaks the caller.
- **routes** (dashed): a skill deliberately handing work to another skill.
  Breaking the target skill strands the routing.
- **serves** (dotted): a launchd service running fleet code, or a tool
  reading another's data on disk. Every fleet service is agentstart's; the
  machine's own reverse-DNS services are outside the fleet.
- **pins**: a binary installed at an exact version because a consumer locks
  or resolves it by contract.

## Runtime call graph

```mermaid
flowchart LR
    subgraph harnesses [Harnesses]
        claude[Claude Code]
        codex[Codex CLI]
        pi[Pi]
    end

    subgraph balancing [Launch balancing]
        launch[agentlaunch]
        usage[agentusage]
        claudeSwap[claude-swap]
        swap[codex-swap]
    end

    subgraph research [Research pipeline]
        brain[agentbrain]
        scrape[agentscrape]
        web[agentweb]
        browser[agent-browser]
    end

    voice[agentvoice]
    board[agentboard]
    wiki[agentwiki]
    chats[cass / agentchats]
    herdr[herdr — the surface]
    ghostty[Ghostty]
    tinty[tinty]
    herdrTinty[agentstart / herdr-tinty]
    surface[agentsurface]

    surface -->|x-catalog --x-json, slug completions| launch
    surface -->|workspace/worktree create, agent start, tab rename, agent prompt| herdr
    herdr -.->|plugin: launch popup; pane.agent_detected → project token + name-tab| surface
    herdrTinty -->|install, update, build, apply Chalk| tinty
    tinty -->|item hook: generated palette| herdrTinty
    tinty -->|generated theme + SIGUSR2 reload| ghostty
    herdrTinty -->|config check, reload-config| herdr
    launch -->|balance claude/codex --json| usage
    launch -->|run --share-history| claudeSwap
    launch -->|run / resume / pi run --claim| swap
    launch -->|managed launch| claude
    launch -->|managed launch| codex
    launch -->|managed launch| pi
    swap --> codex
    swap --> pi
    usage -->|snapshot --json| swap
    usage -->|list --json / recover| claudeSwap
    voice -->|app-server children, login| codex
    voice -->|balance codex| usage
    voice -.->|fallback: select| swap
    voice -->|surface wakes: events.subscribe, unix socket| herdr
    brain -->|extraction and discovery| scrape
    scrape -->|drives| browser
    scrape -->|sessions/resolve, unix-socket IPC| web
    web -->|digest-locked launch| browser
    board -->|publish --kind render| wiki
    chats -.->|indexes session stores| harnesses
```

## Install and service layer

```mermaid
flowchart LR
    machine[machine installer + updater]
    start[agentstart]

    machine ==>|scripts/install.sh --install, sync-skills| start
    start ==>|official installers| harnesses[Claude Code / Codex / Pi]
    start ==>|brew formula + harness integrations + binary-rendered skill| herdrInstall[herdr]
    start ==>|upstream tap + formula + local templates| tinty[tinty]
    start ==>|npm pin| browser[agent-browser]
    start ==>|checkout contracts| fleet[agentvoice / agentwiki / agentboard / agentsearch / agentkeys / agentweb / agentscrape / agentbrain / codex-swap / agentusage / agentlaunch / agentsurface / cass]
    start ==>|skills scan + post-sync hooks| skills[all agent skills, agentguidance rendered]
    start ==>|per-file links, after the scan| voiceDoctrine[agentvoice doctrine: server.json from start, orchestrator prompts agentguidance-rendered]
    start -.->|config/launchd + install-launchagents| services[agentbrain worker + share + doctor / agentusage observer / agentweb broker / agentscrape queue-processor / agentwiki server]
```

## Skill routing

An edge `X -.-> Y` means X's runbook names the `Y` skill and routes work to
it. Extracted from the SKILL.md files themselves.

```mermaid
flowchart LR
    subgraph fleetSkills [Fleet skills]
        board -.-> groom & wiki
        groom -.-> board
        brain -.-> chats & scrape & search & wiki
        scrape -.-> brain & browser & search
        search -.-> brain & chats & scrape
        browser -.-> scrape & search
        wiki -.-> board & brain & chats
        chats
        keys
        bus
    end

    subgraph guidanceSkills [agentguidance skills]
        resource[resource-create / resource-update] -.->|built on| brainCli[agentbrain CLI]
        story -.->|publishes via| wikiCli[agentwiki CLI]
        notify -.->|posts via| notifierCli[terminal-notifier]
        email -.->|reads via| gogCli[gog] & notify
        watchRequests[watch-requests] -.-> notify
    end

    watchRequests -.-> chats
    bus -.-> notify

    tools[TOOLS.md — agentstart prompts, spliced into collab, build, and orchestrate at render] -.-> search & scrape & brain & browser & wiki & board & groom & chats & notify & bus
```

The TOOLS.md node is the widest fan-out in the fleet and this repository is
its origin: `agentguidance/scripts/render` splices
`prompts/agentguidance/TOOLS.md`
into the collab, build, and orchestrate skills at their
`<!-- extension-prompt: TOOLS.md -->`
markers, so those skills route to all advertised tools without
their templates naming any of them. That is why the tool-advertisement
policy (the `tool-advertisement-policy` wiki page) governs a real graph
edge, not just prose.

`keys` references no other skill and none reference it — the standalone
shape behind the decision not to advertise it in TOOLS.md. `email` is
unadvertised on the same policy but is not standalone: it routes to
`notify`, so mail work that stalls still reaches the human.

A trap this section has already caught twice: a project's *own* `search`
subcommand (agentboard's and agentwiki's) reads exactly like a reference to
the `search` skill in a bare name-grep. Verify a routing edge from the
sentence around the match, never from the name alone.

## Edges with evidence

### calls

| Caller | Callee | What | Evidence |
| --- | --- | --- | --- |
| agentstart | agentusage | `install-agent-clis` invokes the checkout's `scripts/install.sh --install`, which provisions the public claude-swap fork before installing the observer. It no longer writes a `codex-swap` shim — that command has one owner now | `agentstart/scripts/install-agent-clis`; `agentusage/scripts/install-providers.sh` |
| agentstart | codex-swap | `install-agent-clis` invokes `scripts/install.sh --install`, which writes the `codex-swap` command as a source shim into the checkout and installs the exact stock codex-multi-auth npm pin | `agentstart/scripts/install-agent-clis`; `codex-swap/scripts/install.sh` |
| agentstart | agentlaunch | `install-agent-clis` invokes `scripts/install.sh --install` after `agentusage`; `scripts/install-agentlaunch-shims` is the external shim contract for bare `claude`/`codex`/`pi` | `agentstart/scripts/install-agent-clis`; `agentstart/scripts/install-agentlaunch-shims` |
| agentlaunch | agentusage | `agentusage balance claude\|codex --json` chooses a balanced account. Real Codex/Pi launches add `--claim`; dry runs do not reserve capacity | `agentlaunch/src/balance.ts` (`balanceClaude`, `balanceCodexFamily`) |
| agentlaunch | claude-swap | wraps balanced Claude launches as `cswap run <slot> --share-history -- <native argv>` | `agentlaunch/src/balance.ts` (`balanceClaude`); `agentlaunch/docs/adr/0003-balanced-launches-compose-a-prefix.md` |
| agentlaunch | codex-swap | wraps Codex opens as `codex-swap run`, Codex resumes as `codex-swap resume <id>`, and Pi as `codex-swap pi run`, with `--claim <lease>` for real Codex/Pi launches and `--account <key>` for dry runs or explicit pins | `agentlaunch/src/balance.ts` (`balanceCodexFamily`, `composeCodexFamily`); `agentlaunch/docs/adr/0003-balanced-launches-compose-a-prefix.md` |
| agentlaunch | claude / codex / pi | launches the resolved native harness and sets `AGENTLAUNCH_LAUNCH=1`; AgentStart's bare-command shims route to `agentlaunch --x-harness <harness>` and use that sentinel to exec the real binary on descendant launches | `agentlaunch/src/launch.ts`; `agentstart/scripts/install-agentlaunch-shims`; `agentlaunch/docs/adr/0004-shims-route-bare-calls-the-sentinel-breaks-recursion.md` |
| codex-swap | codex-multi-auth | exact npm pin, currently 2.8.4. Codex-swap invokes the package-local forced-account wrapper for native Codex runs and resumes; its installer no longer binds the fleet to the patched fork | `codex-swap/package.json`; `codex-swap/src/ndy/bin-resolver.ts`; `codex-swap/scripts/install.sh` |
| agentusage | claude-swap | `cswap list --json` observes Claude accounts; `cswap recover <slot> --json` repairs due expired tokens; its installer converges the public fork's `main` | `agentusage/src/claude/observe.ts:235`; `src/daemon.ts:78`; `scripts/install-providers.sh` |
| agentusage | codex-swap | `codex-swap snapshot --json` observes codex accounts; paced polling | `agentusage/src/codex/observe.ts:221`, `daemon.ts:19` |
| agentvoice | codex | runs the resident `codex app-server` under launchd via a rendered wrapper, and `codex login --device-auth` for profile onboarding | `agentvoice/src/resident/contract.ts` (`residentArgv`), `src/resident/install.ts` (`renderWrapper`), `src/main.ts` (`accounts add`) |
| agentvoice | agentusage → codex-swap | `agentusage balance codex`, falling back to `codex-swap select`, consulted by the resident wrapper at every spawn (`pick-home`) and by the console's rotation check | `agentvoice/src/core/accounts.ts` (`selectAccount`), `src/resident/install.ts` (`runPickHome`), `src/core/runtime.ts` (`maybeRotate`) |
| agentvoice | herdr | unix-socket IPC, not a spawn: with `surface.events` on, the console holds an `events.subscribe` NDJSON stream on herdr's socket and reconciles via one-shot `agent.list` calls; pane lifecycle events for token-tagged placed workers become `<surface_report>` turns at the orchestrator | `agentvoice/src/core/surface.ts` (`HerdrSurface`), `src/core/runtime.ts` (surface wiring); enabled by `agentstart/prompts/agentvoice/server.json` |
| agentstart | herdr | `scripts/update-herdr` (the one update path: fast-forward the clean `~/src/herdr` checkout at upstream master, build with the pinned `zig@0.15`, install to `~/.local/bin/herdr`, notify instead of forcing a blocked checkout), `herdr integration install claude\|codex\|pi` every run, `herdr plugin link` of agentsurface's launcher-pane and tab-naming plugin directory (registration by checkout path, so relinking converges), and the surface skill rendered from `herdr --skill` into a managed pack and shipped through `skills add` — the skill converges with the installed build. The homebrew-core formula is retired and uninstalled by the full installer | `agentstart/scripts/update-herdr`, `agentstart/scripts/install.sh` (`install_herdr_integrations`, `install_herdr_skill`), asserted by `agentstart/tests/validate.sh` |
| agentstart (`herdr-tinty`) | tinty | installs from Tinted Theming's Homebrew tap, updates the catalog, builds AgentStart's local Base16 Herdr template, and deterministically applies `base16-chalk`; no cycling interface remains | `agentstart/scripts/install.sh`; `agentstart/scripts/herdr-tinty`; `agentstart/config/tinty/` |
| tinty | agentstart (`herdr-tinty`) | the configured `tinted-herdr` item calls `herdr-tinty apply-theme "$TINTY_THEME_FILE_PATH"` when Chalk is applied; generated themes and the recorded palette remain outside Git | `agentstart/config/tinty/config.toml`; `agentstart/scripts/herdr-tinty` (`apply_theme`) |
| tinty | Ghostty | the official `tinted-terminal` item copies the rendered Base16 Chalk palette to Ghostty's stable `tinted-theming` theme name and sends `SIGUSR2` for a live reload; Funk's tracked Ghostty config selects the name while the generated colors remain outside Git | `agentstart/config/tinty/config.toml`; `funk/ghostty/.config/ghostty/config` |
| agentstart (`herdr-tinty`) | herdr | validates every composed candidate through `HERDR_CONFIG_PATH=<temp> herdr config check`, atomically replaces the managed live config, then calls `herdr server reload-config`; a missing server is nonfatal because the next start reads the validated file | `agentstart/scripts/herdr-tinty` (`render_candidate`) |
| agentbrain | agentscrape | evidence pipeline in four argv shapes — `fetch-markdown --markdown`, `fetch-markdown --envelope --allow-private-network --max-content-bytes`, `discover-feed`, `fetch-links --preset x-timeline --limit --max-scrolls` — plus a doctor check; a flag change breaks each shape separately | `agentbrain/src/agentscrape.ts:642,1298-1306,2038,2121-2129`, `src/jobs.ts:736` |
| agentscrape | agentweb | unix-socket IPC, not a spawn: before navigating, asks the daemon `POST /v1/sessions/resolve` whether the origin has a stored signed-in session, via `AGENTSCRAPE_CONDUIT_SOCKET`/`_TOKEN_FILE`; degrades silently to unauthenticated fetching by contract, so it never surfaces in an error path | `agentscrape/src/conduit.ts:10-21,107-110`; served by `agentweb/src/ipc.ts:442-453` |
| agentscrape | agent-browser | resolves `~/.local/bin/agent-browser` first, then PATH | `agentscrape/src/browser.ts:386-391` |
| agentweb | agent-browser | daemon-only launch of the configured absolute path (default `~/Library/pnpm/bin/agent-browser`, never resolved through PATH), refused unless SHA-256 digest and version lock verify | `agentweb/src/config-schema.ts:51,83`, `src/paths.ts:268` |
| agentboard | agentwiki | `agentwiki publish <file> --name agentboard --kind render --json` | `agentboard/src/cli.ts:834-843` |
| agentsurface | agentlaunch | `agentlaunch x-catalog --x-json` at launcher start and before slug inference: the resolved catalog — harness order, per-model efforts, defaults, and each harness's `metadata_level`. `conversation slug` then runs `agentlaunch --x-harness <h> --x-level <metadata_level>` with the harness's native non-interactive tokens (`-p`, `exec --output-last-message`, `-p --no-session`) in the fixed `/tmp/agentsurface/inference` cwd — agentlaunch by name, not the bare shim, because a session's `AGENTLAUNCH_LAUNCH` sentinel would exec the native binary and drop the level. The launch executor also rides agentlaunch's `--x-prompt-file <spool path>` through the shim: the intent's text becomes the final native token only inside agentlaunch (agentlaunch ADR 0029), because herdr refuses control characters in a shell-typed argument | `agentsurface/src/catalog.ts` (`loadLaunchCatalog`); `agentsurface/src/conversation/infer.ts` (`composeInference`); `agentsurface/src/launch/executor.ts` (`writeIntentFile`) |
| agentsurface | herdr | drives the socket API through the CLI (`HERDR_BIN_PATH`, then PATH), split across the popup TUI (`workspace list` probe, `pane get` for the opened-over cwd) and the detached `execute-launch` executor it spawns so the popup closes on submit: `pane list`/`workspace list` to find a workspace already hosting the project, then `tab create` into it or `workspace create`/`worktree create` (each `--focus`/`--no-focus` by submit mode, plus `workspace focus` for a cross-workspace jump), `agent list`, `agent start <opaque-a-token> --kind <harness> --pane <root-pane> -- --x-level <model>:<effort> [--x-prompt-file <state intents/ spool file>]` with the pane-busy ready retry and an `agent_name_taken` re-derive, and `notification show` for failures with no terminal. The intent travels as a spool-file reference, never literal text — herdr types the command into the pane's shell and rejects control characters (`invalid_agent_argument`), so a multi-line intent can only cross as a path; the executor prunes the spool by age. The bare harness command herdr runs is agentstart's shim, so the shim → agentlaunch edge carries balancing, yolo, and the prompt-file expansion; `agent_not_ready` (blocked on a startup dialog) is a soft outcome because the expanded intent rides the native argv and the harness submits it once the dialog clears. The plugin hook uses `pane get` + `workspace get`, plus `worktree list` for linked checkouts, then `pane report-metadata` to publish the Agent sidebar's contiguous `$project` label on every detection; afterward it polls `pane get` for `agent_session`/`tab_id` and runs `tab rename <tab_id> <slug>`. The message bus (`agentsurface agents` / `message`) adds `agent list` + `tab list` (agents named by their tabs' labels), `pane get` for the sender's own identity from `HERDR_PANE_ID`, and `agent prompt <pane> <prefixed text>` — herdr delivering an agent-to-agent message as typed input (paste + Enter), so a working target's harness queues it and a blocked target rejects it | `agentsurface/src/herdr.ts`, `agentsurface/src/launch/executor.ts`, `agentsurface/src/launch/app.ts`, `agentsurface/src/tab-namer.ts`, `agentsurface/src/bus.ts` |

### serves / data

| From | To | What | Evidence |
| --- | --- | --- | --- |
| agentstart | agentbrain, agentscrape, agentusage, agentweb, agentwiki | installs their commands too, and owns these fleet launch agents outright: agentbrain worker/share/doctor, agentusage observer, agentweb broker, agentscrape queue processor, and agentwiki server. Labels name noun roles while the manifest records resident, periodic, or queue-triggered lifecycle; every plist enters through the tool's one public binary. Templates, manifest, rendering, label replacement, and load live here so a service never has two owners racing to render it | `agentstart/config/launchd/*.plist`, `agentstart/scripts/install-launchagents`, asserted by `agentstart/tests/validate.sh` |
| machine installer + updater | agentstart | the only inbound edges from outside the fleet: the installer calls `scripts/install.sh --install` and nothing else about the fleet, because agentstart installs every fleet command and every fleet service, and discovers the tailnet bind address and agentweb's conduit paths itself; the machine's scheduled updater calls `scripts/sync-skills` and `scripts/update-herdr` by path — the convergence steps that stay safe with no terminal | `agentstart/scripts/install.sh` (the documented external interface), `agentstart/scripts/install-agent-clis`, `agentstart/scripts/install-launchagents`, `funk/libexec/funk-update` |
| agentstart | agentscrape ↔ agentweb conduit | brokers the session conduit, because it is the only thing that installs both: it renders agentweb's socket and token paths into the agentbrain.worker service, and the worker passes them uninterpreted into the agentscrape children it spawns | `agentstart/scripts/install-launchagents` (agentbrain.worker tokens), asserted by the machine's local-service verification |
| agentboard | agentwiki | stored data, distinct from the publish call: board items hold agentwiki slugs (`link <ref> --wiki <slug>` / `unlink`), so changing wiki's slug scheme breaks stored links even where publishing never runs | `agentboard/skills/board/SKILL.md:228-232`, reciprocated `agentwiki/skills/wiki/SKILL.md:133-134` |
| cass (agentchats) | Claude Code, Codex, Pi | builds and refreshes the search index over the local session stores; cass itself is upstream software — the official checksummed installer, gh-resolved — with only the `agentchats` state CLI linked editable from the checkout | `agentchats/scripts/install.sh:6,95,123-129,137` |
| agentchats view | cass, session stores | the transcript viewer discovers sessions through `cass sessions --json` (workspace-scoped, deduped by path) and then reads the native store files directly for fidelity and live follow — cass is discovery, never the render source | `agentchats/viewer/src/discover.ts`, `agentchats/viewer/src/tail.ts`, `agentchats/bin/agentchats` (`view`) |
| agentkeys | stowed machine configs | audits the interception chain across Karabiner/skhd/Ghostty/tmux/Neovim — files the machine layer stows | `agentkeys` skill description; the machine's stow packages |
| agentboard, agentchats | each other's CLIs | the shared "agent* state dump" bearings convention: one cross-tool contract for state dumps, with a common ~4-chars-per-token budget | `agentboard/src/help.ts:367`, `agentchats/bin/agentchats:13`, `agentboard/src/brief.ts:140` |
| agentstart statusline | claude-swap | the claude renderer names the balanced account by reading `CLAUDE_CONFIG_DIR`, whose basename claude-swap spells `<n>-<slugified-email>`; renaming that profile directory silently drops the account segment. No counterpart for codex or pi — codex-swap pins an account by swapping auth in place and exports nothing naming it | `agentstart/config/statusline/claude-statusline.sh` (balanced-account segment); `claude-swap/src/claude_swap/session.py:161-167` |
| agentguidance | agentvoice (via agentstart) | the voice orchestrator doctrine is rendered doctrine: `agentguidance/prompts/agentvoice/` templates splice the shared orchestrator fragments to `~/.agents/prompts/agentvoice/`, agentstart links the result into `~/.config/agentvoice` after sync-skills (keeping only `server.json` as its own source), and agentvoice discovers the files by name at console start | `agentguidance/scripts/render`; `agentstart/scripts/install.sh` (`link_agentvoice_config`); `agentvoice/src/core/config.ts` (`PROMPT_FILES`) |
| agentstart | herdr, agentsurface, tinty | owns Herdr's live `config.toml` as a generated composition of tracked behavior and the fixed Base16 Chalk palette. The behavior opens AgentSurface's titled `launch` plugin pane on `prefix+l` from the active pane's cwd; Funk retains only the machine-owned `agent-mem.sh` referenced by the config | `agentstart/config/herdr/config.toml`; `agentstart/scripts/herdr-tinty`; `funk/herdr/.config/herdr/agent-mem.sh` |
| herdr | agentsurface | the linked `agentsurface` plugin (registered by agentstart's installer via `herdr plugin link`, manifest in `agentsurface/plugin/`) exposes `agentsurface launch` as a titled 80% session-modal popup and runs `agentsurface name-tab` on every `pane.agent_detected`. The binding passes the active pane's cwd to the popup; the hook receives the event as `HERDR_PLUGIN_EVENT_JSON`, publishes the `$project` sidebar token (root repository, worktree badge, and branch for linked worktrees), keeps its state under `HERDR_PLUGIN_STATE_DIR`, and names the pane's tab after its conversation once per tab | `agentsurface/plugin/herdr-plugin.toml`; `agentstart/config/herdr/config.toml`; `agentstart/scripts/install.sh` (`install_herdr_plugins`) |

### pins

| Binary | Version | Why | Evidence |
| --- | --- | --- | --- |
| agent-browser | 0.33.2 | one pin, two independent path contracts: Agentweb digest-locks the exact build and launches its configured absolute path (default `~/Library/pnpm/bin/agent-browser`, never PATH), while Agentscrape resolves the `~/.local/bin/agent-browser` link before PATH — relocating one path fixes only that consumer's half | `agentstart/scripts/install.sh` (`agent_browser_version`), `agentweb/src/config-schema.ts:51,83`, `agentweb/src/paths.ts:268`, `agentscrape/src/browser.ts:386` |
| @native-sdk/cli | 0.7 line | the native-sdk skill documents 0.7 and its agent helpers are version-matched | `agentstart/scripts/install.sh` (`native_sdk_version`) |
| zig | Brewfile-tracked, duplicated in the installer | AgentVoice's native duplex audio path and Native SDK packaging build against it | `agentstart/scripts/install.sh` |
| zig@0.15 | 0.15 line, keg-only | herdr's vendored libghostty-vt pins 0.15 and herdr's release CI builds with this same formula; the official 0.15 tarball cannot link against current macOS SDKs. update-herdr refuses with a notification when the vendored pin drifts off 0.15 | `agentstart/scripts/install.sh`, `agentstart/scripts/update-herdr` (drift gate) |
| herdr | `~/src/herdr` at `origin/master` | a checkout binding, not a version pin: the operator runs the head because releases trail master by weeks. update-herdr only ever fast-forwards a clean checkout — a dirty tree or diverged master is reported by notification and left untouched | `agentstart/scripts/update-herdr`, receipt at `~/.local/state/agentstart/herdr-built-commit` |

The managed claude-swap fork rebases its **`integration` branch** onto upstream on every
install — every patch we carry, merged, and the only ref the installer builds
and binds — gated by that project's own CI steps and published with
`--force-with-lease` only after the gate passes. A failed rebase or gate keeps
the previously bound build bound, publishes nothing, and notifies. The fleet
repo owns its own hardened installer rather than sharing a common helper, which
would invert that ownership. A patch also offered upstream lives on its own
branch and is **not** moved by this — refreshing an open PR is a separate
operation against a different audience. Whether a fork is wired at all is a
declared constant in the owning installer, so retiring it is an edit and a
rerun; a binding hand-written into the installed shim is unwired by the next
install, which is how the codex-multi-auth one was lost once. The
`fork-rebase-policy` wiki page is the contract.

| Fork | Integration branch | Owner | Gate |
| --- | --- | --- | --- |
| `~/src/claude-swap` | `integration` | `agentusage/scripts/install-providers.sh` | `uv sync --locked && uv run pytest` |

Codex-swap no longer binds `~/src/codex-multi-auth`: it uses the exact stock
npm pin. Open upstream PRs #664 and #665 address helper cleanup for the retired
per-TUI app-server topology and are no longer needed by this fleet; AgentVoice's
independent app-server children do not use codex-swap's removed sidecars.

### routes (skill → skill)

| From | Routes to | Notable natures |
| --- | --- | --- |
| board | groom, wiki | bulk reshaping is groom's; renders publish through wiki (see the calls edge). Board's `search` is its own subcommand, not the search skill |
| groom | board | one item is board; several at once is groom |
| brain | chats, scrape, search, wiki | checked before any web search — search is paid per call; ingestion is scrape-fed. Brain also has an own-`search` subcommand; the skill edge is genuine independently (`agentbrain/skills/brain/SKILL.md:32,172-173,382,415`) |
| scrape | brain, browser, search | scrape wants a URL in hand; finding URLs is search; interaction is browser |
| search | brain, chats, scrape | check brain first — the answer is often already local |
| browser | scrape, search | fetching content is scrape; finding pages is search |
| wiki | board, brain, chats | the durable home the others cite into. Wiki's `search` is its own subcommand, not the search skill |
| TOOLS.md (this repo) | search, scrape, brain, browser, wiki, board, groom, chats, notify, bus | spliced into collab, build, and orchestrate at render — the advertisement lines are the routing |
| bus | notify | a blocked bus target is waiting on the operator, so a message that matters escalates to a human notification instead of more retries (`agentsurface/skills/bus/SKILL.md`) |
| orchestrate (agentguidance) | collab, build, herdr | the wielder: collab's contract holds on the conversation thread, and execution leaves as standalone briefs run under build's contract by dispatched workers (`agentguidance/skills/orchestrate/SKILL.md`, `fragments/orchestrator-conduct.md`). Dispatch runs on two lanes: the native facility for work in the orchestrator's own service, and the surface — herdr — for the work itself; both orchestrator renditions bind herdr by name and load its skill for placement mechanics |
| resource-create / resource-update (agentguidance) | brain | resources are built from and refreshed against the agentbrain index |
| story (agentguidance) | wiki | publishes the finished narrative through agentwiki |
| watch-requests (agentguidance) | chats, notify | the watch diagnoses but never authors: `cass resume <source_path> --shell` names the session that opened the request, and notify carries the resume command and steering prompt to the human (`agentguidance/skills/watch-requests/SKILL.md`) |
| email (agentguidance) | notify | a lapsed credential or consent screen needs the human, who is not reading the transcript — the stall is announced, not waited in (`agentguidance/skills/email/SKILL.md`) |

## Checked and absent

Edges that were looked for and do not exist — recorded so the next audit
does not re-suspect them:

- agentbrain → agentsearch: no reference anywhere in `agentbrain/src`;
  ingestion is purely scrape-fed (checked 2026-08-09).
- agentvoice → agentboard / agentwiki: the orchestrator's app-server
  threads drive codex only; no board or wiki reference in `agentvoice/src`
  (checked 2026-08-09).

Last verified: 2026-08-09, twice — an initial first-hand sweep, then an
independent second sweep that removed two false routing edges (own-`search`
subcommands), added the conduit and TOOLS.md edges, and re-confirmed both
absences above. Updated 2026-08-12 for the de-Orca topology: AgentLaunch owns
bare harness launch balancing, AgentStart retires AgentBus launch agents and
adapters, and TOOLS.md no longer advertises the retired bus skill. Updated
again 2026-08-12 for the orchestrator doctrine unification: agentguidance
renders the voice orchestrator prompts from shared fragments, the new
orchestrate skill wields collab and build, and AgentStart links rendered
doctrine instead of owning it. Updated again 2026-08-12 for the fleet service
taxonomy: noun-role labels, explicit lifecycle metadata, and one public binary
per tool replace daemon/command-shaped labels and separate `*d` executables.
Updated 2026-08-15 for the surface abstraction: herdr (external,
homebrew-core) becomes the orchestrator doctrine's reference launch surface —
AgentStart renders its shipped skill from the binary, agentvoice subscribes
to its events for `<surface_report>` wakes, and the orchestrate/voice
doctrine binds it by name. The `land-vs-place` and new launch-surface wiki
pages carry the ruling. Updated 2026-08-16 for the first AgentSurface
integration: `agentsurface launch` composes herdr (workspace/worktree
create, agent start) with agentlaunch's new read-only `x-catalog`, and the
managed herdr config gains the `prefix+l` popup binding. Updated again
2026-08-16 for the second integration: `agentsurface conversation slug`
runs metadata completions through `agentlaunch --x-level <metadata_level>`
(the catalog's new per-harness cheap pair), the agentsurface herdr plugin
names tabs from `pane.agent_detected` hooks, agentstart links that plugin
and adopts the agentsurface checkout contract, and the retired-integration
cleanup stops treating the reborn `agentsurface` command link as retired.
Updated again 2026-08-16 for AgentStart's Tinty/Herdr integration: AgentStart
replaces Funk as the live Herdr config owner, Tinty hooks feed generated
palettes into `herdr-tinty`, and the helper validates and live-reloads the
generated config. Updated again 2026-08-16 to make the
existing AgentSurface plugin own the launcher's title and popup geometry, with
the managed keybinding opening that pane entrypoint from the active pane's cwd.
Updated 2026-08-17 for Tinted Terminal's official Ghostty target and the fixed
theme decision: AgentStart now applies Base16 Chalk on every install, copies it
into Ghostty's untracked theme directory, and signals live instances to reload;
Funk selects the stable generated theme name. The theme-cycling commands and
Herdr keybindings were removed.
Updated 2026-08-17 for the third AgentSurface integration, the message bus:
`agentsurface agents`/`message` speak herdr's `agent list`, `tab list`,
`pane get`, and `agent prompt`, so agents on the surface message each other
by tab-label names or session ids with herdr as the delivery path. The bus
gained its skill the same day: `bus` joins TOOLS.md's advertisements and
routes to `notify` for blocked-target escalation; `message --wait-unblocked`
retries a blocked delivery until its deadline.
