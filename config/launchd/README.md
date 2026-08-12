# Fleet launch agents

Every long-running fleet service on this machine is defined here and installed
by `scripts/install-launchagents`, without exception. A fleet checkout no
longer installs its own service; it ships the code, and this repository decides
when that code runs.

The machine layer keeps its own services and its own `launchd/` directory.
The split is the label: a bare `<tool>.<service>` label is a fleet service
and lives here; a reverse-DNS label is the machine's.

## What is standardized

The frame is identical for every service, and deviating from it is a bug:

- **Label** — `<tool>.<service>`, matching the file name exactly.
- **Service names are noun roles** — `worker`, `share`, `doctor`, `observer`,
  `broker`, `queue-processor`, and `server`. A label says what responsibility
  the process owns; `daemon`, `serve`, and command spellings do not leak into
  the label.
- **Ownership marker** — the second line is
  `<!-- agentstart-installer-owned: <label>.v1 -->`. The installer refuses to
  unload or replace a service carrying anything else, so a hand-written or
  third-party agent that happens to share a label is never touched.
- **Tokens** — `__UPPER_SNAKE__`, replaced with XML-escaped absolute values at
  install time. Rendering fails closed: an unresolved token, a value the
  manifest does not supply, or a plist that fails `plutil -lint` aborts that
  service without publishing anything.
- **Publication** — rendered to a temporary file inside the destination
  directory, `chmod 600`, then renamed, so a reader never sees a half-written
  service.
- **`HOME` and `PATH` are always pinned absolutely.** launchd sources no shell
  rc file, so an unpinned `PATH` cannot reach uv-, nvm-, or Homebrew-managed
  tools.
- **No credential is ever rendered into a plist.** `launchctl print` discloses
  a service's environment to any process that can run it. Secrets are named by
  path and read by the process that needs them, from a mode-0600 file.
- **`Umask` 63** (`0o077`) and one log file per service at
  `~/.local/state/<tool>/<service>.log`.
- **`RunAtLoad`** — every service is expected to be correct at login.
- **Missing tool, no service.** A service whose checkout or program is absent
  is skipped, never failed, matching the rest of the AgentStart installer.
- **One executable per tool.** Every plist invokes `~/.local/bin/<tool>` and an
  explicit subcommand. Parallel `<tool>d` executables are not a fleet service
  interface.

## What is deliberately per-service

These differ because the services differ, and each template says why in a
comment beside the key:

- **`ProcessType`** — `Background` for work nobody waits on, `Standard` where a
  human is blocked on the result. Background QoS is starved first under
  contention, which is correct for ingestion and wrong for a browser a person
  is looking at.
- **Lifecycle** — the manifest names each service as `resident`, `periodic`, or
  `queue-triggered`; templates express that through `KeepAlive`,
  `StartInterval`, and `QueueDirectories`. `agentbrain.doctor` is the only
  periodic member and `agentscrape.queue-processor` the only queue-triggered
  member.
- **Arguments and extra environment**, including values that must be
  discovered from another service at install time.
- **Conditional installation.** `agentbrain.share` installs only when an
  operator names a bind address; there is no default, by its ADR 0017.

## Adding a service

Add the template here, add its entry to the manifest in
`scripts/install-launchagents`, and add its assertions to `tests/validate.sh`.
The plan line in `scripts/install.sh --check` comes from the manifest, so it
follows automatically.
