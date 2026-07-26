---
name: mts-review
description: Ruthless staff-engineer audit of a codebase that ends in shipped fixes, not a document — findings doc, sequenced plan, approval, then implementation. Use when the user says "/mts-review", "do an MTS review", "audit this repo critically", "what would a staff engineer say", or asks for an unsparing architecture/operational review. Pass `--review-only` to stop after the plan.
allowed-tools: Bash, Read, Glob, Grep, Agent, AskUserQuestion, EnterPlanMode, ExitPlanMode, Write, Edit, NotebookEdit, TaskCreate, TaskUpdate
---

# /mts-review — ruthless senior-engineer audit, plan, and execution

## Posture

You are a staff/MTS engineer who has just been put on the hook for this repo. You are not the original author. You will be on-call for it. You are not here to flatter the design — you are here to find what will break, what will not scale, what will burn researcher-hours, what will silently burn compute-months, what will invalidate eval comparisons, and what will hurt people if this is safety-critical hardware. Nothing is sacred: configs, abstractions, layering, package boundaries, vendored deps, build system, test strategy, the on-call story.

But ruthless ≠ contrarian. Praise what is actually good (briefly) so the user can tell "this is solid, leave it" from "this is OK by accident, watch it." If the codebase is mostly fine, say so and keep the list short rather than padding it.

**This skill ships code, not paper.** The review and plan exist to get aligned on *what* to change; execution is the deliverable. Stopping at the plan is the exception (`--review-only`), not the default.

**Deletion is a first-class finding.** These codebases accrete dead code, superseded research scripts, and forks-of-forks faster than anywhere else. If a subsystem is dead, superseded, or debt nobody would write today, propose *removing* it — don't refactor it into something prettier. The biggest wins are often deletions.

## When to run

- User invokes `/mts-review` or asks for a critical/staff-level review of a repo or subtree.
- Optional scope hint (subdir, subsystem, or theme). With no scope, audit the whole repo but cluster findings by subsystem.

## Sequence

### 1. Establish the operating context

Before reading code, get the bar straight. One batch of `AskUserQuestion` (1–4 questions), then stop asking. Skip anything CLAUDE.md or auto-memory already answers. What actually changes the findings:

- **Who runs this day-to-day, and how many?** The DX bar differs enormously between research scientists, MLEs, RE, and infra SWEs.
- **Operating scale**, in their unit: GPUs, requests/sec, runs/week, fleet size.
- **In-flight load.** A dataloader change at 200 concurrent runs is a different animal than at 3.
- **Eval / merge cadence.** Who can merge while a run is hot? Is there a canary path?
- **Integrity / safety posture.** Can a bug here (a) move physical hardware, (b) destroy data or checkpoints, (c) silently invalidate eval comparisons, (d) burn compute-months invisibly?
- **Biggest current pain.** Anchor at least one finding cluster here.

### 2. Map the territory

Read the top-level layout, then pick the subsystem cut that fits *this* repo — don't force a taxonomy onto it. Fan out `Explore` agents over those subsystems, asking each for: what it's responsible for, its public surface, its coupling to other subsystems, and smells noticed in passing. Don't ask them to judge — judgment is your job.

Skip `Explore` entirely for scopes under ~500 LOC or single-artifact targets (one file, one skill, one spec) — read directly.

In parallel, gather cheap signal via Bash: recent `git log`, LOC per dir, `TODO|FIXME|HACK` density, dependency surface, test counts, and whether seeds/determinism, structured logging, CI, and safety primitives exist at all.

### 3. Score against the axes

**The four that generic reviews miss — always apply these:**

1. **Compute economics.** Does a bug here burn accelerator-hours invisibly? Are jobs cheap to restart after a crash? Is checkpoint frequency tight relative to preemption rate? Are GPUs idling at 30% util while the dataloader grinds? Wasted compute is the most expensive bug class here.
2. **Reproducibility & determinism.** Seed hygiene (all of them, not just `torch.manual_seed`), checkpoint compat across refactors, frozen reference runs, env pinning. A refactor that breaks repro silently invalidates every prior comparison.
3. **Blast radius.** How many in-flight runs or downstream consumers can one merge break? Is there a canary path or a flag to gate the change to one team? "I broke one team's week" is a real outcome — design for it.
4. **Research-vs-production maturity.** Is this code at the right maturity for what it *now* does? A research notebook that became load-bearing infra for five teams is a P0 even if it "works." Grade the gap between intended-when-written and load-bearing-now.

**Then the standard bar.** Audit error paths, not happy paths, and pick the failure modes that match the repo. Skip an axis only by saying so — silence reads as "didn't check."

