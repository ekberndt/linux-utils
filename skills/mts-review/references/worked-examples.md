# Worked examples — the lenses applied

**This is not a checklist.** It is a set of examples showing what each lens in
`SKILL.md` finds when someone applies it carefully. Your repo's failures will be
different ones. Read these to calibrate what a lens *feels like* when it catches
something, then apply the lens — not this list — to the code in front of you.

Examples are drawn from ML infrastructure because that is the common case, but
each lens is domain-independent. The lens is the durable part; the example is
scaffolding.

---

## Lens 1 — Invariants

*What must be true for this to be correct? Where is that enforced? What happens
when it is violated — does anything notice?*

The pattern: a property the whole system depends on is established by convention
rather than by construction. Nothing enforces it, so it holds until someone
refactors, and then it silently doesn't.

**Every epoch should see a different data order.** `DistributedSampler` derives its
shuffle from `self.epoch`, which stays at 0 unless the training loop calls
`set_epoch`. The invariant is real, the enforcement is a line someone has to
remember, and nothing fails when they don't. Asking "where is this enforced?" finds
it in seconds; reading the training loop for smells does not.

**A checkpoint should represent one consistent moment.** Model, optimizer, step and
data position must come from the same instant. Sharded saves violate this when rank
3 writes at step N and rank 5 at step N−1; in-place writes violate it when a
preemption lands mid-write. The enforcement that works is structural — write to
temp, fsync, write a manifest last, validate it on load — not care.

**Scored text must equal sampled text.** In an RL loop the reward model has to see
exactly what the policy produced. Re-rendering a transcript from structured
messages breaks this invisibly. A five-line test asserting string equality enforces
it permanently; nothing else does.

**The realized data mixture should match the configured one.** Weights are
configured, then renormalized at runtime when a source is empty or exhausted. The
invariant holds only if something compares realized counts against config and
complains.

Applying the lens: list what the system assumes, then for each, find the line that
makes it true. If you cannot find one, that is a finding — and the fix is usually
an assert or a structural change, not vigilance.

---

## Lens 2 — Boundaries

*Where does state cross something? Enumerate the crossings, then ask what is
preserved and what is silently dropped at each.*

Bugs concentrate at boundaries because that is where one component's assumptions
meet another's. Enumerate them before reading code: process, machine, restart,
version, serialization, batch, time.

**The restart boundary.** What survives a preemption? Model and optimizer usually
do. Data position usually does not, so a run preempted forty times reads epoch-0
data forty times. Scheduler state is the other common casualty: an LR schedule
advanced per micro-batch, resumed from a checkpoint counting optimizer steps, lands
at the wrong learning rate — a visible discontinuity that gets blamed on data.

**The version boundary.** A tokenizer or chat template loaded by name at each stage
is three independent versions agreeing only by luck. Same for a judge model behind
a moving alias: prior scores stop being comparable and nothing announces it.

**The process boundary.** Dataloader workers inherit the parent's seed, so eight
workers draw one stream unless something reseeds per worker. Ranks read config from
their own environment, so one rank can disagree about batch size and the collective
hangs — reported as a network fault and debugged as one for days.

**The batch boundary.** Kernel selection and reduction order vary with batch shape,
so an output depends on what it was batched with. Documents packed into a fixed
context length attend across each other unless a boundary mask says otherwise.

**The serialization boundary.** Anything reconstructed rather than stored can drift
from the original — trajectories re-rendered from messages, configs recomposed from
defaults plus overrides.

Applying the lens: draw the crossings, then walk each one asking what is carried
and what is rebuilt. What gets rebuilt is where to look.

---

## Lens 3 — Detectability

*If this were wrong right now, how would anyone find out? Rank by silence.*

This lens usually produces the highest-value findings, because it evaluates the
system's ability to report its own failures — a capability that applies to every
future bug as well as today's.

