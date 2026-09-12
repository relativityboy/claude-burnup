#!/bin/bash
# claude-burnup — a burn-up status line for Claude Code.
# https://github.com/relativityboy/claude-burnup
#
# Shows: directory | git branch | model | context consumed | every rate-limit
# bucket Claude Code reports (5h session, weekly, and model-scoped weeklies when
# present), each with a projection of usage at reset if the current average rate
# continues.
#
# Bars are 10 full-block cells. Completed cells render at full band color; the
# in-progress cell is a FULL block whose brightness encodes percent-within-block:
# band RGB scaled by (10 + 9*r)% for r in 1..9 (19%..91%), snapping to 100% when
# the block completes. Empty cells are a fixed neutral-gray ░ baseline.
#
# Reads the JSON Claude Code passes on stdin, plus one local git query for the
# branch (the statusline schema carries no current-branch field) — no network,
# no credentials.
# Stdin schema: https://code.claude.com/docs/en/statusline.md

input=$(cat)
# Debug: set BURNUP_DEBUG=1 to dump the raw stdin JSON for inspection.
[ -n "$BURNUP_DEBUG" ] && printf '%s' "$input" > ~/.claude/statusline-last.json

JQ=${JQ:-$(command -v jq)}
if [ -z "$JQ" ]; then
  printf 'claude-burnup: jq not found (brew install jq / apt install jq)\n'
  exit 0
fi

# BSD (macOS) vs GNU date for epoch -> clock formatting
if date -r 0 +%s >/dev/null 2>&1; then DATE_BSD=1; else DATE_BSD=; fi
clock() { if [ -n "$DATE_BSD" ]; then date -r "$1" +%H:%M; else date -d "@$1" +%H:%M; fi; }

# Band colors as truecolor R;G;B triplets (computable gradients need real RGB).
LIME="0;255;0"        # <33: pure bright green
GRN="25;188;46"       # 33-59: mid green
YEL="230;185;0"       # 60-84: amber
RED="220;50;47"       # >=85: red
NULC="110;114;120"    # empty-cell baseline — fixed neutral so its visibility
                      # never depends on the color of the cell to its left
DIRC="140;144;150"    # directory segment: neutral gray, quieter than the model
BRNC="130;90;180"     # branch segment: muted dark purple
OVER=$'\033[1;91m'    # projections > 100%: bold bright red, distinct from band-red
CYA=$'\033[36m'; B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'
SEP=" ${D}|${X} "

fg() { printf '\033[38;2;%sm' "$1"; }

# consumed-percentage bands: lime <33, green <60, amber <85, red >=85
band_rgb() {
  if   [ "$1" -lt 33 ]; then printf '%s' "$LIME"
  elif [ "$1" -lt 60 ]; then printf '%s' "$GRN"
  elif [ "$1" -lt 85 ]; then printf '%s' "$YEL"
  else                       printf '%s' "$RED"; fi
}
color_for() { fg "$(band_rgb "$1")"; }
proj_color() { if [ "$1" -gt 100 ]; then printf '%s' "$OVER"; else color_for "$1"; fi; }

# bar <percent-filled> <R;G;B> -> 10 full-block cells; the in-progress cell's
# brightness encodes percent-within-block
bar() {
  local pct=$1 rgb=$2 full rem i out="" r g b scale
  [ "$pct" -gt 100 ] && pct=100
  [ "$pct" -lt 0 ] && pct=0
  full=$(( pct / 10 )); rem=$(( pct % 10 ))
  for ((i = 0; i < full; i++)); do out+="█"; done
  printf '%s' "$(fg "$rgb")${out}"
  if [ "$rem" -gt 0 ]; then
    IFS=';' read -r r g b <<<"$rgb"
    scale=$(( 10 + 9 * rem ))
    printf '%s' "$(fg "$(( r * scale / 100 ));$(( g * scale / 100 ));$(( b * scale / 100 ))")█"
  fi
  out=""
  for ((i = full + (rem > 0); i < 10; i++)); do out+="░"; done
  printf '%s%s%s' "$(fg "$NULC")" "$out" "$X"
}

# render_bucket <label> <used%> <reset-epoch> <window-seconds> -> appends to $line
render_bucket() {
  local lbl=$1 used=$2 reset=$3 window=$4 rgb seg elapsed proj secs
  rgb=$(band_rgb "$used")
  seg="${lbl} $(bar "$used" "$rgb") $(fg "$rgb")${used}%${X}"
  if [ "$reset" -gt "$now" ] 2>/dev/null; then
    elapsed=$(( window - (reset - now) ))
    # project at average rate; skip the first ~1/60th of a window (too noisy)
    if [ "$elapsed" -ge $(( window / 60 )) ]; then
      proj=$(( used * window / elapsed ))
      [ "$proj" -gt 999 ] && proj=999
      seg+=" ${D}→${X}$(proj_color "$proj")${proj}%${X}"
    fi
    if [ "$window" -le 18000 ]; then
      seg+=" ${D}⟳ $(clock "$reset")${X}"
    else
      secs=$(( reset - now ))
      if [ "$secs" -ge 86400 ]; then seg+=" ${D}⟳ $(( secs / 86400 ))d${X}"
      else seg+=" ${D}⟳ $(( secs / 3600 ))h${X}"; fi
    fi
  fi
  line+="${SEP}${seg}"
}