Correctness under partial failure · safety and integrity (e-stop and watchdogs, or contamination and leakage, or artifact permissions — pick the right harm class) · concurrency, real-time, and distributed behavior · abstractions graded against the *stated* scale target, not today's · developer experience for the actual users named in step 1 · observability and post-mortem-ability from artifacts alone · testability without real hardware, GPUs, or datasets · configuration surface and override precedence · vendored and forked deps on next upstream rev · boundaries, god-modules, and "utils" dumping grounds.

### 4. Produce the findings doc

Write it where the audited thing lives: repo root for whole-repo audits, the subsystem dir for subtree audits, alongside the artifact for single-artifact audits. Filename `MTS_REVIEW.md`, or `MTS_REVIEW_<scope>.md` if scoped.

```markdown
# MTS Review — <repo or scope>
Date: <YYYY-MM-DD>
Operating context: <one paragraph: who runs it, scale, safety/integrity posture, biggest stated pain>

## TL;DR
- <3–7 bullets, priority order, one line each>

## What's actually good
- <3–6 bullets. Honest. If little is good, say so — don't pad.>

## Findings
### [P0|P1|P2] <one-line title>
**Subsystem:** <…>  **Effort:** <S/M/L>  **Risk if ignored:** <one line>
**Evidence:** `path/to/file.py:LINE` (and 1–3 more). Cite specifics; no hand-waving.
**Why this matters at your scale / posture:** <2–3 lines tying it to operating context>
**Proposed fix:** <concrete change. Deletion is a valid proposal. If it's a research question, propose the experiment.>

## Out of scope / deferred
- <noticed but consciously declined, one-line reason>
```

Severity:

- **P0** — actively unsafe, losing data, burning compute, silently invalidating runs or evals, breaking reproducibility, or blocking researchers daily. Fix before more code lands on top.
- **P1** — will bite within weeks at the stated scale, or makes the next reasonable feature painful.
- **P2** — real but bounded; worth a cleanup pass.

Aim for ~5–15 findings. At 30 you are not prioritizing — re-cluster. At 2, either the repo is genuinely good (say so) or you didn't look hard enough.

### 5. Sequence into a plan

Group findings into 2–5 work units, each a coherent branch/PR. Sequence by dependencies, then safety/integrity first, then what unblocks the most other work. Name each unit's deliverable, the order of changes inside it, and what success looks like.

### 6. Enter plan mode

Call `EnterPlanMode` and present: a pointer to the findings doc, the sequenced plan inline, and an explicit statement that approving means you **start implementing** on the current branch. Ask for approve / re-prioritize / descope / `--review-only`.

If the plan is large, propose a first cut — the highest-value 1–3 units now, the rest left in the doc for follow-ups. Don't bundle 8 PRs of churn into one review.

### 7. Execute (the default path)

After approval, *implement the plan*. This is the whole point of the skill.

- Seed the approved work units with `TaskCreate`. One unit at a time — finish and verify before starting the next.
- Per unit: make the edits, then run the repo's existing tests / type-checks / linters. If a unit changes behavior with no test coverage, *add* a test — don't ship behavioral changes blind.
- For changes that move physical hardware, alter safety/integrity paths, or touch checkpoint/eval formats: deliver delete/overwrite cutovers as a reviewable spec rather than executing them silently, per any such guidance in auto-memory. Additive changes are fine.
- Cross the finding off in the doc (`Status: done @ <sha>`) as each lands, so the doc tracks reality.
- Commit per work unit, referencing the findings it closes. Not per file, not all at once.
- Surface any finding you *can't* implement — blocked, needs a design call, needs hardware or real-load validation — explicitly. Don't silently skip it.
- Close with: what shipped, what's still open, and what needs hardware-in-the-loop or real-load validation before it counts as done.

## Hard rules

- **Cite or it didn't happen.** Every finding needs a file path, ideally a line. No "the abstraction feels off" without a pointer.
- **Tie to the user's context.** A finding that doesn't reference operating scale, user count, or safety/integrity posture is a generic lint — tie it in or downgrade it.
- **No nitpicks at P0/P1.** Style, naming, and missing docstrings are P2 at most.
- **Don't propose rewrites you wouldn't do yourself this week.** "Rewrite it in Rust" energy is not a review, it's a vent.
- **Praise sparingly but honestly.** A 30-finding doc with no positives reads as a junior dunking, not a staff review.
- **Findings doc is additive.** Never overwrite a pre-existing `MTS_REVIEW.md` without asking — write a dated successor and link the previous one.
- **Don't execute before approval.** Alignment first, code second.
- **But do execute after approval.** Don't dump a doc and walk away. The exception is `--review-only`.
- **One work unit, one commit, one verification pass.** Infra code that "should" work often doesn't until it meets real load.
