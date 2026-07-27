# Failure library — data, training, and eval infrastructure

Failure modes that have bitten real training stacks, each with the **mechanism**
(why the code produces it), the **tell** (how to confirm or clear it in seconds),
and the **blast radius** (what it costs when it fires).

Run the tells first — `scripts/probe.sh` automates most of them. Go deep only
where one fires. A tell that clears is worth one line in the findings doc under
"checked and clear"; silence reads as "didn't look."

Tells are written for PyTorch-shaped repos because that is what most of these
stacks are. Translate freely — the mechanism is the durable part, the grep is not.

---

## Data pipeline

### D1. Dataloader workers share a seed

**Mechanism:** each worker process inherits the parent seed. Without
`worker_init_fn` (or a framework that does it for you), every worker draws the
same augmentation/sampling stream, so a `num_workers=8` run sees 8 copies of the
same randomness rather than 8 independent streams.

**Tell:** `DataLoader(` present with `num_workers` > 0 and no `worker_init_fn`
and no `generator=`. Also check for `torch.initial_seed()` or
`torch.utils.data.get_worker_info()` inside the dataset's `__iter__`.

**Blast radius:** silently reduces effective data diversity. Does not crash, does
not show in loss curves early, invalidates any comparison against a run with a
different worker count.

### D2. `DistributedSampler` without `set_epoch`

**Mechanism:** `DistributedSampler` derives its shuffle from `self.epoch`, which
stays 0 unless the train loop calls `sampler.set_epoch(epoch)`. Every epoch
replays the identical order.

**Tell:** `grep -rn "DistributedSampler"` hits, `grep -rn "set_epoch"` does not.
This is one of the highest-yield greps in the library — it is a two-line bug that
survives for months because nothing fails.

**Blast radius:** multi-epoch runs train on a fixed ordering. Degrades final
quality in a way attributed to hyperparameters for weeks.

### D3. Resharding double-counts or skips on resume

**Mechanism:** the sampler indexes by shard index and offset; a reshard changes
shard boundaries, so a checkpoint's saved position points somewhere else in the
new layout. Resumed runs re-see or skip a slice.

**Tell:** does the manifest carry a content hash and sample count per shard? Does
the checkpoint store dataset state (`state_dict` on the iterator) or just a step
number? Does anything assert `observed_samples == manifest_count` at epoch end?

**Blast radius:** duplicate data inflates memorization and corrupts held-out
guarantees; skipped data is invisible. Neither shows up as an error.

### D4. Packed sequences leak across document boundaries

**Mechanism:** documents are concatenated to fill a fixed context length. Without
a document-boundary mask (or `cu_seqlens` into a varlen attention kernel, or
`reset_position_ids`), tokens attend across the boundary into an unrelated
document.

**Tell:** find the packing/concatenation code. Does the collator emit a boundary
mask, segment ids, or `cu_seqlens`? Does position-id construction restart per
document? If packing exists and none of these do, it leaks.

**Blast radius:** trains a subtly different objective than intended. Deniable,
hard to attribute, and every downstream comparison inherits it.

### D5. Mixture weights renormalize silently

**Mechanism:** a data mixture is configured as per-source weights. One source is
empty, misconfigured, or exhausted; the sampler renormalizes the rest so training
proceeds at proportions nobody chose.

**Tell:** does anything log or assert the *realized* mixture (counts per source
over the last N steps) against the configured weights? Configured-only logging is
not evidence.

**Blast radius:** the run that was supposed to be 30% code is 8% code, and the
ablation against it is meaningless.

### D6. Exact-hash dedup against near-dupe contamination

**Mechanism:** dedup and eval-decontamination use exact hashing (`sha256` of
normalized text). Near-duplicates — reformatted, whitespace-shifted, translated,
templated — pass straight through.

**Tell:** is dedup exact-hash or minhash/LSH/suffix-array? Is the eval set held
out *before* dedup runs, or filtered from the corpus after?

**Blast radius:** benchmark numbers that do not survive contact with a clean
holdout. Invalidates external comparisons, not just internal ones.

### D7. Tokenizer drift between prep, train, and eval

