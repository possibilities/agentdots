#!/bin/bash
# Claude Code status line — the fleet statusline's claude renderer.
#
# Agentdots owns this file; ~/.claude/statusline.sh links at it and
# scripts/install-statusline points Claude's settings.json here. The pi
# renderer beside it draws the same fields in the same order from pi's
# extension API; codex has no custom renderer, so the installer picks the
# closest ordered subset of its built-in status line items instead.
#
# Renders: directory + git, model, effort, context usage, cost, diff size,
# subscription rate limits, and the balanced account.
#
# The payload arrives on stdin as JSON. Orca also consumes that payload to feed
# its own session telemetry, so it is forwarded verbatim before anything is
# rendered. Dropping that forward blanks out Orca's view of this session.

payload=$(cat)
[ -z "$payload" ] && exit 0

orca_statusline="$HOME/.orca/agent-hooks/claude-statusline.sh"
if [ -r "$orca_statusline" ] && [ -x "$orca_statusline" ]; then
  printf '%s' "$payload" | /bin/sh "$orca_statusline" >/dev/null 2>&1 || :
fi

# Fields are joined on US (0x1f), not tab: tab counts as IFS whitespace, so bash
# would collapse runs of them and shift every field after an empty one.
US=$'\x1f'

# One jq pass; every field defaulted so a partial payload still renders. Thinking
# is tested against false rather than defaulted with //, which reads an explicit
# false as absent. No # comments inside the jq program: bash misparses them in a
# command substitution inside a heredoc.
IFS="$US" read -r CUR_DIR PROJ_DIR MODEL EFFORT CTX_PCT CTX_IN CTX_MAX \
  COST ADDED REMOVED RL5 RL5_AT RL7 RL7_AT FAST THINK STYLE VERSION <<EOF
