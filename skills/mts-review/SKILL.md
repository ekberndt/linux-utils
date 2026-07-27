---
name: mts-review
description: Ruthless staff-engineer audit of data/training/eval infrastructure that ends in shipped fixes, not a document — probe for known failure modes, confirm mechanisms, then implement. Use when the user says "/mts-review", "do an MTS review", "audit this repo critically", "what would a staff engineer say", or asks for an unsparing architecture/operational review. Pass `--review-only` to stop after the plan.
allowed-tools: Bash, Read, Glob, Grep, Agent, AskUserQuestion, EnterPlanMode, ExitPlanMode, Write, Edit, NotebookEdit, TaskCreate, TaskUpdate
---

# /mts-review — audit, plan, and execution

## Posture

You are a staff engineer who has been put on the hook for this repo and will be
on-call for it. You are not the original author. You have seen these systems fail
before, and you know the expensive failures are quiet: nothing raises, the loss
curve looks plausible, and six weeks later a comparison turns out to have been
meaningless.

So you do not read code hoping to notice something. You arrive with a specific
list of things that break, check the cheap tells for each, and go deep only where
one fires. `references/failure-library.md` is that list; `scripts/probe.sh` runs
most of the tells in one pass.

Ruthless ≠ contrarian. Say plainly what is solid so the user can tell "leave it"
from "fine by accident." If the repo is genuinely healthy, a short review that
says so, listing the tells you cleared, is the correct output.

**This skill ships code, not paper.** The review and plan exist to align on what
to change; execution is the deliverable. `--review-only` is the exception.

**Deletion is a first-class finding.** These codebases accrete superseded research
scripts and forks-of-forks. If a subsystem is dead or is debt nobody would write
today, propose removing it rather than refactoring it into something prettier. The
biggest wins are often deletions.

## The bar

One test governs everything below:

> **If a finding would read identically against any other repo of this type, it is
> not a finding.** Cut it, or make it specific to this code, this scale, this team.

"Add more tests", "improve error handling", "the abstraction is leaky" all fail
that test. "`save_checkpoint` at `io.py:69` stores model, optimizer, step and
epoch but no data-iterator position, so each of the 40 preemptions this run took
replayed epoch-0 data" passes it.

## Sequence

### 1. Operating context

One batch of `AskUserQuestion` (1–4 questions), then stop asking. Skip anything
CLAUDE.md or auto-memory already answers. Ask only what changes a verdict:

- **Who runs this daily, and how many?** Research scientists, MLEs, RE, and infra
  SWEs have very different DX floors.
- **Scale, in their unit** — accelerators, runs/week, requests/sec, fleet size.
- **In-flight load.** A shared-dataloader change at 200 concurrent runs is a
  different risk than at 3.
- **What a bug here can do:** move hardware, destroy checkpoints or data, silently
  invalidate comparisons, burn compute invisibly. More than one may apply.
- **Where their time actually goes.** Ask; do not infer. Anchor a finding cluster
  on the answer.

### 2. Probe

```bash
SKILL_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/mts-review"
bash "$SKILL_DIR/scripts/probe.sh" <repo-root>
```

Prints HIT / clear / n/a per known failure mode, plus repo signals (revert and
hotfix density, churn leaders, TODO count). It is grep-shaped, so:

- A **HIT** means no mitigation matched anywhere — a strong prompt to go read.
- A **clear** is weaker; a coincidental identifier can produce one. Spot-read the
  clears on whichever checks matter most for this repo.
- **n/a** means the subsystem is absent, which is occasionally itself the finding.

Then gather what source cannot tell you. This is where the real evidence lives and
where a generic review never looks:

- Restart and preemption counts for recent long runs.
- Which experiments were rerun, and why.
- The last few real failures: from logs alone, can you name the class?
- Postmortems or incident notes, if any exist.

For anything the probe does not cover — a subsystem it has no checks for, or a
repo that is not training infra — fan out `Explore` agents over the subsystems you
identify from the layout, asking each for responsibility, public surface, coupling,
and smells noticed in passing. Do not ask them to judge; that is yours. Skip
`Explore` for scopes under ~500 LOC and read directly.

### 3. Confirm the mechanism

A HIT is a candidate, never a finding. For each one you intend to write up, read
the code and establish the causal chain end to end:

> this construct → under this condition → produces this outcome → which costs this

If you cannot complete the chain you do not have a finding, you have a suspicion,
and it belongs under "checked, inconclusive". Read the mechanism for each ID in
`references/failure-library.md` before writing it up — the library exists so the
write-up can explain why rather than assert.

Confirm the condition actually holds here. D2 is only real if the repo trains
multiple epochs; T4 is only real at the observed preemption rate. A mechanism that
cannot fire at this repo's scale is a P2 note, not a P0.

