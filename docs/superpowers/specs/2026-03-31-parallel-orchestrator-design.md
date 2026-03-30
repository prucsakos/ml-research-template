# Parallel Orchestrator Design

**Date:** 2026-03-31
**Status:** Approved
**Scope:** `ml-research-template` — adds orchestrated multi-agent infrastructure alongside the existing `ralph-loop.sh`

---

## Overview

The parallel orchestrator extends the ralph loop pattern with a two-level agent hierarchy: an orchestrator LLM that reasons about research state and dispatches specialist agents, and specialist agents that execute focused units of work in parallel where safe.

The existing `ralph-loop.sh` (single agent, single prompt, repeated) is kept unchanged for simple use cases.

---

## Architecture

```
scripts/orchestrator.sh          — ralph loop wrapper + dispatch logic
scripts/lib/worktree.sh          — worktree create / merge / cleanup
scripts/lib/dispatch.sh          — parse <dispatch>, run agents, collect <result>
scripts/ralph-loop.sh            — unchanged

agents/
├── config.yaml                  — role → model mapping
├── orchestrator/system.md       — orchestrator system prompt
├── implementer/system.md
├── test-quality/system.md
├── performance/system.md
├── documentation/system.md
├── literature/system.md
└── research/system.md
```

---

## Two-Level Hierarchy

### Level 1 — Orchestrator (ralph loop)

Runs on `claude-sonnet-4-6` in a ralph loop (`--continue --print`). Each iteration:

1. Reads `DESIGN.md`, `PROGRESS.md`, `git log --oneline -10`, `pytest tests/ -q --fast`
2. Identifies independent vs dependent tasks using the module map in `DESIGN.md`
3. Outputs a `<dispatch>` block with task descriptions and file declarations
4. Writes `PROGRESS.md` after agents finish (agents never write to it directly)
5. Outputs `<promise>DONE</promise>` only when all `PROMPT.md` success criteria are met

The orchestrator is the research lead. It owns research direction, task decomposition, conflict resolution, and the introspection protocol.

### Level 2 — Specialist agents (one-shot)

Each specialist is a single `claude --print` invocation. It does not inherit the orchestrator's conversation history. It sees:

- Its role system prompt (`agents/<role>/system.md`)
- The task text the orchestrator wrote for it
- Whatever it reads from the filesystem

The orchestrator must therefore write self-contained task descriptions. Vague tasks produce wrong results.

---

## Communication Protocol

### Orchestrator → shell

```xml
<dispatch mode="parallel">
  <agent role="implementer"
         model="claude-haiku-4-5-20251001"
         task="Implement src/data_loader.py to pass tests/test_data_loader.py.
               Read DESIGN.md §Architecture first.
               Run: pytest tests/test_data_loader.py -q --fast after each change.
               Commit with message: feat: implement data_loader
               Do NOT modify any file outside src/data_loader.py and tests/test_data_loader.py."
         files="src/data_loader.py,tests/test_data_loader.py"/>
  <agent role="implementer"
         model="claude-haiku-4-5-20251001"
         task="Implement src/model.py to pass tests/test_model.py. ..."
         files="src/model.py,tests/test_model.py"/>
</dispatch>
```

`mode` is either `parallel` or `sequential`.

The `files` attribute declares every file the agent may read or write. The shell uses this for parallel safety enforcement.

### Agent → shell

```xml
<result>
  <status>DONE</status>
  <summary>Implemented data loader. 8/8 tests passing. Committed a1b2c3d.</summary>
  <files_changed>src/data_loader.py,tests/test_data_loader.py</files_changed>
</result>
```

**Status values:**

| Status | Meaning |
|---|---|
| `DONE` | Task complete, tests pass, committed |
| `DONE_WITH_CONCERNS` | Complete but agent flagged doubts — orchestrator reads summary |
| `NEEDS_CONTEXT` | Agent lacks information to proceed |
| `BLOCKED` | Agent cannot complete — orchestrator decides next steps |

---

## Shell Script Flow (`orchestrator.sh`)