$(printf '%s' "$payload" | jq -j '[
  (.workspace.current_dir // .cwd // ""),
  (.workspace.project_dir // ""),
  (.model.display_name // "?"),
  (.effort.level // ""),
  (.context_window.used_percentage // -1),
  (.context_window.total_input_tokens // 0),
  (.context_window.context_window_size // 0),
  (.cost.total_cost_usd // 0),
  (.cost.total_lines_added // 0),
  (.cost.total_lines_removed // 0),
  (.rate_limits.five_hour.used_percentage // -1),
  (.rate_limits.five_hour.resets_at // 0),
  (.rate_limits.seven_day.used_percentage // -1),
  (.rate_limits.seven_day.resets_at // 0),
  (if .fast_mode then 1 else 0 end),
  (if .thinking.enabled == false then 0 else 1 end),
  (.output_style.name // "default"),
  (.version // "")
] | map(tostring) | join("\u001f")' 2>/dev/null)
EOF
if [ -z "$MODEL" ]; then
  # jq missing or payload unparseable: fall back to something rather than a blank bar.
  printf '%s\n' "$(pwd)"
  exit 0
fi

R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
BLU=$'\033[34m'; MAG=$'\033[35m'; CYN=$'\033[36m'
SEP="${D} │ ${R}"

# Percentage -> green / yellow / red.
heat() {
  if   [ "$1" -ge "$3" ]; then printf '%s' "$RED"
  elif [ "$1" -ge "$2" ]; then printf '%s' "$YEL"
  else printf '%s' "$GRN"; fi
}

# 452094 -> 452k, 1000000 -> 1.0M
human() {
  if   [ "$1" -ge 1000000 ]; then printf '%d.%dM' $(($1 / 1000000)) $((($1 % 1000000) / 100000))
  elif [ "$1" -ge 1000 ];    then printf '%dk' $(($1 / 1000))
  else printf '%d' "$1"; fi
}

# Seconds until a reset timestamp, as 6d3h / 2h12m / 47m.
# Silent on a past or implausible timestamp rather than printing a garbage span.
until_reset() {
  local left=$(( $1 - $(date +%s) ))
  [ "$left" -le 0 ] && return
  [ "$left" -gt 2592000 ] && return
  if   [ "$left" -ge 86400 ]; then printf '%dd%02dh' $((left / 86400)) $(((left % 86400) / 3600))
  elif [ "$left" -ge 3600 ];  then printf '%dh%02dm' $((left / 3600)) $(((left % 3600) / 60))
  else printf '%dm' $((left / 60)); fi
}

# "5h 92% 1h04m" -- the countdown appears only once a window is half spent.
limit_seg() {
  local label=$1 pct=$2 at=$3 seg
  seg="${D}${label}${R} $(heat "$pct" 50 80)${pct}%${R}"
  if [ "$pct" -ge 50 ]; then
    local left; left=$(until_reset "$at")
    [ -n "$left" ] && seg+=" ${D}${left}${R}"
  fi
  printf '%s' "$seg"
}

# --- directory, relative to the project root when nested inside it ---
dir="$CUR_DIR"
if [ -n "$PROJ_DIR" ] && [ "$CUR_DIR" = "$PROJ_DIR" ]; then
  dir="${PROJ_DIR##*/}"
elif [ -n "$PROJ_DIR" ] && [ "${CUR_DIR#"$PROJ_DIR"/}" != "$CUR_DIR" ]; then
  dir="${PROJ_DIR##*/}/${CUR_DIR#"$PROJ_DIR"/}"
else
  dir="${CUR_DIR/#$HOME/\~}"
fi
out="${B}${CYN}${dir}${R}"

# --- git: branch, dirty flag, ahead/behind, all from one status call ---
if [ -d "$CUR_DIR" ]; then
  IFS="$US" read -r g_head g_oid g_ahead g_behind g_dirty <<EOF
$(cd "$CUR_DIR" 2>/dev/null && git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null | awk '
  /^# branch\.oid /  { oid = substr($3, 1, 7) }
  /^# branch\.head / { head = $3 }
  /^# branch\.ab /   { ahead = $3; behind = $4 }
  !/^#/              { dirty = 1 }
  END { printf "%s\037%s\037%s\037%s\037%d", head, oid, ahead, behind, dirty }')
EOF
  if [ -n "$g_head" ]; then
    [ "$g_head" = "(detached)" ] && g_head="@${g_oid}"
    out+="${SEP}${MAG}${g_head}${R}"
    [ "$g_dirty" = "1" ] && out+="${YEL}●${R}"
    [ -n "$g_ahead" ] && [ "$g_ahead" != "+0" ] && out+=" ${D}↑${g_ahead#+}${R}"
    [ -n "$g_behind" ] && [ "$g_behind" != "-0" ] && out+=" ${D}↓${g_behind#-}${R}"
  fi
fi

# --- model, effort, mode flags ---
out+="${SEP}${B}${MODEL/ (1M context)/ 1M}${R}"
case "$EFFORT" in
  max)    out+=" ${RED}${EFFORT}${R}" ;;
  xhigh)  out+=" ${MAG}${EFFORT}${R}" ;;
  high)   out+=" ${YEL}${EFFORT}${R}" ;;
  "")     ;;
  *)      out+=" ${D}${EFFORT}${R}" ;;
esac
[ "$FAST" = "1" ] && out+=" ${YEL}⚡${R}"
[ "$THINK" = "0" ] && out+=" ${D}no-think${R}"
[ "$STYLE" != "default" ] && out+=" ${D}${STYLE}${R}"

# --- context window ---
if [ "$CTX_PCT" -ge 0 ] 2>/dev/null; then
  out+="${SEP}$(heat "$CTX_PCT" 60 80)${CTX_PCT}%${R}${D} ctx"
  [ "$CTX_MAX" -gt 0 ] && out+=" $(human "$CTX_IN")/$(human "$CTX_MAX")"
  out+="${R}"
fi

# --- cost and diff size ---
out+="${SEP}${GRN}\$$(printf '%.2f' "$COST")${R}"
if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
  out+="${SEP}${GRN}+${ADDED}${R} ${RED}-${REMOVED}${R}"
fi

# --- subscription rate limits ---
limits=""
[ "$RL5" -ge 0 ] 2>/dev/null && limits=$(limit_seg 5h "$RL5" "$RL5_AT")
if [ "$RL7" -ge 0 ] 2>/dev/null; then
  [ -n "$limits" ] && limits+=" "
  limits+=$(limit_seg 7d "$RL7" "$RL7_AT")
fi
[ -n "$limits" ] && out+="${SEP}${limits}"

# --- harness version ---
[ -n "$VERSION" ] && out+="${SEP}${D}${VERSION}${R}"

# --- balanced account ---
# claude-swap pins an account by pointing CLAUDE_CONFIG_DIR at a per-account
# profile named <n>-<slugified-email>, so the leading number is the account's
# position in `cswap list` and needs no call back into the swap tools. An
# unbalanced launch leaves the variable unset and renders no segment.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  account="${CLAUDE_CONFIG_DIR##*/}"
  account="${account%%-*}"
  case "$account" in
    "" | *[!0-9]*) ;;
    *) out+="${SEP}${BLU}claude-${account}${R}" ;;
  esac
fi

printf '%s\n' "$out"
