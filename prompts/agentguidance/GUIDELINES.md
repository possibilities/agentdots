## Guidelines

- In someone else's checkout (`~/src`), orient before working: confirm the
  branch is the one the task means — the default, or our fork's branch when
  we carry patches — then pull and fast-forward. A genuinely diverged
  branch is reported, not resolved in passing.
- Forks we patch keep two kinds of branch: `integration` — every patch,
  merged, the only ref an installer binds — and per-PR branches, which an
  install never moves. Installers own the binding, never hands. The
  `fork-rebase-policy` wiki page is the contract.
- Worktrees and branches belong to the orchestrator that starts sessions:
  work where you were started, and say so when the task needs topology you
  were not given.
- Build forward: the new shape replaces the old. Shims, deprecation
  windows, and migrations are opt-in — name what breaks and for whom
  before a breaking change lands; the softer path is asked for, never
  assumed.
- Repository guidance is `AGENTS.md` at the repo root, with `CLAUDE.md` a
  symlink to it — or, where tooling refuses tracked symlinks, a short
  pointer file naming `AGENTS.md`; never a second set of instructions.
- Route documents by reader and lifetime: asked-for documents and ruling
  decisions go to the wiki, the repo keeps what it owns (`AGENTS.md`,
  `CONTEXT.md`, `README`, ADRs, the docs that ship with the code), and
  successor-session context is a dated `~/handoffs/` file, deleted by its
  consumer. The `document-placement-policy` wiki page is the contract.
- Publish an artifact only when asked for one, and always through `wiki`,
  never a harness's own artifact publisher.
- Cap searches at the source, not the reader: `grep -m N`, not `| head`,
  and `< /dev/null` on a grep inside a `while read` loop — some harness
  grep engines outlive the pipe and eat the loop's stdin.
- A clipboard copy leaves nothing on screen, so notify what landed there.
- Finished work lands in main and is pushed — a worktree is where work
  happens, not where it stops. A pull request is a workflow to be asked
  for by name, not a default.
- A fleet full-screen TUI follows the Signal Room design language. Before
  building or reshaping one, read the `fleet-tui-design` wiki page — the
  shell contract: header and footer rows, the action rail, explicit
  widths — and the design-language page it opens with, for the tokens and
  their law. The contracts live there, not here.
