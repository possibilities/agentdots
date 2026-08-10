## Guidelines

- When a project needs persistent repository guidance, `AGENTS.md` at the repo
  root is the canonical file; make `CLAUDE.md` a symlink to it
  (`ln -s AGENTS.md CLAUDE.md`). Where tooling refuses tracked symlinks
  (agentscrape's installer does), `CLAUDE.md` is instead a short pointer
  file naming `AGENTS.md` as the real notes — never a second set of
  instructions.
