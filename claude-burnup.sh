#!/bin/bash
# claude-burnup — a burn-up status line for Claude Code.
# https://github.com/relativityboy/claude-burnup
#
# Shows: model | context consumed | every rate-limit bucket Claude Code reports
# (5h session, weekly, and model-scoped weeklies when present), each with a
# projection of usage at reset if the current average rate continues.
#
# Bars are 10 full-block cells. Completed cells render at full band color; the
# in-progress cell is a FULL block whose brightness encodes percent-within-block:
# band RGB scaled by (10 + 9*r)% for r in 1..9 (19%..91%), snapping to 100% when
# the block completes. Empty cells are a fixed neutral-gray ░ baseline.
#
# Reads only the JSON Claude Code passes on stdin — no network, no credentials.
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

label_for() {
  case "$1" in
    five_hour) printf '5h';;
    seven_day) printf 'wk';;
    *) printf '%s' "${1#seven_day_}";;
  esac
}

model=$($JQ -r '.model.display_name // "?"' <<<"$input" 2>/dev/null)
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
line="${B}${CYA}${model}${X}"

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