**Mechanism:** the tokenizer is loaded by name or path at each stage. A vocab or
special-token change between stages means the model is evaluated under different
tokenization than it trained on.

**Tell:** is a tokenizer hash/version recorded in the shard manifest *and* the
checkpoint *and* the eval config? Loading `AutoTokenizer.from_pretrained(name)`
in three places with no pinning is the failure.

**Blast radius:** eval regressions with no code change. Days lost before anyone
suspects the tokenizer.

---

## Training loop

### T1. Non-atomic checkpoint writes

**Mechanism:** the checkpoint is written in place. A preemption or OOM mid-write
leaves a truncated file that looks present. Worse when sharded: rank 3's shard is
from step N, rank 5's from step N-1.

**Tell:** write-to-temp-then-`os.replace`? Is there a manifest written *last*
that lists the expected shards and the step? Any `fsync` before rename? Does
resume validate the manifest against what is on disk?

**Blast radius:** discovering the last three checkpoints are corrupt, at the
moment you need them.

### T2. Data position not in the checkpoint

**Mechanism:** the checkpoint holds model, optimizer, and step, but not the data
iterator's position. Resume restarts the stream from the top.

**Tell:** grep the save/load path for sampler or dataset `state_dict`. If the
checkpoint dict has no data key, resume re-reads from the beginning.

**Blast radius:** a run preempted 40 times has seen epoch-0 data 40 times and the
tail never. Compounds with D3.

### T3. Schedule keyed to the wrong step counter

**Mechanism:** LR schedule, warmup, or EMA advance per micro-batch while the
checkpoint stores optimizer steps (or vice versa). With gradient accumulation the
two differ by the accumulation factor, so resume lands at the wrong LR.

**Tell:** find the scheduler `.step()` call. Is it inside or outside the
accumulation boundary? Does the resumed LR get logged and compared against the
pre-preemption value? A one-line assert at resume catches this permanently.

**Blast radius:** a visible loss discontinuity at every resume, usually
misattributed to data.

### T4. Checkpoint cadence below preemption rate

**Mechanism:** checkpoint interval exceeds mean time between preemptions, so the
run loses more progress to rollback than it makes.

**Tell:** checkpoint interval from config; preemption frequency from the job
scheduler's history or the run's restart count. If restarts-per-day × interval
approaches wall-clock, the run is net-negative.

**Blast radius:** the single most expensive quiet failure in the library — burns
accelerator-months while looking like a slow run.

### T5. Rank divergence at startup

**Mechanism:** ranks read config from env, local files, or a rank-dependent path.
One rank gets a different batch size, dtype, or data slice. Collectives then hang
or, worse, complete with mismatched semantics.

**Tell:** is there an all-reduce or all-gather of a config hash at init? Is the
resolved config logged from every rank or only rank 0? Rank-0-only logging hides
this class entirely.

**Blast radius:** NCCL timeouts that read as network faults and are debugged as
such for days.

### T6. No step-to-sample provenance

**Mechanism:** a loss spike appears at step 41,213. Nothing maps that step back to
shard, sample ids, or source, so the bad data cannot be found.

**Tell:** are sample or shard ids logged per step (even sampled 1-in-1000)? Is
there a documented way to reconstruct the batch at step N?

**Blast radius:** every spike becomes an unfalsifiable argument about
hyperparameters instead of a data bug you can excise in an hour.

### T7. Throughput regression invisible

**Mechanism:** no MFU / tokens-per-second-per-device metric, or it is logged but
never alerted on. A dataloader or collator change costs 30% and nobody notices
because loss curves look fine.

**Tell:** is a throughput metric emitted per step? Is there any regression gate,
or a reference value in CI? "It is in wandb" is not a gate.

**Blast radius:** proportional and permanent compute waste.

### T8. Master weights silently downcast

**Mechanism:** mixed precision keeps an fp32 master copy. A refactor casts it, or
an optimizer state is stored in bf16, so updates below the epsilon vanish.

**Tell:** grep optimizer construction and any `.to(dtype)` / `.half()` /
`.bfloat16()` near parameter or optimizer-state handling. Check whether the
framework's own mixed-precision wrapper is bypassed.