Sort candidates into **crashes** (cheap, you find out immediately), **visibly
degrades** (moderate, someone notices a number moved), and **silently degrades**
(expensive, cost accrues until an unrelated investigation stumbles on it). Spend
your attention on the third.

**A throughput regression with no gate.** A collator change costs 30%. Loss curves
look fine. It is in the dashboard, and dashboards are not gates, so it persists
until someone happens to compare against an old run.

**A quality regression with no reference run.** Nothing detects that a refactor
changed numerics, because the tests assert shapes and types rather than a loss
value at step N. "Did this refactor change training?" becomes unanswerable instead
of a five-minute check.

**A spike with no provenance.** Step 41,213 has a loss spike and nothing maps a step
back to shards or sample ids, so the argument becomes about hyperparameters rather
than about the batch that caused it.

**Failures that all look alike.** OOM, collective timeout, bad shard, preemption and
a genuine bug all surface as the same framework stack trace. Every failure then
costs an expert rather than a runbook.

The strongest move this lens supports: when you find a bug, prefer the fix that
makes its whole class **loud** over the fix that makes this instance unlikely. An
assert comparing LR before and after resume outlives any careful patch to the
scheduler.

Applying the lens: for each finding, ask what signal would have caught it. If the
answer is "none", the missing signal is often the better finding.

---

## Lens 4 — Fit for current load

*What was this built for, and what is it doing now? The gap is where the P0s are.*

Code is written against an implied scale and an implied user. Both drift. The
question is not "is this good code" but "is this code at the right maturity for
what it now carries."

**A research script that became infrastructure.** Written for one person and one
experiment, now imported by five teams. It works. It is also a P0, because nothing
about it — error handling, config surface, blast radius — was designed for that
role. The finding is the mismatch, not the code quality.

**An abstraction sized for the old scale.** A design requiring a subclass per robot
type is fine at three robots and fails at fifty. Grade abstractions against the
stated target from the operating-context questions, not against today.

**Capacity planned on the average case.** Memory headroom sized against mean
sequence length OOMs on a burst of long requests. A checkpoint cadence chosen when
preemptions were rare goes net-negative when they are not: the run loses more to
rollback than it makes.

**A boundary that was cheap and is now hot.** A serialization step or a lock that
cost nothing at low volume and now dominates.

Applying the lens: ask what changed since this was written — scale, users, adjacent
systems — and check whether anything in the design moved with it. Usually nothing
did, and one or two of those gaps are the real story of the review.

---

## Lens 5 — Cost gradient

*Where do time, compute and money actually go? Does the design reflect that?*

Effort in a codebase tends to be distributed by when things were written rather
than by what they cost. This lens finds that mismatch, and it more often changes a
team's priorities than their code.

**Compute.** Idle accelerators are the most expensive quiet failure available.
Checkpoint cadence against preemption rate; whether the input pipeline keeps the
device fed; work redone after every restart.

**Researcher time.** How long from an idea to a signal? If the smallest run that
exercises the real path is slow, people batch changes and lose attribution, and
debugging cost grows superlinearly in the number of bundled changes. Ask where
their time goes rather than inferring it — the answer is frequently something
mundane like config resolution or queue waits.

**Rework.** Experiments rerun because a result could not be trusted. Each rerun is
a receipt for a missing invariant or a missing signal, and the pattern of reruns
points at which.

**Attention.** A component that requires one specific person is a cost even when it
never breaks.

Applying the lens: put the top three cost sinks next to where the codebase's
complexity actually sits. Where those disagree you have both a finding and an
argument for it that a reader will not dispute.

---

## Where to look beyond the code

Source cannot answer most questions these lenses raise. Ask for, or derive:

- `git log --grep` over revert / hotfix / rollback — repeated reverts in one
  directory locate the fragile subsystem faster than reading it does.
- Restart and preemption counts for recent long runs.
- Which experiments were rerun, and why.
- The last few real failures: from the logs alone, can you name the class?
- Postmortems or incident notes, if any exist.
- Where the operator says their time goes. Ask; do not infer.
