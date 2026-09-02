# 2026-09-02 15:18 — Brainstorm: git branch in the status line

Mode: brainstorming (superpowers:brainstorming), bounded path. No code changed yet.

## The ask (Donovan)

Add the git branch to the status line.

## What I established (primary sources, not memory)

- **Live payload** (`~/.claude/statusline-last.json`, fresh today, CC 2.1.252): no branch
  field. `workspace` now carries `repo{host,owner,name}` and optionally `git_worktree`,
  but not the checked-out branch.
- **Binary 2.1.258 schema doc-comment** (read via `strings`): confirms it. The only
  branch-shaped fields are `worktree.branch` / `worktree.original_branch` (present only in
  `--worktree` sessions) and `pr` (open-PR metadata). A normal session's stdin never says
  what branch you're on.

**Conclusion:** unlike the July asks, this one can't come from stdin — the script has to
ask git itself. That amends the header's "reads only the JSON on stdin" contract; the
security-relevant half (no network, no credentials) survives untouched.

## Proposed design (awaiting Donovan's yes)

- One `git -C "$dir" branch --show-current` call, `$dir` = `workspace.current_dir`
  (fallback `cwd`). Chosen over parsing `.git/HEAD` by hand: git handles worktrees,
  subdirectories, and detached HEAD correctly, and the script already spawns jq four
  times per render — one more ~5ms process at a ≤3.3Hz refresh is nothing.
- Segment right after the model: `F5 | main | ctx ...`, dim-styled so quota colors stay
  dominant. No label, no glyph — a branch name is self-evident.
- Not a repo / git missing → segment omitted entirely.
- Detached HEAD → dim short SHA prefixed `@` (rebase/bisect shouldn't render as
  silence — absence must keep meaning exactly one thing: "not a repo").
- Always shown, including on main. Only-when-not-main would make absence ambiguous
  (two meanings), which is the silent-swallow family this project exists to avoid.
- No truncation of long names for now — Donovan's own July principle ("don't spend
  information to buy space unless the trade adds something"); revisit if it bites.
- Tests: `tests/branch_test.sh` — temp git repos as fixtures (on-branch, detached,
  non-repo dir), driving the real script end-to-end like `abbrev_test.sh` does. Red
  first, then implement.
- Docs: README segment table + example line; header comment contract line amended.

## Pre-existing state noted

README.md, claude-burnup.sh, tests/abbrev_test.sh and the July brainstorm note are
staged-but-uncommitted (the abbreviation feature awaiting Donovan's review/commit).
This work stacks on top of that in the working tree.

---

# Implementation log (appended 2026-09-02)

## What Donovan decided

- Design approved as proposed, plus two additions mid-flight:
  - a **directory segment**, placement `<dir> | <branch> | <model> | ...`
  - a **trailing `/`** on the dir, so it reads as a path.

## What changed

- `claude-burnup.sh`: `dir` extracted from `workspace.current_dir // cwd`; new
  dir + branch block before the model segment. Dir = basename + `/`, bold cyan
  (the new left anchor). Branch = dim, from `git -C "$dir" branch --show-current`;
  detached HEAD falls back to `@$(git rev-parse --short HEAD)`. No dir in payload →
  both segments omitted (degenerate output unchanged); not a repo → branch omitted.
  Header comment reworded — the on-stdin-only contract is now "stdin plus one local
  git query; no network, no credentials."
- `tests/branch_test.sh`: 5 cases — on-branch, slashed feature branch, detached,
  non-repo dir, no-dir payload — built on temp `git init` repos, driving the real
  script end-to-end like abbrev_test does.
- `README.md`: intro, contract line, example line + two segment-table rows,
  git listed as optional requirement, Tests section covers both suites.
- `~/.claude/statusline-claude.sh` (Donovan's live fork, outside the repo): same
  block ported surgically — it has no `abbrev_model` and carries the OAuth
  usage-endpoint fallback, so no overwrite. Backup at
  `<session scratchpad>/statusline-claude.sh.bak-2026-09-02`.

## Verification (TDD, red first)

- branch_test red: 4/5 failing for the right reason (dir cases render only model),
  the no-dir case passing trivially and correctly. Green after implementation.
- Trailing-slash request: test updated first, watched red on exactly the slash,
  then the one-character fix. 5/5 green; abbrev 9/9 green (regression).
- Real-payload regression: old (staged) vs new output — everything from the model
  segment onward byte-identical, ANSI included.
- Degenerate inputs `{}`, `{"model":{}}`, `{"cwd":"/private/tmp"}` — no crash;
  the last correctly renders `tmp/` with no branch segment.
- Live fork smoke-tested against the real captured payload: renders
  `claude-burnup/ | main | Fable 5 | ...` with its fable-fallback segment intact.

## Decisions and why

- **git subprocess over parsing `.git/HEAD`**: git handles worktrees, subdirs and
  detached HEAD correctly; the script already spawns jq four times per render.
- **Detached HEAD shows `@shortsha`, never silence**: absence must keep exactly one
  meaning ("not a repo") — the silent-swallow rule applied to a readout.
- **Always show the branch, even `main`**: hiding the default branch would give
  absence two meanings.
- **No truncation**: Donovan's July principle — don't spend information to buy
  space unless the trade adds something.
- **Local fork edited, not replaced**: it has real divergences (OAuth fallback,
  pinned jq, unconditional debug dump). Surgical block, backup kept.

## Vis tweaks (Donovan, after functional sign-off)

- Dir: gray (`DIRC="140;144;150"`), replacing bold cyan — no more competing with
  the model segment for the anchor role.
- Branch: muted dark purple (`BRNC="130;90;180"`), replacing dim. Detached
  `@shortsha` inherits it.
- Both as named truecolor triplets beside the band colors, so they're tweakable
  the same way; README's Customize section updated to name them. Same edits
  ported to the live fork. Tests unaffected (they strip ANSI) — 14/14 green.

## Known stale

~~`default_colors.png` now trails the rendered line by two features.~~ Resolved:
Donovan supplied a fresh screenshot (`img.png`, copied over `default_colors.png`,
staged). It's from his live fork, so it shows the dir/branch/colors but the
unabbreviated model name ("Fable 5" where the repo script renders "F5") — his
call, flagged at the time. `img.png` left untracked in the root as his scratch.

Follow-up: Donovan asked for the abbreviation ported to the fork too (he'd
wondered if the script was symlinked — it never was, and can't be while the fork
carries the credential-touching fable fallback the public script's contract
excludes). `abbrev_model()` copied verbatim into `~/.claude/statusline-claude.sh`
and applied at the model segment; smoke-tested on the real payload (`F5`, fallback
intact) plus the `O5·1M` and pass-through shapes. He retook the screenshot with
`F5` showing; copied over `default_colors.png` and staged — the earlier
"unabbreviated model in the image" caveat no longer applies.
