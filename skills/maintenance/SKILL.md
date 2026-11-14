---
name: maintenance
description: Run a maintenance pass over a repository's MAINTENANCE.md — check each item that drifts (pins, files copied from upstream, agent CLI config, OS-release workarounds, docs that restate code, and what a machine still holds from installs the repo has moved or dropped), update what is stale, verify it, and report. Use when the user says "/maintenance", "check MAINTENANCE.md", "maintenance pass", "keep the repo current", "clean up this machine", "what's stale", or asks to update pins or copied upstream files. Also the format to follow when writing or editing a MAINTENANCE.md.
---

# Maintenance

## Purpose

`MAINTENANCE.md` at a repository's root does for upkeep what `AGENTS.md` does
for editing: one file in a known place that any agent can act on with no other
context. It lists what drifts while nobody touches the code. A pass brings each
item back to current and proves it.

## The format

- Sections are triggers. `## Every pass` comes first; then one section per
  event, named for it: `## When Ubuntu ships a release the machines will run`,
  `## On each <tool> release`.
- A section can be scoped to a machine: `## On each machine, after <sync>`. Its
  items change the machine, not the repo, and replace migration code: a change
  that moves, renames or drops something the repo installs ships no cleanup
  for the old one, and this section finds and removes it.
- An item is a `###` heading naming the thing, then up to four bullets:
  - **Where:** the files, and the names inside them that drift.
  - **Check:** how to tell it is stale: a short command, or what to compare
    against which upstream source.
  - **Update:** only what "make it match" does not cover, including the
    decisions that belong to the user.
  - **Verify:** the test or command that proves the update.
- A table replaces the bullets when one item covers many file pairs; a list
  does when the items under an event are one line each.
- Facts, not history: no last-checked dates (git is the record), no narration
  of how an item was found. Name what to compare rather than pasting long
  scripts. Commands must run on every OS the section covers.
- A change that adds something that drifts adds its item in the same PR; a
  change that removes the thing deletes its item.

## Running a pass

1. Work in a worktree off freshly fetched `origin/main` (the `worktree` skill).
   Run the repo's tests and linters first, so a failure later is yours.
2. Work through `## Every pass`, and each event section whose event happened
   since the last pass (`git log --oneline --grep '^chore(maintenance)'` dates
   the last one).
3. For each item, run **Check**. If it is current, move on. If it is stale,
   apply **Update**, run **Verify**, and commit that item alone as
   `chore(maintenance): <item>`.
4. Machine sections differ: run them on that machine, in the primary checkout
   (the first line of `git worktree list`) on `main`, and commit nothing.
5. Stop and ask before any decision the file leaves to the user: switching a
   model, dropping an OS release, removing a package, or removing anything
   from a machine that is not plainly the repo's.
6. Read upstream with your web and `gh` tools and put downloads in
   `mktemp -d`. Give the user anything that needs `curl`, `rm`, `sudo`, or
   another machine as a `! <command>` line, saying what it does and why,
   rather than working around a denied command.
7. Fix the file itself as you go: an item that no longer applies is deleted, a
   wrong path or command is corrected.

## Report

Per item: current; updated (old → new); removed from the machine; stale but
left alone, and why; or not checkable here, and where it has to run. Then say
whether the branch is ready to land. Pushing and the PR wait for the `land`
skill.

A repository without `MAINTENANCE.md`: say so, and offer to write one in this
format from a survey of what it pins, copies, and works around.
