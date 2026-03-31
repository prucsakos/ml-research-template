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
├── config.yaml                  — role → model mapping (default models per role)
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

Runs on `claude-sonnet-4-6` in a ralph loop (`--continue --print`). The `--continue` flag resumes the same Claude Code session across iterations, allowing the orchestrator to maintain conversational context. This context grows over iterations; for very long runs (50+ iterations) users may need to start a fresh session if the context window becomes saturated.

Each iteration:

1. Reads `DESIGN.md`, `PROGRESS.md`, `git log --oneline -10`, and test status (see orientation note below)
2. Checks for unresolved merge conflicts or BLOCKED/NEEDS_CONTEXT agents recorded in `PROGRESS.md` — addresses these before new work
3. Identifies independent vs dependent tasks using the module map in `DESIGN.md`
4. Outputs a `<dispatch>` block with task descriptions and file declarations
5. After agents finish, writes a `PROGRESS.md` update (agents never write to it directly)
6. Outputs `<promise>DONE</promise>` only when all `PROMPT.md` success criteria are met

**Orientation note:** The orchestrator runs `pytest tests/ -q` for test status. The `--fast` flag is appended only if the project has registered it (i.e., `conftest.py` defines the `--fast` option). The orchestrator system prompt must instruct the orchestrator to run `pytest tests/ -q --fast 2>/dev/null || pytest tests/ -q` to gracefully fall back.

The orchestrator is the research lead. It owns research direction, task decomposition, conflict resolution, and the introspection protocol.

### Level 2 — Specialist agents (one-shot)

Each specialist is a single `claude --print` invocation without `--continue`. It starts with a clean session and does not inherit the orchestrator's conversation history. It sees:

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
               Run: pytest tests/test_data_loader.py -q after each change.
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

**`model` attribute:** If present, overrides the default from `agents/config.yaml` for this dispatch only. If omitted, the config.yaml value for the agent's role is used. The orchestrator may override models when a task requires more or less reasoning than the default.

**`files` attribute:** Comma-separated list of every file the agent may read or write. Used by the shell for parallel safety enforcement. Rules:
- File paths are matched as exact strings (relative to project root).
- Read-only shared files (e.g., `DESIGN.md`, `CLAUDE.md`) that multiple agents need but will not modify should be omitted — the conflict check is for write conflicts only. The orchestrator system prompt must instruct the orchestrator to only list files agents will write.
- Directory paths (e.g., `src/`) are not valid — list individual files.

### Agent → shell

```xml
<result>
  <status>DONE</status>
  <summary>Implemented data loader. 8/8 tests passing. Committed a1b2c3d.</summary>
  <files_changed>src/data_loader.py,tests/test_data_loader.py</files_changed>
</result>
```

**Status values:**

| Status | Meaning | Shell action |
|---|---|---|
| `DONE` | Task complete, tests pass, committed | Proceed normally |
| `DONE_WITH_CONCERNS` | Complete but agent flagged doubts | Log to stdout; orchestrator reads summary next iteration |
| `NEEDS_CONTEXT` | Agent lacks information to proceed — no changes made | Log to stdout; write to PROGRESS.md; orchestrator addresses next iteration |
| `BLOCKED` | Agent cannot complete — changes may be partial | Log to stdout; write to PROGRESS.md; orchestrator decides next steps |

For `NEEDS_CONTEXT` and `BLOCKED`, the shell writes a structured entry to `PROGRESS.md`:

```markdown
## Agent issue — iteration <N>
- **Status:** NEEDS_CONTEXT / BLOCKED
- **Role:** <role>
- **Task:** <first 100 chars of task text>
- **Summary:** <agent's summary from <result> block>
- **Worktree:** <path if applicable, else "main">
```

The orchestrator reads this on the next iteration and decides: re-dispatch with additional context, break the task into smaller pieces, or escalate to the human via `<promise>DONE</promise>` with an explanation.

---

## Shell Script Flow (`orchestrator.sh`)

