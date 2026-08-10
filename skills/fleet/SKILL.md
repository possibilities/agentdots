---
name: fleet
description: Show how the agent* apps in ~/code depend on each other, from the maintained map in this skill — CLI subprocess calls, skill routing, machine services, and pinned binaries, every edge with evidence. Use when asked what depends on what ("will changing X break Y", "who calls this tool", "fleet map", "how do the agent tools relate"), and before renaming a CLI, changing its flags, or retiring a tool — the blast radius is the incoming edges. The map is maintained, not generated; a change that adds a cross-tool call updates it in the same commit.
---

# Fleet

The dependency map of the agent ecosystem lives beside this file in
`MAP.md`: every known edge between the `~/code` fleet apps, in four kinds —
runtime subprocess calls, skill-to-skill routing, machine services, and
pinned binaries — each with the evidence that proves it.

## Answering with it

1. Read `MAP.md` (same directory). The mermaid diagrams are the overview;
   the edge tables underneath carry the evidence and the consequence of
   breaking each edge.
2. Answer blast-radius questions from the *incoming* edges of the changed
   tool: a CLI whose flags change breaks every solid-edge caller listed for
   it; a data-format change breaks the dotted readers.
3. When the question is about one tool, quote only its edges, not the whole
   map.

## Keeping it honest

The map is maintained, not generated: a change that adds or removes a
cross-tool call must update `MAP.md` in the same commit (AgentStart's
`AGENTS.md` makes this a rule). To verify an edge or hunt for new ones:

```sh
# subprocess edges: spawn sites naming another tool's binary
grep -rnE 'Bun\.spawn|spawn\(|execFile' ~/code/agent*/src \
  | grep -iE 'agentusage|agentwiki|agentscrape|codex-swap|agent-browser|"codex"'

# skill routing: one skill naming another. Verify from the surrounding
# sentence — agentboard, agentwiki, and agentbrain each have their OWN
# `search` subcommand that name-matches the search skill and is not it.
grep -rn 'skill' ~/code/agent*/skills/*/SKILL.md \
  | grep -iE 'scrape|search|brain|board|groom|wiki|browser|chats|keys'

# IPC edges spawn-greps miss: unix-socket conduits and injected env
grep -rn 'CONDUIT\|unix:' ~/code/agent*/src ~/code/funk/libexec 2>/dev/null | grep -v node_modules

# service edges: what funk's launchd points at
grep -rn 'agent' ~/code/agentstart/scripts/install-agent-clis
```

If a verified edge is missing from `MAP.md`, add it — edge, kind, evidence,
consequence — and note anything retired. Uncertain edges do not go on the
map; they go in the Unconfirmed section until proven.