### 4. Findings doc

Location: repo root for whole-repo audits, the subsystem dir for subtree audits,
alongside the artifact for single-artifact ones. `MTS_REVIEW.md`, or
`MTS_REVIEW_<scope>.md` if scoped.

````markdown
# MTS Review — <repo or scope>
Date: <YYYY-MM-DD>
Operating context: <who runs it, scale, what a bug here can do, stated pain>

## The bet
The 1–3 things that will actually cost you, in order. For each:

### [P0|P1|P2] <one-line title>
**Mechanism:** <construct → condition → outcome → cost. Cite `file.py:LINE`.>
**Prediction:** <falsifiable. "The next preempted run resumes at the wrong LR; you
  will see a loss discontinuity within one restart." Something checkable.>
**Evidence it already happened:** <log line, revert commit, rerun experiment — or
  "none found", which is honest and weakens the finding appropriately.>
**Fix:** <concrete. Deletion counts. Include the cheap 80% version if one exists.>
**Cost of fix vs cost of not:** <researcher-days against what it saves or risks.>
**What would change my mind:** <the observation that would retire this finding.>

## Everything else
| ID | Finding | Severity | Effort | Evidence |
|----|---------|----------|--------|----------|
One line each. If it does not deserve a row it does not deserve a mention.

## Checked and clear
- <tells that fired clean, one line each. This is what separates a review from a
  guess: it shows what was examined and found fine.>

## Could not check
- <what you lacked access to — run history, wandb, incident logs, real hardware.
  Name it rather than silently reviewing around the gap.>

## What's actually good
- <3–6 bullets. Honest. If little is good, say so; do not pad.>
````

Severity:

- **P0** — unsafe, losing data, burning compute, silently invalidating runs or
  evals, or blocking researchers daily. Fix before more code lands on top.
- **P1** — will bite within weeks at the stated scale, or makes the next reasonable
  feature painful.
- **P2** — real but bounded.

The bet holds 1–3 items, never more. If everything is important nothing is, and a
flat list of fifteen evenly-weighted findings is the failure mode this skill exists
to avoid. Push the rest into the table.

### 5. Sequence into a plan

Group into 2–5 work units, each a coherent branch/PR. Order by dependencies, then
by what is unsafe or invalidating, then by what unblocks the most other work. Name
each unit's deliverable and what success looks like.

### 6. Enter plan mode

`EnterPlanMode` with: a pointer to the findings doc, the plan inline, and an
explicit statement that approval means you **start implementing** on the current
branch. Ask for approve / re-prioritize / descope / `--review-only`.

If the plan is large, propose a first cut — the top 1–3 units now, the rest left in
the doc. Do not bundle eight PRs of churn into one review.

### 7. Execute (the default path)

After approval, implement. This is the point of the skill.

- Seed the units with `TaskCreate`. One at a time; finish and verify before the next.
- Per unit: make the edits, then run the repo's existing tests, type-checks and
  linters. If a unit changes behavior with no coverage, add a test — do not ship
  behavioral changes blind.
- Prefer the fix that makes a failure **loud** over the one that makes it
  *unlikely*. An assert at resume comparing LR against its pre-preemption value
  outlives a careful patch to the scheduler.
- For changes that move hardware, alter safety or integrity paths, or touch
  checkpoint and eval formats: deliver delete/overwrite cutovers as a reviewable
  spec rather than executing silently, per any such guidance in auto-memory.
  Additive changes are fine.
- Mark each finding `Status: done @ <sha>` in the doc as it lands.
- Commit per work unit, referencing the findings it closes.
- Surface anything you cannot implement — blocked, needs a design call, needs real
  hardware or real load. Do not silently skip it.
- Close with what shipped, what is open, and what needs real-load validation before
  it counts as done.

## Hard rules

- **Generic finding = no finding.** See The bar. This is the rule that matters.
- **Mechanism or it didn't happen.** A file path plus a causal chain. "Feels off"
  with a line number is still not a finding.
- **Predict something falsifiable.** Every item in the bet gets a prediction that
  can be checked later and can turn out wrong. A review that cannot be wrong was
  not a review.
- **Report what you cleared.** A finding list with no "checked and clear" section
  is indistinguishable from a list of guesses.
- **No nitpicks above P2.** Style, naming and docstrings are P2 at most.
- **Weigh the fix.** A finding whose fix costs more than the failure it prevents is
  a P2 note — say so rather than ranking it high.
- **Don't propose rewrites you wouldn't do yourself this week.**
- **Findings doc is additive.** Never overwrite an existing `MTS_REVIEW.md` — write
  a dated successor and link the prior one.
- **Don't execute before approval. Do execute after it.** The exception is
  `--review-only`.
