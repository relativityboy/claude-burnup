# 2026-07-26 17:16 — Brainstorm: subagent readouts, compact quota, model abbreviations

Mode: brainstorming (superpowers:brainstorming). No code changed yet.

## The ask (Donovan)

1. Change the readouts to the current agent when the TUI view switches to a subagent.
2. Show weekly & monthly quota usage as a % number only, same coloring.
3. Abbreviate model names (O5, F5, O4.8) to free horizontal space.

## What I established before designing (primary sources, not memory)

**Statusline stdin schema, Claude Code 2.1.220** — read from the shipped binary
(`strings` over `~/.local/share/claude/versions/2.1.220`, function `yRS`):

- Emits: `session_id, transcript_path, prompt_id, cwd, session_name, model{id,display_name},
  workspace, version, output_style, cost, context_window, exceeds_200k_tokens, fast_mode,
  effort, thinking, rate_limits, vim, agent, remote, pr, worktree`.
- `rate_limits` is built from `DYr()` and maps **only** `five_hour` and `seven_day`. The
  underlying header parser (`kOu`) also knows `seven_day_overage_included` and `overage`,
  but the statusline object never carries them.
- `agent: {name}` is `eB()` → `mainThreadAgentType`. Its setter `c_e()` is called only from
  `--agent` resolution, teammate activation, and main-thread agent switching. **Nothing in
  the statusline path reads `viewingAgentTaskId` / `viewSelectionMode`** (the store keys for
  "user switched the transcript view to a subagent"), and `messagesRef` is scoped to the main
  conversation id (`Mzf(Si())`).

**No monthly quota window exists in the client's model.** `/usage` renders "Current session",
"Current week (all models)", "Current week (Sonnet only)" (max/team), and scoped weeklies via
`FPt()` (`kind === "weekly_scoped"`). The only monthly figure anywhere is usage credits /
extra usage (`extra_usage{monthly_limit, used_credits, utilization}`) plus the
`anthropic-ratelimit-unified-overage-period-monthly-utilization` header — a spend meter, not
a quota window, and reachable only through `/api/oauth/usage`.

Donovan's own `/usage` confirmed it: session 10%, week (all models) 41%, week (Fable) 39%.
No monthly meter.

## The experiment (ask #1)

Sampled `~/.claude/statusline-last.json` every 3s for 6 minutes (45 distinct dumps captured),
spawned one subagent, and Donovan switched the TUI view to it.

- During the switch window this session's dumps kept updating (ctx 16% → 17%), so the
  statusline **was** refreshing while the agent view was up.
- Every dump was identical in shape: `model: "Opus 5 (1M context)"`, main-thread context,
  **no `agent` field**. Donovan independently reported "no difference in statusline."

**Verdict: blocked upstream.** Static analysis and live observation agree — the harness hands
the statusline no viewed-agent state. Donovan chose to skip the feature rather than fake it.

**Side finding worth keeping:** three live sessions (`4c375283` Opus 5, `e8172eaf` Opus 5,
`0458654d` Fable 5) were all clobbering the same debug dump file, because the local
`~/.claude/statusline-claude.sh` writes it unconditionally. The public `claude-burnup.sh`
gates it behind `BURNUP_DEBUG`, so the repo is fine — but that file cannot be trusted for
diagnosis on a multi-session machine.

## Where it stands

- Ask #1: dropped (harness limitation, Donovan's call).
- Ask #2: "monthly" doesn't exist; question outstanding on whether he meant the two weeklies
  (all-models + Fable) or usage credits. The *compaction* half — long-window meters as a
  colored % with no bar — is live and mocked.
- Ask #3: proposed a derived abbreviation (family initial + version) rather than a lookup
  table, so unreleased models abbreviate correctly instead of falling back to a raw name.
  Open question: how to mark the 1M-context variant, since `O5` and `O5·1M` are different
  context budgets.

Mockup of four layouts + three 1M markers written to the session scratchpad (`mock.sh`),
rendered in Donovan's own terminal for a real-color comparison. Awaiting his pick before
writing the design doc.

## Why this shape

The two asks that survived are cheap; the one that died died on evidence rather than on my
assertion, which is what the extra ~10 minutes of binary-reading and the live capture bought.
Designing an "agent readout" that silently showed main-thread numbers while claiming to show
the agent's would have been exactly the silent-swallow shape — a display that looks
authoritative and is wrong.

---

# Implementation log (appended 2026-07-26)

## What Donovan decided

- Ask #1 (subagent readouts): **skip** — the harness provides no viewed-agent state.
- Ask #2 (weekly/monthly): **leave the quota segments alone.** His reasoning, which is the
  better principle: *"we don't need to reduce to percentages since we're not adding
  information."* Don't spend information to buy space unless the trade adds something.
- Ask #3 (model abbreviations): **do it.**

So the shipped change is the abbreviation only.

## What changed

- `claude-burnup.sh`: new `abbrev_model()`, applied at the model segment. Derived rule —
  family initial + version — rather than a lookup table, so models released after this
  script abbreviate correctly instead of falling back to their full name. Names with no
  version token pass through untouched.
- `tests/abbrev_test.sh`: 9 cases, run against the real script with fixture stdin.
- `README.md`: example line, segment table, new "Model abbreviations" section, "Tests"
  section.

## Decisions and why

- **`O5·1M` rather than bare `O5`.** Dropping the parenthetical would lose information, and
  Donovan's own stated principle for this change is to not trade information for space.
  `O5` and `O5·1M` are different context budgets and the model segment is the only place
  that distinction appears. Called it myself instead of asking a third time; it's one line
  to change.
- **Derived rule over a lookup table.** A table is a maintenance obligation that silently
  degrades: the day a new model ships, an un-updated table renders the long name and the
  segment quietly stops doing its job. The derived rule fails visibly instead — an
  unrecognized shape passes through whole.
- **Pass-through on no-version names, not a guess.** Rendering something wrong-but-confident
  in a readout people trust at a glance is the failure mode this project exists to avoid.
- **`Claude` is skipped as a family word** so an older `Claude 3.5 Sonnet` style name gives
  `S3.5`, not `C3.5`.
- **bash 3.2 compatibility held** (stock macOS ships 3.2.57) — no `${var^^}`; `tr` does the
  uppercase, once per render.
- **Tests drive the real script with fixture stdin** rather than sourcing the function.
  Sourcing would block on the script's `input=$(cat)`, and the end-to-end path is what
  actually matters.

## Verification

- `bash tests/abbrev_test.sh` — red first (7 of 9 failing, the 2 pass-through cases passing
  trivially and correctly), then green after implementation, 9/9.
- Regression: ran the committed version and the new version against a real captured payload;
  everything after the model segment is byte-identical.
- Model-scoped weekly path re-checked with a synthetic `rate_limits.model_scoped` — unchanged.
- Degenerate inputs (`{}`, `{"model":{}}`, empty display name) — no crash, behavior unchanged.

## Known stale

`default_colors.png` still shows the pre-abbreviation model segment. Donovan's screenshot to
retake, or drop me a note and I'll set up a fixture render for it.
