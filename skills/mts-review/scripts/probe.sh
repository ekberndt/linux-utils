#!/usr/bin/env bash
# Run the cheap tells from references/failure-library.md against a repo.
#
# Read-only: greps and prints, touches nothing. Each check is
# "trigger present, expected mitigation absent" -> HIT. A HIT is a place to look,
# not a finding; confirm the mechanism by reading the code before writing it up.
#
# HIT and clear are not symmetric. A HIT means "no mitigation matched anywhere",
# which is a strong prompt to read. A clear means some regex matched somewhere in
# the repo, which a coincidental identifier can produce — so spot-read the clears
# on the checks that carry the most weight (D3, T1, E3) rather than trusting them.
#
# Usage: probe.sh [repo-root]

set -uo pipefail

ROOT=${1:-.}
[ -d "$ROOT" ] || { printf 'not a directory: %s\n' "$ROOT" >&2; exit 1; }

if command -v rg >/dev/null 2>&1; then
  hits() { rg --no-messages --color never -c -g '*.py' -e "$1" "$ROOT" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}'; }
  first() { rg --no-messages --color never -n --no-heading -m1 -g '*.py' -e "$1" "$ROOT" 2>/dev/null | head -1 | cut -c1-90; }
  anyfile() { rg --no-messages --color never -l -e "$1" "$ROOT" 2>/dev/null | head -1; }
else
  hits() { grep -rEl --include='*.py' -e "$1" "$ROOT" 2>/dev/null | wc -l; }
  first() { grep -rEn --include='*.py' -m1 -e "$1" "$ROOT" 2>/dev/null | head -1 | cut -c1-90; }
  anyfile() { grep -rEl -e "$1" "$ROOT" 2>/dev/null | head -1; }
fi

HIT_COUNT=0
NA_COUNT=0

# check <id> <label> <trigger-regex> <mitigation-regex>
check() {
  local id="$1" label="$2" trigger="$3" expect="$4"
  local t e
  t=$(hits "$trigger")
  if [ "$t" -eq 0 ]; then
    printf '  %-4s %-38s %s\n' "$id" "$label" "n/a"
    NA_COUNT=$((NA_COUNT + 1))
    return
  fi
  e=$(hits "$expect")
  if [ "$e" -gt 0 ]; then
    printf '  %-4s %-38s %s\n' "$id" "$label" "clear"
  else
    printf '  %-4s %-38s %s\n' "$id" "$label" "HIT"
    printf '  %-4s %-38s   %s\n' "" "" "$(first "$trigger")"
    HIT_COUNT=$((HIT_COUNT + 1))
  fi
}

printf '\nProbing %s\n' "$(cd "$ROOT" && pwd)"
printf 'trigger present + mitigation absent = HIT (a place to look, not a finding)\n'

printf '\nData pipeline\n'
check D1 "worker seeding" 'DataLoader\(|num_workers' 'worker_init_fn|get_worker_info|generator='
check D2 "sampler reshuffles per epoch" 'DistributedSampler' 'set_epoch'
check D3 "data position in checkpoint" 'def (save|_save)_checkpoint|torch\.save' 'sampler_state_dict|dataset_state_dict|dataloader_state_dict|sampler\.state_dict|dataset\.state_dict|dataloader\.state_dict|iterator_state|data_position'
check D4 "packing keeps doc boundaries" 'pack_sequences|packed_|concat.*documents|def pack' 'cu_seqlens|segment_ids|position_ids|document_mask|boundary'
check D6 "near-dupe dedup" 'dedup|deduplicat' 'minhash|MinHash|lsh|LSH|simhash|suffix_array'
check D7 "tokenizer pinned" 'from_pretrained|AutoTokenizer' 'tokenizer_hash|tokenizer_sha|revision=|tokenizer_version'

printf '\nTraining loop\n'
check T1 "atomic checkpoint write" 'torch\.save|save_checkpoint|save_file\(' 'os\.replace|os\.rename|\.rename\(|atomic'
check T3 "resume LR asserted" 'gradient_accumulation|accum_steps|accumulation_steps' 'assert.*lr|resumed_lr|check_lr|log.*resume.*lr'
check T5 "config agreed across ranks" 'init_process_group|torch\.distributed' 'all_reduce.*hash|config_hash|broadcast.*config|barrier.*config'
check T6 "step to sample provenance" 'for step|global_step' 'sample_id|shard_id|example_id|doc_id'
check T7 "throughput tracked" 'log_metrics|wandb\.log|\.log_dict|log_scalar' 'mfu|MFU|tokens_per_sec|tokens/s|samples_per_sec|throughput'
check T8 "master weights kept fp32" 'bfloat16|float16|\.half\(|autocast' 'master_weight|fp32|float32|GradScaler|mixed_precision'

printf '\nEval integrity\n'
check E1 "result bound to harness version" 'def (run_)?eval|evaluate\(|benchmark' 'harness_sha|harness_version|commit|git_sha|prompt_version'
check E3 "frozen reference run" 'def test_|pytest' 'reference_loss|golden|expected_loss|regression.*loss|tolerance'
check E4 "seed variance measured" 'seed' 'num_seeds|seeds=|across_seeds|seed_variance|std'
check E5 "token-weighted loss" 'loss\.mean\(\)|mean.*loss|reduce.*loss' 'num_tokens|token_count|sum.*tokens|weighted'

printf '\nOperational\n'
if [ -n "$(anyfile 'preempt|requeue|SIGTERM|SIGUSR')" ]; then
  printf '  %-4s %-38s %s\n' "T4" "preemption handled" "clear"
else
  printf '  %-4s %-38s %s\n' "T4" "preemption handled" "HIT"
  printf '  %-4s %-38s   %s\n' "" "" "no preemption/requeue handling found — check ckpt cadence vs restart rate"
  HIT_COUNT=$((HIT_COUNT + 1))
fi
if [ -n "$(anyfile 'debug|smoke|tiny|dev_|_dev|fast_dev')" ]; then
  printf '  %-4s %-38s %s\n' "O1" "tiny/debug config exists" "clear"
else
  printf '  %-4s %-38s %s\n' "O1" "tiny/debug config exists" "HIT"
  printf '  %-4s %-38s   %s\n' "" "" "no tiny/debug config found — time the smallest real run by hand"
  HIT_COUNT=$((HIT_COUNT + 1))
fi

printf '\nRepo signals (read, do not score)\n'
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '  reverts/hotfixes (180d):  %s\n' "$(git -C "$ROOT" log --since=180.days --grep='revert\|hotfix\|rollback\|hot fix' -i --oneline 2>/dev/null | wc -l)"
  printf '  churn leaders (180d):     %s\n' "$(git -C "$ROOT" log --since=180.days --name-only --pretty=format: 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s(%s) ", $2, $1}')"
else
  printf '  not a git repo — skipping history signals\n'
fi
printf '  TODO/FIXME/HACK:          %s\n' "$(hits 'TODO|FIXME|HACK|XXX')"

printf '\n%s HIT, %s n/a. Read the mechanism for each HIT in references/failure-library.md\n' "$HIT_COUNT" "$NA_COUNT"
printf 'before writing it up. A HIT you confirm as fine is worth one line under "checked and clear".\n\n'
