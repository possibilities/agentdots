# 0001: Keep core skills out of compatibility roots

Fx intentionally discovers user skills from `~/.agents/skills`,
`~/.claude/skills`, and `~/.codex/skills`. AgentStart previously used the
cross-agent `skills` CLI defaults, which made every fleet and external skill
available to Fx even though they were installed for Claude Code, Codex, and
Pi.

AgentStart now owns one private marketplace at
`~/.local/share/agentstart/core-marketplace`. Its `agentstart-core` plugin
contains the canonical installed skill tree. Claude Code and Codex install
that plugin from machine-local marketplaces, while Pi links the same skill
directories from its harness-specific root. The full installer removes only
AgentStart-owned legacy compatibility-root entries; the unattended sync is
additive there.

Plugin namespaces are part of the isolation boundary. Claude Code and Codex
therefore expose names qualified by `agentstart-core`; Pi retains plain skill
names. Preserving plain Codex names would require moving the canonical
`CODEX_HOME`, fragmenting assumptions shared by Codex, account balancing,
voice profiles, session indexing, and the desktop app. Patching Fx to ignore
compatibility roots would leave the resources globally available to other
consumers and would not meet the ownership boundary.

Repository-local `skills/` directories remain source code. Fx may discover
them when run inside a fleet checkout; this decision removes installed global
leakage, not workspace-local source visibility.
