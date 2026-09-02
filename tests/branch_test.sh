#!/bin/bash
# Directory + branch segment tests for claude-burnup.
#
# Runs the real script against fixture stdin, with temp git repos as the
# working directories, so the test exercises the same git lookup a status
# line refresh does. Run: bash tests/branch_test.sh

SCRIPT="$(dirname "$0")/../claude-burnup.sh"
fail=0

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# render <current_dir or empty> -> full line, ANSI stripped
render() {
  local ws=""
  [ -n "$1" ] && ws=$(printf '"workspace":{"current_dir":%s},' "$(printf '%s' "$1" | jq -R .)")
  printf '{%s"model":{"display_name":"Fable 5"}}' "$ws" \
    | "$SCRIPT" \
    | sed $'s/\033\\[[0-9;]*m//g'
}

# check <label> <current_dir or empty> <expected 'dir | branch | model' prefix>
check() {
  local got
  got=$(render "$2" | awk -F' \\| ' -v n=3 '{
    out=$1; for (i=2; i<=n; i++) if ($i != "") out=out" | "$i; print out }')
  got=${got%% | ctx*}
  if [ "$got" = "$3" ]; then
    printf 'ok    %-18s -> %s\n' "$1" "$got"
  else
    printf 'FAIL  %-18s -> %s (want %s)\n' "$1" "$got" "$3"
    fail=1
  fi
}

# --- fixtures ---

# a repo on a branch
mkdir "$TMP/repo"
git -C "$TMP/repo" init -q -b main
git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit --allow-empty -q -m x

# a repo with a slashed feature branch (no truncation)
mkdir "$TMP/feat"
git -C "$TMP/feat" init -q -b feature/mobile-controls-v2
git -C "$TMP/feat" -c user.email=t@t -c user.name=t commit --allow-empty -q -m x

# a repo with detached HEAD
mkdir "$TMP/det"
git -C "$TMP/det" init -q -b main
git -C "$TMP/det" -c user.email=t@t -c user.name=t commit --allow-empty -q -m x
git -C "$TMP/det" checkout -q --detach
sha=$(git -C "$TMP/det" rev-parse --short HEAD)

# a plain directory, no repo
mkdir "$TMP/plain"

# --- cases ---

# dir basename (with trailing /) + branch + model, in that order
check 'on a branch'    "$TMP/repo"  'repo/ | main | F5'
check 'slashed branch' "$TMP/feat"  'feat/ | feature/mobile-controls-v2 | F5'

# detached HEAD shows the short sha, not silence
check 'detached HEAD'  "$TMP/det"   "det/ | @${sha} | F5"

# not a repo: dir still shows, branch segment omitted
check 'non-repo dir'   "$TMP/plain" 'plain/ | F5'

# no dir in the payload at all: both segments omitted, model stays first
check 'no dir in JSON' ''           'F5'

[ "$fail" -eq 0 ] && printf '\nall passed\n' || printf '\nfailures\n'
exit "$fail"