# abbrev_model <display name> -> compact form: family initial + version, so
# "Opus 4.8" -> O4.8 and "Haiku 4.5" -> H4.5. A context-window variant keeps its
# distinction ("Opus 5 (1M context)" -> O5·1M) because O5 and O5·1M are different
# budgets and the model segment is the only place that shows.
#
# NOTE(claude): derived, not table-driven — a model released after this script
# still abbreviates correctly instead of falling back to its full name. Anything
# without a version token (or an unrecognized shape) passes through untouched
# rather than being mangled into something wrong-but-confident.
abbrev_model() {
  local name=$1 base=$1 paren ctx="" fam="" ver="" w
  if [[ $name =~ \(([^\)]*)\)[[:space:]]*$ ]]; then
    paren=${BASH_REMATCH[1]}
    base=${name%%(*}
    [[ $paren =~ ([0-9]+[MmKk]) ]] &&
      ctx=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
  fi
  for w in $base; do
    if   [ -z "$ver" ] && [[ $w =~ ^[0-9]+(\.[0-9]+)?$ ]]; then ver=$w
    elif [ -z "$fam" ] && [[ $w =~ ^[A-Za-z] ]] && [ "$w" != "Claude" ]; then fam=$w
    fi
  done
  if [ -n "$fam" ] && [ -n "$ver" ]; then
    printf '%s%s%s' \
      "$(printf '%s' "${fam:0:1}" | tr '[:lower:]' '[:upper:]')" "$ver" "${ctx:+·$ctx}"
  else
    printf '%s' "$name"
  fi
}

# effort_suffix <level> -> slash-letter appended to the model segment. The
# escalation reads alphabetically at the tail: /l /m /h, then /x (xhigh),
# /y (max), /z (ultracode — the /effort value beyond max; the harness may
# only report it as xhigh, but if the string arrives it renders right).
# A level outside the known set passes through whole (F5/ultra) rather than
# being guessed at; no effort field means no suffix.
effort_suffix() {
  case "$1" in
    '')        ;;
    low)       printf '/l';;
    medium)    printf '/m';;
    high)      printf '/h';;
    xhigh)     printf '/x';;
    max)       printf '/y';;
    ultracode) printf '/z';;
    *)         printf '/%s' "$1";;
  esac
}

label_for() {
  case "$1" in
    five_hour) printf '5h';;
    seven_day) printf 'wk';;
    *) printf '%s' "${1#seven_day_}";;
  esac
}

model=$($JQ -r '.model.display_name // "?"' <<<"$input" 2>/dev/null)
effort=$($JQ -r '.effort.level // ""' <<<"$input" 2>/dev/null)
dir=$($JQ -r '.workspace.current_dir // .cwd // ""' <<<"$input" 2>/dev/null)
ctx_used=$($JQ -r '
  .context_window as $c |
  (($c.used_percentage // (if $c.remaining_percentage != null then 100 - $c.remaining_percentage else -1 end)) | round)
  ' <<<"$input" 2>/dev/null)
# classic buckets (objects with used_percentage), 5h first, weekly second
rate_lines=$($JQ -r '
  .rate_limits // {} | to_entries
  | map(select((.value | type) == "object" and (.value | has("used_percentage"))))
  | sort_by(if .key == "five_hour" then 0 elif .key == "seven_day" then 1 else 2 end)
  | .[] | [.key, ((.value.used_percentage // -1) | round), (.value.resets_at // 0)] | @tsv
  ' <<<"$input" 2>/dev/null)
# model-scoped weeklies (e.g. the Fable/Opus weekly). Claude Code defines
# rate_limits.model_scoped[] in its statusline schema; these segments appear
# automatically once your client populates it. resets_at is an ISO string here.
scoped_lines=$($JQ -r '
  .rate_limits.model_scoped // [] | .[] | select(.utilization != null)
  | [(.display_name // "model" | ascii_downcase), (.utilization | round),
     ((.resets_at // "")[0:19] | if . == "" then 0 else (strptime("%Y-%m-%dT%H:%M:%S") | mktime) end)]
  | @tsv' <<<"$input" 2>/dev/null)

now=$(date +%s)

# --- directory + git branch ---
# The branch comes from git, not stdin — the statusline JSON has no
# current-branch field (worktree.branch only exists in --worktree sessions).
# Absent segments keep one meaning each: no dir segment = no dir in the
# payload; no branch segment = not a git repo. A detached HEAD renders as
# @shortsha rather than silence, so a rebase/bisect doesn't look like main.
line=""
if [ -n "$dir" ]; then
  line+="$(fg "$DIRC")${dir##*/}/${X}${SEP}"
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    sha=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    [ -n "$sha" ] && branch="@${sha}"
  fi
  [ -n "$branch" ] && line+="$(fg "$BRNC")${branch}${X}${SEP}"
fi
line+="${B}${CYA}$(abbrev_model "$model")$(effort_suffix "$effort")${X}"

# --- context burn-up ---
if [ "$ctx_used" -ge 0 ] 2>/dev/null; then
  crgb=$(band_rgb "$ctx_used")
  line+="${SEP}ctx $(bar "$ctx_used" "$crgb") $(fg "$crgb")${ctx_used}%${X}"
else
  line+="${SEP}ctx ${D}–${X}"
fi

# --- quota buckets ---
if [ -n "$rate_lines" ]; then
  while IFS=$'	' read -r key used reset; do
    [ -z "$key" ] && continue
    if [ "$used" -ge 0 ] 2>/dev/null; then
      if [ "$key" = "five_hour" ]; then w=18000; else w=604800; fi
      render_bucket "$(label_for "$key")" "$used" "$reset" "$w"
    else
      line+="${SEP}$(label_for "$key") ${D}–${X}"
    fi
  done <<EOF
$rate_lines
EOF
else
  line+="${SEP}5h ${D}–${X}"
fi

# --- model-scoped weeklies ---
if [ -n "$scoped_lines" ]; then
  while IFS=$'	' read -r lbl used reset; do
    [ -z "$lbl" ] && continue
    render_bucket "$lbl" "$used" "$reset" 604800
  done <<EOF
$scoped_lines
EOF
fi

printf '%s\n' "$line"
