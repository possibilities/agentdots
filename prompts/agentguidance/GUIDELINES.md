## Guidelines

- In someone else's checkout (`~/src`), orient before working: confirm the
  branch is the one the task means — usually the default, or our fork's
  branch when we carry patches there — and not a leftover temporary one.
  Then pull and fast-forward from the remote. A branch that has genuinely
  diverged is its own procedure; report it rather than resolving it in
  passing.
- A fork we carry patches on has exactly two kinds of branch, and confusing
  them is the recurring mistake. `integration` is every patch we carry,
  merged, and the only ref an installer builds and binds; a patch also
  offered upstream lives on its own branch, cut from upstream's head, and is
  never moved by an install — refreshing an open PR force-pushes a head a
  maintainer is mid-review on. A fleet app depending on a fork binds the
  local checkout at `integration` from its own installer, never by hand:
  the binding survives a reinstall or it is not a binding. Whether the fork
  is wired at all is a declared line in that installer, so retiring it is an
  edit and a rerun. The `fork-rebase-policy` wiki page is the contract.
- Worktrees and branches belong to the orchestrator that starts sessions:
  when work needs one, the session is started inside it, already on the
  right branch. Work where you were started, and when the task seems to
  need a worktree or branch you were not given, say so rather than
  creating it.
- Build forward: the new shape replaces the old. Compatibility shims,
  deprecation windows, and migrations are opt-in — when a change breaks
  something, name what breaks and for whom before it lands; the softer path
  is asked for, never assumed.
- When a project needs persistent repository guidance, `AGENTS.md` at the repo
  root is the canonical file; make `CLAUDE.md` a symlink to it
  (`ln -s AGENTS.md CLAUDE.md`). Where tooling refuses tracked symlinks
  (agentscrape's installer does), `CLAUDE.md` is instead a short pointer
  file naming `AGENTS.md` as the real notes — never a second set of
  instructions.
- A document someone asks for goes in the wiki — write-ups, reports, plans,
  research, notes — unless they ask for it in the project. What the repo
  itself owns stays in the repo: `AGENTS.md`, `CONTEXT.md`, `README`, ADRs,
  and the docs that ship with the code.
- Publish an artifact only when asked for one, and always through `wiki`,
  never a harness's own artifact publisher.
- When a search runs in a pipeline, cap it at the source: `grep -m N` stops
  after N matches, while `| head -N` stops only the reader — the harness
  rewrites `grep` to an embedded ugrep that keeps searching after `head`
  exits, holding memory with nobody left to consume it. Inside a `while read`
  loop, give it `< /dev/null` as well, or it inherits the loop's stdin and
  eats the input being iterated.
- A clipboard copy leaves nothing on screen, so notify what landed there.
- Finished work lands in main and is pushed — a worktree is where work
  happens, not where it stops. A pull request is a workflow to be asked for
  by name, not a default.
