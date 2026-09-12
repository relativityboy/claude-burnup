#!/bin/bash
# Effort-suffix tests for claude-burnup.
#
# Runs the real script against fixture stdin and checks the rendered model
# segment, so the test exercises the same path a status line refresh does.
# Run: bash tests/effort_test.sh

SCRIPT="$(dirname "$0")/../claude-burnup.sh"
fail=0

# check <display_name> <effort level or empty> <expected model segment>
check() {
  local eff="" got
  [ -n "$2" ] && eff=$(printf ',"effort":{"level":%s}' "$(printf '%s' "$2" | jq -R .)")
  got=$(printf '{"model":{"display_name":%s}%s}' "$(printf '%s' "$1" | jq -R .)" "$eff" \
        | "$SCRIPT" \
        | sed $'s/\033\\[[0-9;]*m//g' \
        | awk -F' \\| ' '{print $1}')
  if [ "$got" = "$3" ]; then
    printf 'ok    %-22s %-8s -> %s\n' "$1" "${2:-—}" "$got"
  else
    printf 'FAIL  %-22s %-8s -> %s (want %s)\n' "$1" "${2:-—}" "$got" "$3"
    fail=1
  fi
}

# the known levels: /l /m /h /x /y, plus /z for ultracode (the /effort value
# beyond max; the harness may only ever report it as xhigh, but if the level
# string arrives it renders right)
check 'Fable 5' 'low'       'F5/l'
check 'Fable 5' 'medium'    'F5/m'
check 'Fable 5' 'high'      'F5/h'
check 'Fable 5' 'xhigh'     'F5/x'
check 'Fable 5' 'max'       'F5/y'
check 'Fable 5' 'ultracode' 'F5/z'

# unknown future level: pass the string through rather than guess a letter
check 'Fable 5' 'ultra'  'F5/ultra'

# no effort reported: bare model, no slash
check 'Fable 5' ''       'F5'

# suffix composes with the context-variant form
check 'Opus 5 (1M context)' 'xhigh' 'O5·1M/x'

[ "$fail" -eq 0 ] && printf '\nall passed\n' || printf '\nfailures\n'
exit "$fail"
