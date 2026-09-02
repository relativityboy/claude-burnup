#!/bin/bash
# Model-name abbreviation tests for claude-burnup.
#
# Runs the real script against fixture stdin and checks the rendered model
# segment, so the test exercises the same path a status line refresh does.
# Run: bash tests/abbrev_test.sh

SCRIPT="$(dirname "$0")/../claude-burnup.sh"
fail=0

# check <display_name> <expected model segment>
check() {
  local got
  got=$(printf '{"model":{"display_name":%s}}' "$(printf '%s' "$1" | jq -R .)" \
        | "$SCRIPT" \
        | sed $'s/\033\\[[0-9;]*m//g' \
        | awk -F' \\| ' '{print $1}')
  if [ "$got" = "$2" ]; then
    printf 'ok    %-22s -> %s\n' "$1" "$got"
  else
    printf 'FAIL  %-22s -> %s (want %s)\n' "$1" "$got" "$2"
    fail=1
  fi
}

# family initial + version
check 'Fable 5'             'F5'
check 'Sonnet 5'            'S5'
check 'Opus 4.8'            'O4.8'
check 'Haiku 4.5'           'H4.5'

# context-window variants keep the distinction — O5 and O5·1M are different budgets
check 'Opus 5 (1M context)' 'O5·1M'
check 'Opus 5'              'O5'

# "Claude" is a prefix, not the family
check 'Claude 3.5 Sonnet'   'S3.5'

# nothing version-shaped to abbreviate: pass the name through rather than mangle it
check 'Some Future Model'   'Some Future Model'
check '?'                   '?'

[ "$fail" -eq 0 ] && printf '\nall passed\n' || printf '\nfailures\n'
exit "$fail"
