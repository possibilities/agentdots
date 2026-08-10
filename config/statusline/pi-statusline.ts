// Pi status line — the fleet statusline's pi renderer.
//
// AgentStart owns this file; ~/.pi/agent/extensions/agentstart-statusline.ts
// links at it. It draws the same fields in the same order as the claude
// renderer beside it, minus the two pi cannot know: Anthropic subscription
// rate limits, and which account a balanced launch picked (codex-swap pins
// pi's account by swapping auth in place, so nothing in the environment
// names it — claude-swap's CLAUDE_CONFIG_DIR has no counterpart here).
//
// Why: no type import from the pi package. Pi and Orca's OMP runtime expose
// the same extension API under different package names, so an extension that
// names either one only loads under that one. The structural interfaces below
// are the subset this file actually touches, all of it optional so a pi whose
// API has moved renders a shorter bar instead of throwing.

import { execFile } from "node:child_process"
import { readFileSync, realpathSync } from "node:fs"
import { basename, dirname, join } from "node:path"

interface Theme {
  fg(color: string, text: string): string
}

interface FooterData {
  getGitBranch(): string | null
  onBranchChange(callback: () => void): () => void
}

interface Ctx {
  cwd: string
  mode?: string
  model?: { id?: string; name?: string; contextWindow?: number }
  getContextUsage?(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined
  getThinkingLevel?(): string
  ui: {
    setFooter?(factory: unknown): void
  }
}

interface Api {
  on(event: string, handler: (event: unknown, ctx: Ctx) => void | Promise<void>): void
  getThinkingLevel?(): string
}

const SEP = " │ "

/** Git facts for one working tree, all from the single status call below. */
interface GitState {
  project: string
  branch: string
  dirty: boolean
  ahead: number
  behind: number
  insertions: number
  deletions: number
}

const EMPTY_GIT: GitState = {
  project: "",
  branch: "",
  dirty: false,
  ahead: 0,
  behind: 0,
  insertions: 0,
  deletions: 0,
}

function runGit(cwd: string, args: string[]): Promise<string> {
  return new Promise((resolve) => {
    try {
      execFile(
        "git",
        ["-C", cwd, "--no-optional-locks", ...args],
        { encoding: "utf8", timeout: 2_000, maxBuffer: 256 * 1024 },
        (error, stdout) => resolve(error ? "" : stdout),
      )
    } catch {
      resolve("")
    }
  })
}

async function probeGit(cwd: string): Promise<GitState> {
  const [status, shortstat, topLevel] = await Promise.all([
    runGit(cwd, ["status", "--porcelain=v2", "--branch"]),
    runGit(cwd, ["diff", "--shortstat"]),
    runGit(cwd, ["rev-parse", "--show-toplevel"]),
  ])
  if (status === "") return { ...EMPTY_GIT, project: basename(cwd) || cwd }

  const state: GitState = { ...EMPTY_GIT, project: basename(topLevel.trim()) || basename(cwd) || cwd }
  let oid = ""
  for (const line of status.split("\n")) {
    if (!line.startsWith("#")) {
      if (line.trim() !== "") state.dirty = true
      continue
    }
    const [, key, ...rest] = line.split(" ")
    if (key === "branch.oid") oid = rest[0] ?? ""
    if (key === "branch.head") state.branch = rest[0] ?? ""
    // `branch.ab` is signed: `+2 -1`. An unpublished branch omits the line.
    if (key === "branch.ab") {
      state.ahead = Number.parseInt(rest[0] ?? "0", 10) || 0
      state.behind = Math.abs(Number.parseInt(rest[1] ?? "0", 10) || 0)
    }
  }
  // Git spells a detached head as the literal `(detached)`; name the commit
  // instead, the way the claude renderer does.
  if (state.branch === "(detached)") state.branch = oid === "" ? "" : `@${oid.slice(0, 7)}`
  state.insertions = Number.parseInt(shortstat.match(/(\d+) insertion/)?.[1] ?? "0", 10)
  state.deletions = Number.parseInt(shortstat.match(/(\d+) deletion/)?.[1] ?? "0", 10)
  return state
}

/**
 * Pi's own version. It is not on the extension API, so it comes from the
 * package that owns the running entry point.
 *
 * Why realpath first: pi is normally launched through an npm/nvm bin symlink,
 * and node keeps that launcher path in argv — walking its parents searches the
 * bin tree instead of the installed package. Resolving the link first anchors
 * the walk in the package, while a bundled binary or a direct dist/cli.js
 * launch stays valid.
 *
 * An unresolved version renders no segment rather than a guess: the bar would
 * otherwise state a version the operator cannot act on.
 */
function resolveVersion(entryPath: string = process.argv[1] ?? ""): string {
  let anchor = entryPath
  try {
    anchor = realpathSync(entryPath)
  } catch {
    // A moved install or a transient launcher path still gets the walk below.
  }
  let dir = dirname(anchor)
  for (let depth = 0; depth < 8; depth++) {
    try {
      const pkg = JSON.parse(readFileSync(join(dir, "package.json"), "utf8")) as {
        name?: unknown
        version?: unknown
      }
      // Pi and Orca's OMP runtime publish the same agent under different
      // names, so match the shared suffix rather than either exact name.
      if (typeof pkg.name === "string" && pkg.name.includes("coding-agent") && typeof pkg.version === "string") {
        return pkg.version
      }
    } catch {
      // Keep walking toward the package root.
    }
    const parent = dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  return ""
}

/** 452094 -> 452k, 1000000 -> 1.0M — the claude renderer's `human`. */
function human(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`
  if (value >= 1_000) return `${Math.floor(value / 1_000)}k`
  return `${value}`
}

/** Percentage -> the theme's ok / warn / alert colors, on claude's thresholds. */
function heat(percent: number, warn: number, alert: number): string {
  if (percent >= alert) return "error"
  if (percent >= warn) return "warning"
  return "success"
}

export interface RenderInput {
  git: GitState
  model: string
  effort: string
  contextPercent: number | null
  contextTokens: number | null
  contextWindow: number
  version: string
}

/** Exported for the render test; pi itself only calls the installer below. */
export function renderStatusLine(input: RenderInput, theme: Theme): string {
  const sep = theme.fg("dim", SEP)
  const parts: string[] = []

  if (input.git.project !== "") parts.push(theme.fg("accent", input.git.project))

  if (input.git.branch !== "") {
    let segment = theme.fg("muted", input.git.branch)
    if (input.git.dirty) segment += theme.fg("warning", "●")
    if (input.git.ahead > 0) segment += theme.fg("dim", ` ↑${input.git.ahead}`)
    if (input.git.behind > 0) segment += theme.fg("dim", ` ↓${input.git.behind}`)
    parts.push(segment)
  }

  if (input.model !== "") {
    let segment = theme.fg("text", input.model)
    if (input.effort !== "") segment += ` ${theme.fg("dim", input.effort)}`
    parts.push(segment)
  }

  if (input.contextPercent !== null) {
    const percent = Math.round(input.contextPercent)
    let segment = theme.fg(heat(percent, 60, 80), `${percent}%`)
    segment += theme.fg("dim", " ctx")
    if (input.contextWindow > 0 && input.contextTokens !== null) {
      segment += theme.fg("dim", ` ${human(input.contextTokens)}/${human(input.contextWindow)}`)
    }
    parts.push(segment)
  }

  if (input.git.insertions !== 0 || input.git.deletions !== 0) {
    parts.push(theme.fg("success", `+${input.git.insertions}`) + " " + theme.fg("error", `-${input.git.deletions}`))
  }

  if (input.version !== "") parts.push(theme.fg("dim", input.version))

  return parts.join(sep)
}

export default function (pi: Api): void {
  // Resolved once: the running package cannot change mid-session.
  const version = resolveVersion()
  let git: GitState = EMPTY_GIT
  let requestRender = (): void => {}
  let refresh = (_ctx: Ctx): void => {}
  let installed = false

  const install = (ctx: Ctx): void => {
    // The footer is a TUI surface. A headless run (pi exec, an RPC client)
    // has no setFooter and must be left exactly as it was.
    if (installed || ctx.mode !== "tui" || typeof ctx.ui.setFooter !== "function") return
    installed = true

    refresh = (target: Ctx): void => {
      void probeGit(target.cwd)
        .then((next) => {
          git = next
          requestRender()
        })
        .catch(() => {})
    }

    ctx.ui.setFooter((tui: { requestRender(): void }, theme: Theme, footerData: FooterData) => {
      requestRender = () => tui.requestRender()
      const unsubscribe = footerData.onBranchChange(() => {
        refresh(ctx)
      })
      return {
        dispose: unsubscribe,
        invalidate(): void {},
        render(): string[] {
          const usage = ctx.getContextUsage?.()
          return [
            renderStatusLine(
              {
                // The branch pi already watches beats the probe's copy: it is
                // pushed on checkout, while the probe only catches up on the
                // next turn.
                git: { ...git, branch: footerData.getGitBranch() ?? git.branch },
                model: ctx.model?.name ?? ctx.model?.id ?? "",
                effort: ctx.getThinkingLevel?.() ?? pi.getThinkingLevel?.() ?? "",
                contextPercent: usage?.percent ?? null,
                contextTokens: usage?.tokens ?? null,
                contextWindow: usage?.contextWindow ?? ctx.model?.contextWindow ?? 0,
                version,
              },
              theme,
            ),
          ]
        },
      }
    })
    refresh(ctx)
  }

  // A custom footer is cosmetic: pi must stay usable if any of this throws.
  const guard = (handler: (ctx: Ctx) => void) => async (_event: unknown, ctx: Ctx): Promise<void> => {
    try {
      handler(ctx)
    } catch {
      // Leave pi's own footer in place.
    }
  }

  pi.on("session_start", guard(install))
  // The diff counters and the dirty flag only move when the agent edits, so
  // a turn boundary is the cheapest honest moment to re-probe git. Install
  // is idempotent; a session that started headless and never gets a footer
  // simply keeps returning here.
  pi.on("turn_end", guard((ctx) => {
    install(ctx)
    refresh(ctx)
  }))
}