```
for i in 1..MAX_ITERATIONS:

  1. ORCHESTRATOR CALL
     (cat agents/orchestrator/system.md; cat PROMPT.md)
       | claude --model <orchestrator_model> --continue --print --dangerously-skip-permissions
     → capture OUTPUT

  2. RATE LIMIT CHECK
     if OUTPUT matches rate limit patterns (same regex as ralph-loop.sh):
       sleep 3600
       continue (retry same iteration — implemented with a while loop, not for-loop decrement)

  3. COMPLETION CHECK
     OUTPUT contains <promise>DONE</promise> → exit 0

  4. PARSE DISPATCH BLOCK
     extract mode, per-agent: role, model (or default from config.yaml), task text, files

  5. PARALLEL SAFETY CHECK
     if mode=parallel:
       build file sets per agent
       if any two agents share a file → downgrade to mode=sequential
       log downgrade reason to stdout

  6. DISPATCH AGENTS
     parallel:
       for each agent (index n):
         WORKTREE=".worktrees/<role>-iter<i>-<n>-<timestamp>"
         create worktree at WORKTREE (timestamp prevents collision on retry)
         run claude --model <model> --print --dangerously-skip-permissions
           with role system prompt + task text, inside WORKTREE, in background (&)
       wait for all background jobs
       merge worktrees into main in declaration order using git merge --no-ff:
         on success: delete worktree
         on conflict: abort merge, leave worktree intact,
                      write conflict entry to PROGRESS.md (see format below),
                      continue merging remaining worktrees

     sequential:
       for each agent in declaration order:
         run claude --model <model> --print --dangerously-skip-permissions
           with role system prompt + task text, in main working tree
         wait for completion
         if agent exits with BLOCKED status:
           if main working tree is dirty: git stash (preserves partial work)
           write BLOCKED entry to PROGRESS.md with note "partial changes stashed"
           halt remaining sequential agents for this iteration
           (orchestrator decides next steps on next iteration)

  7. COLLECT RESULTS
     parse each <result> block from agent outputs
     for BLOCKED or NEEDS_CONTEXT: write structured entry to PROGRESS.md (see format above)
     log all non-DONE statuses to stdout

  8. LOOP
     orchestrator sees updated filesystem state on next iteration
```

**Rate limit retry:** Implemented as a `while true` loop inside each iteration slot, not as `for`-loop index decrement (which has no effect on bash `for i in $(seq ...)` loops).

**Agent timeout:** All agents — both parallel and sequential — are subject to `AGENT_TIMEOUT_SECONDS` (default: 1800, i.e. 30 minutes). Configurable via environment variable. The shell wraps each `claude` invocation with `timeout $AGENT_TIMEOUT_SECONDS`.

- **Parallel agent timeout:** Kill the process, leave its worktree intact, write a BLOCKED entry to PROGRESS.md with reason "timeout".
- **Sequential agent timeout:** Kill the process. If the main working tree is dirty (partial uncommitted changes), run `git stash` to preserve the partial work, then write a BLOCKED entry to PROGRESS.md with reason "timeout" and note "partial changes stashed". The orchestrator reads this next iteration and decides whether to unstash and continue or discard.

---

## Parallel Safety

Two rules enforced by the shell:

**1. File overlap → sequential:** If two agents in a `parallel` dispatch declare any file in common (exact string match on relative path), the entire dispatch is downgraded to `sequential`. Overlap is checked only against the `files` attribute (write-intent files), not against read-only shared files omitted from `files`.

**2. Merge conflict → orchestrator decides:** On `git merge --no-ff` failure:

Note: parallel safety enforcement guarantees file-disjoint agents, so a merge conflict at this stage means an indirect dependency was missed — two agents modified different files that have a shared downstream effect (e.g., both modified different parts of a shared import, or both generated code that conflicts at the type level). This is an orchestrator planning error, not a normal operating case.

On conflict:
- Merge is aborted (`git merge --abort`)
- Worktree left intact at `.worktrees/<id>`
- Conflict entry written to `PROGRESS.md`:

```markdown
## Merge conflict — iteration <N>
- **Conflicting worktree:** .worktrees/<id> (role: <role>)
- **Merged successfully before conflict:** <list of prior worktrees already merged>
- **Conflicting files:** <list from git merge output>
- **Likely cause:** indirect dependency not captured in `files` declaration
- **Resolution:** pending orchestrator decision
```

- Remaining non-conflicting worktrees continue to be merged in declaration order
- Orchestrator reads this on the next iteration and decides: resolution agent, task resequencing, or task rewrite

The shell never makes judgment calls about conflicts. That is the orchestrator's responsibility.

