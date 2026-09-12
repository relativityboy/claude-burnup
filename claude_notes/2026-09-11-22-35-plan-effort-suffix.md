# 2026-09-11 22:35 — Plan: effort level as model-segment suffix

## The ask (Donovan)

Show the session's reasoning-effort level. His notation: single letter after a
slash, immediately on the model signifier — `F5/x`.

## Established

- `effort.level` is in the statusline stdin (schema read from the 2.1.258 binary
  last week: `"low" | "medium" | "high" | "xhigh" | "max"`, optional — absent
  when the model doesn't support effort). His live payload tonight: `xhigh`.
- Mapping decided via AskUserQuestion: `low→/l, medium→/m, high→/h, xhigh→/x,
  max→/y` — max takes /y (next in sequence), **/z reserved** for a hypothetical
  future level above max.
- Unknown future level → full string after the slash (`F5/ultra`): closed-enum
  map with the same never-guess pass-through philosophy as abbrev_model.
- Absent field → bare model, no slash. Absence keeps one meaning: not reported.

## Plan

1. `tests/effort_test.sh` (red first): five levels, absent, unknown pass-through,
   and composition with the `O5·1M` context-variant form.
2. Implement: `effort` extraction + `effort_suffix()` case map; suffix rendered
   inside the model segment's bold cyan (one token: `F5/x`).
3. Regressions: abbrev + branch suites, real-payload before/after tail check.
4. README: example line + segment row + suffix mapping note.
5. Port to `~/.claude/statusline-claude.sh` (the live fork).
6. Append implementation log here; stage everything.

---

# Implementation log (appended 2026-09-11)

## Mid-plan addition (Donovan)

"There's also `ultracode` which is '/z'" — completing his original six-letter
sketch. Binary evidence: `/effort` accepts `ultracode` as a value ("Current
effort level: ultracode (xhigh + dynamic workflow orchestration)"), but it's
implemented as xhigh-plus-a-flag and the statusline schema's effort.level enum
stays five values — so with ultracode active the payload most likely still
reports `xhigh` → renders `/x`. The `ultracode → /z` case is wired anyway
(one line): if the level string ever arrives, it renders right. Empirically
testable later: run `/effort ultracode`, check the BURNUP_DEBUG dump.

## What shipped

- `claude-burnup.sh`: `effort` extracted from `.effort.level`; `effort_suffix()`
  case map rendered inside the model segment's bold cyan — `F5/x` as one token.
  Mapping: low/l, medium/m, high/h, xhigh/x, max/y, ultracode/z; unknown level
  passes through whole (`F5/ultra`); absent field → no suffix.
- `tests/effort_test.sh`: 9 cases — six mapped levels, unknown pass-through,
  absent field, composition with `O5·1M`.
- `README.md`: example line, model-segment row, "Effort suffix" subsection with
  the mapping table.
- Live fork (`~/.claude/statusline-claude.sh`): same three edits ported.

## Verification

- Red first: 8/9 failing for the right reason (absent-field case passing
  trivially and correctly). Green after implementation: 9/9.
- Regressions: abbrev 9/9, branch 5/5 — 23/23 total.
- Real payload (his session, effort xhigh): repo script and fork both render
  `claude-burnup/ | main | F5/x | ...`, fork's fable fallback intact.

## Decisions and why

- **max → /y, not /z** — Donovan's pick via AskUserQuestion: escalation order
  l→m→h→x→y, with /z as the value beyond max (then ultracode claimed it).
- **Suffix on the model segment, not its own labeled segment** — his notation
  (`F5/x`); effort is model-adjacent state and the line stays compact.
- **Case map, not derived** — the enum is closed and first-letter derivation
  collides (max/medium); pass-through covers the future honestly.

## Empirical result (same evening)

Donovan ran `/effort ultracode` live. The debug dump (22:58) reports
`effort.level: "xhigh"` — prediction confirmed: the harness decomposes
ultracode into xhigh + an orchestration flag and the statusline payload never
carries the word. His line reads `F5/x` under ultracode. `/z` stays wired but
unreachable until the harness exposes the flag (feedback drafted upstream).
Not worth groveling session-internal files from the fork to detect it — that's
undocumented-internals coupling for one letter.