**Blast radius:** slow quality degradation with no error, usually blamed on data.

---

## Eval and experiment integrity

### E1. Harness version not bound to the result

**Mechanism:** results are stored as numbers without the harness commit, prompt
template version, or decoding params. Comparisons silently span harness changes.

**Tell:** does a stored result record harness SHA, prompt/template version, and
sampling params? If results are a CSV of task→score, they do not.

**Blast radius:** every historical comparison becomes unreliable at once, and the
loss is retroactive.

### E2. Judge model drift

**Mechanism:** an LLM judge is referenced by a moving alias. The endpoint updates;
prior scores are no longer commensurable.

**Tell:** is the judge pinned to an immutable version string? Is there a fixed
calibration set re-scored on judge change to measure the shift?

**Blast radius:** the whole eval history rebases without anyone deciding to.

### E3. No frozen reference run

**Mechanism:** nothing detects that a refactor changed numerics. Refactors ship
on the argument that tests pass, but the tests do not cover loss trajectory.

**Tell:** is there a tiny-model, fixed-seed, fixed-data run whose loss at step N
is asserted in CI within a tolerance? This is the single highest-value test an
infra stack can have and it is usually absent.

**Blast radius:** determines whether "did this refactor change training?" is a
five-minute question or an unanswerable one.

### E4. Seed sensitivity unmeasured

**Mechanism:** two configs are compared at one seed each and the difference is
reported as an effect.

**Tell:** does any result carry a seed-variance estimate, or does the repo have a
convention for how many seeds a claim needs?

**Blast radius:** the team chases differences smaller than their own noise floor.

### E5. Token-weighted metrics averaged per batch

**Mechanism:** per-batch losses are averaged with equal weight while batches hold
unequal token counts (variable-length, packed, or dropped-remainder).

**Tell:** find the metric aggregation. Is it `sum(loss * tokens) / sum(tokens)` or
`mean(batch_losses)`? Check eval and train separately — they often differ.

**Blast radius:** small persistent bias in the headline number, in the direction
of whichever batches are short.

---

## Operational and velocity

### O1. Debug loop too slow to keep attribution

**Mechanism:** the smallest configuration that exercises the real code path takes
long enough that researchers batch several changes per run.

**Tell:** is there a documented tiny config (1 GPU or CPU, small model, seconds to
first loss)? Time it. If none exists, that absence *is* the finding.

**Blast radius:** attribution loss. Every failure then implicates N changes at
once, and debugging cost grows superlinearly.

### O2. Failure class not distinguishable from logs

**Mechanism:** OOM, NCCL timeout, bad shard, preemption, and code bug all surface
as the same stack trace into framework internals.

**Tell:** take the last few real failures from the job history. From the logs
alone, can you name the class? Ask the operator how they usually tell.

**Blast radius:** every failure costs an expert instead of a runbook.

### O3. Config knob exists in several places

**Mechanism:** the same value is settable in YAML, CLI, and env, with precedence
that is undocumented or inverted between entry points.

**Tell:** pick the three most-tuned knobs (LR, batch size, sequence length). Grep
each. Count the places it can be set and whether the resolved value is logged.

**Blast radius:** silent misconfiguration, and experiments that cannot be
reproduced from their recorded config.

### O4. Shared-code blast radius unbounded

**Mechanism:** a change to a shared dataloader, collator, or trainer lands with no
way to scope it to one team's runs.

**Tell:** is there any versioning, flag, or pinning by which an in-flight run
holds an old code path? Do runs record the commit they ran?

**Blast radius:** determines whether a bad merge costs one run or all of them.

---

## Where to look beyond the code

Source alone cannot answer most of the above. Ask for, or derive:

- `git log --grep` over revert / hotfix / rollback / "fix ckpt" — repeated
  reverts in one directory locate the fragile subsystem faster than reading it.
- Restart and preemption counts for recent long runs (T4, T2).
- The last three postmortems or incident notes, if any exist.
- Which experiments got rerun, and why (E1, E3 usually).
- Where the operator says their time actually goes — ask, do not infer.