---

## Orchestrator System Prompt (`agents/orchestrator/system.md`)

This is the most critical file in the system. The following is the required structure and content.

**Starter template for `agents/orchestrator/system.md`:**

```
You are the orchestrator for a multi-agent ML research project.
You are the research lead. You do not write code directly — you direct specialist agents.

## Your responsibilities
- Understand the current project state deeply before dispatching any work.
- Decompose work into the smallest independently testable units.
- Write task descriptions precise enough that a specialist agent needs no additional context.
- Run the research introspection protocol (via the research agent) after every experiment.
- Own PROGRESS.md — you write it, agents do not.
- Decide how to resolve merge conflicts, BLOCKED agents, and NEEDS_CONTEXT reports.

## Orientation (run at the start of every iteration)
1. Read DESIGN.md — understand goals, module map, and success criteria.
2. Read PROGRESS.md — check for conflicts, blocked agents, and what's next.
3. Run: git log --oneline -10
4. Run: pytest tests/ -q --fast 2>/dev/null || pytest tests/ -q
5. Check for unresolved worktrees: ls .worktrees/ 2>/dev/null

Address any conflicts or blocked agents before dispatching new work.

## Dispatching agents
Output a <dispatch> block. Rules:
- `files` lists only files the agent will WRITE (not read-only files like DESIGN.md).
- `model` is optional — omit to use the default from agents/config.yaml.
- Use mode="parallel" only when agents write to completely different files.
- Task descriptions must include: target files, test command, files NOT to touch,
  relevant context, and commit message format.
- Only list files in `files` that the agent will actually modify.

## After agents finish
Write a PROGRESS.md update summarizing what was done, what passed, what's next.

## Completion
Output <promise>DONE</promise> only when every success criterion in PROMPT.md
is satisfied and PROGRESS.md is fully up to date.
```

Projects should extend this template with project-specific context from `DESIGN.md`.

**Module map requirement:** `DESIGN.md` must include a `## Module dependencies` section listing which modules are independent. The orchestrator uses this to determine parallel safety. Without it, the orchestrator will default to sequential dispatch.

Example format:
```markdown
## Module dependencies

- `src/data_loader.py` — no dependencies on other src modules
- `src/model.py` — no dependencies on other src modules
- `src/trainer.py` — depends on data_loader, model
- `src/evaluate.py` — depends on model
- `src/utils.py` — shared by all modules (treat as non-parallelizable)
```

Modules with no listed dependencies on each other can be dispatched in parallel.

---

## Agent Role System Prompts

Each specialist receives its role system prompt plus the task text written by the orchestrator. Prompts are stored in `agents/<role>/system.md`.

| Role | Default model | Responsibility |
|---|---|---|
| `orchestrator` | sonnet | Research lead, task decomposition, conflict resolution |
| `implementer` | haiku | Write code to pass failing tests |
| `test-quality` | haiku | Improve test harness, add edge cases, improve error messages |
| `performance` | sonnet | Profile, identify bottlenecks, optimize runtime and memory |
| `documentation` | haiku | Keep docstrings and DESIGN.md in sync with actual code |
| `literature` | opus | Review related work, flag relevant papers |
| `research` | opus | Introspection protocol, hypothesis interrogation, paper narrative |

Note: the `documentation` agent syncs docstrings and `DESIGN.md` only. `PROGRESS.md` is written exclusively by the orchestrator.

---

## Config (`agents/config.yaml`)

Default model per role. The `model` attribute in a `<dispatch>` block overrides this for a specific agent invocation.

```yaml
orchestrator: claude-sonnet-4-6
implementer:  claude-haiku-4-5-20251001
test-quality: claude-haiku-4-5-20251001
performance:  claude-sonnet-4-6
documentation: claude-haiku-4-5-20251001
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

# Environment variables:
AGENT_TIMEOUT_SECONDS=1800  # per-agent timeout (default 30 min)
```

Remote monitoring (agents commit and push after each unit):
```bash
git log --oneline -20
git diff HEAD~5
ls .worktrees/          # check for unresolved conflicts
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
| Session continuity | `--continue` across iterations | Orchestrator uses `--continue`; specialists are one-shot |

Both scripts read from `PROMPT.md` and both terminate on `<promise>DONE</promise>`.