```
for i in 1..MAX_ITERATIONS:

  1. ORCHESTRATOR CALL
     cat agents/orchestrator/system.md + PROMPT.md
       | claude --model <orchestrator_model> --continue --print --dangerously-skip-permissions
     → capture OUTPUT

  2. RATE LIMIT CHECK
     same logic as ralph-loop.sh — sleep 1h on rate limit, retry same iteration

  3. COMPLETION CHECK
     OUTPUT contains <promise>DONE</promise> → exit 0

  4. PARSE DISPATCH BLOCK
     extract mode, per-agent: role, model, task text, files

  5. PARALLEL SAFETY CHECK
     if mode=parallel AND any two agents declare overlapping files
       → downgrade to mode=sequential
       → log downgrade reason to stdout

  6. DISPATCH AGENTS
     parallel:
       for each agent:
         create worktree at .worktrees/<agent-role>-<iteration>-<n>
         run claude in background (&) inside that worktree
       wait for all background jobs
       for each worktree:
         attempt merge into main branch
         on success: delete worktree
         on conflict: leave worktree intact, write conflict details to PROGRESS.md

     sequential:
       for each agent in order:
         run claude, wait for completion

  7. COLLECT RESULTS
     parse each <result> block
     log BLOCKED / NEEDS_CONTEXT statuses to stdout for human visibility

  8. LOOP
     orchestrator sees updated filesystem state on next iteration
```

---

## Parallel Safety

Two rules enforced by the shell:

1. **File overlap → sequential**: If two agents in a `parallel` dispatch declare any file in common, the dispatch is automatically downgraded to sequential.

2. **Merge conflict → orchestrator decides**: On worktree merge failure:
   - Conflicting worktrees left intact at `.worktrees/<id>`
   - Conflict details written to `PROGRESS.md`
   - Orchestrator reads this on the next iteration and decides: resolution agent, task resequencing, or task rewrite

The shell never makes judgment calls about conflicts. That is the orchestrator's responsibility.

---

## Orchestrator System Prompt (`agents/orchestrator/system.md`)

This is the most critical file in the system. It must instruct the orchestrator to:

**On every iteration:**
1. Run orientation: read `DESIGN.md`, `PROGRESS.md`, `git log --oneline -10`, `pytest tests/ -q --fast`
2. Check for merge conflicts or BLOCKED agents in `PROGRESS.md` — address these first
3. Identify the next independent units of work using the module map in `DESIGN.md`
4. Write task descriptions that are explicit and self-contained (file paths, test commands, success criteria, what not to touch)
5. Declare `files` accurately — include every file the agent may read or write
6. After any experiment completes, dispatch the research agent for introspection before continuing implementation

**Task description quality standard:**
Every task must include:
- Target files (explicit paths)
- Test command and what passing looks like
- Files the agent must not touch
- Relevant context from `DESIGN.md` or `PROGRESS.md`
- Commit message format

**Completion:**
Output `<promise>DONE</promise>` only when every success criterion in `PROMPT.md` is met and `PROGRESS.md` is up to date.

---

## Agent Role System Prompts

Each specialist receives its role system prompt plus the task text written by the orchestrator. Prompts are stored in `agents/<role>/system.md`.

| Role | Model | Responsibility |
|---|---|---|
| `orchestrator` | sonnet | Research lead, task decomposition, conflict resolution |
| `implementer` | haiku | Write code to pass failing tests |
| `test-quality` | haiku | Improve test harness, add edge cases |
| `performance` | sonnet | Profile, identify bottlenecks, optimize |
| `documentation` | haiku | Keep PROGRESS.md, docstrings, DESIGN.md in sync |
| `literature` | opus | Review related work, flag relevant papers |
| `research` | opus | Introspection protocol, hypothesis interrogation, paper narrative |

Models are configured in `agents/config.yaml` and can be overridden per project.

---

## Config (`agents/config.yaml`)

```yaml
orchestrator: claude-sonnet-4-6
implementer:  claude-haiku-4-5-20251001
test-quality: claude-haiku-4-5-20251001
performance:  claude-sonnet-4-6
documentation:claude-haiku-4-5-20251001
literature:   claude-opus-4-6
research:     claude-opus-4-6
```

---

## Usage

```bash
# Edit PROMPT.md with task and success criteria, then:
./scripts/orchestrator.sh                    # default: 20 iterations
./scripts/orchestrator.sh -n 50             # more iterations
./scripts/orchestrator.sh -s                # run inside tmux (HPC/detached)
./scripts/orchestrator.sh -s -t my_session  # custom tmux session name
```

Remote monitoring (same as ralph loop — agents commit and push after each unit):
```bash
git log --oneline -20
git diff HEAD~5
```

---

## Relationship to ralph-loop.sh

| | `ralph-loop.sh` | `orchestrator.sh` |
|---|---|---|
| Use case | Simple, single-agent tasks | Multi-agent research projects |
| Agents | One agent, one prompt | Orchestrator + N specialists |
| Parallelism | None | Parallel when file-disjoint |
| State management | Agent writes PROGRESS.md | Orchestrator writes PROGRESS.md |
| Conflict handling | N/A | Orchestrator decides |

Both scripts read from `PROMPT.md` and both terminate on `<promise>DONE</promise>`.
