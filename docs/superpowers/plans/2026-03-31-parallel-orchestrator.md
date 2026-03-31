# Parallel Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a parallel multi-agent orchestrator to ml-research-template, enabling an orchestrator LLM to dispatch specialist agents in parallel using git worktrees for isolation.

**Architecture:** A ralph-loop-style shell script (`orchestrator.sh`) runs an orchestrator LLM that reads project state and outputs a `<dispatch>` XML block. Two shell libraries handle worktree lifecycle (`lib/worktree.sh`) and agent dispatch/result parsing (`lib/dispatch.sh`). Agent roles and models are configured in `agents/config.yaml`; each role has a system prompt in `agents/<role>/system.md`.

**Tech Stack:** bash, Python 3 (XML/YAML parsing in dispatch logic), git worktrees, Claude CLI (`claude --print --dangerously-skip-permissions`)

**Spec:** `docs/superpowers/specs/2026-03-31-parallel-orchestrator-design.md`

---

## File Structure

**New files:**
```
agents/
├── config.yaml                    — role → default model mapping
├── orchestrator/system.md         — orchestrator LLM system prompt
├── implementer/system.md
├── test-quality/system.md
├── performance/system.md
├── documentation/system.md
├── literature/system.md
└── research/system.md

scripts/
├── orchestrator.sh                — main entry point (ralph loop + dispatch)
└── lib/
    ├── worktree.sh                — create / merge / cleanup git worktrees
    └── dispatch.sh                — parse <dispatch>, run agents, collect <result>

tests/shell/
├── test_worktree.sh               — tests for worktree.sh functions
└── test_dispatch.sh               — tests for dispatch.sh parsing functions
```

**Unchanged:** `scripts/ralph-loop.sh`

---

## Chunk 1: Agent Configuration and System Prompts

### Task 1: Create agents/config.yaml

**Files:**
- Create: `agents/config.yaml`

- [ ] **Step 1: Create directory and config file**

```bash
mkdir -p agents
```

```yaml
# agents/config.yaml
# Default model per agent role.
# Override per-dispatch via the model="" attribute in <dispatch> XML.
orchestrator: claude-sonnet-4-6
implementer:  claude-haiku-4-5-20251001
test-quality: claude-haiku-4-5-20251001
performance:  claude-sonnet-4-6
documentation: claude-haiku-4-5-20251001
literature:   claude-opus-4-6
research:     claude-opus-4-6
```

- [ ] **Step 2: Verify YAML is valid**

```bash
python3 -c "import yaml; d=yaml.safe_load(open('agents/config.yaml')); print(d)"
```
Expected: dict printed with 7 keys, no errors.

- [ ] **Step 3: Commit**

```bash
git add agents/config.yaml
git commit -m "feat: add agent role/model config"
```

---

### Task 2: Create orchestrator system prompt

**Files:**
- Create: `agents/orchestrator/system.md`

- [ ] **Step 1: Create orchestrator system prompt**

```markdown
<!-- agents/orchestrator/system.md -->
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
3. Run: `git log --oneline -10`
4. Run: `pytest tests/ -q --fast 2>/dev/null || pytest tests/ -q`
5. Check for unresolved worktrees: `ls .worktrees/ 2>/dev/null`

Address any conflicts or blocked agents before dispatching new work.

## Dispatching agents

Output a `<dispatch>` block. Rules:
- `files` lists only files the agent will **write** (not read-only files like DESIGN.md).
- `model` is optional — omit to use the default from agents/config.yaml.
- Use `mode="parallel"` only when agents write to completely different files.
- Task descriptions must include: target files, test command, files NOT to touch,
  relevant context, and commit message format.

Example:
```xml
<dispatch mode="parallel">
  <agent role="implementer"
         model="claude-haiku-4-5-20251001"
         task="Implement src/data_loader.py to pass tests/test_data_loader.py.
               Read DESIGN.md §Architecture first.
               Run: pytest tests/test_data_loader.py -q after each change.
               Commit: feat: implement data_loader
               Do NOT modify any file outside src/data_loader.py and tests/test_data_loader.py."
         files="src/data_loader.py,tests/test_data_loader.py"/>
</dispatch>
```

For sequential work:
```xml
<dispatch mode="sequential">
  <agent role="research"
         task="Run the introspection protocol on exp_001 results in experiments/exp_001_baseline/results/."
         files="PROGRESS.md"/>
</dispatch>
```

## After agents finish
Write a PROGRESS.md update: what was dispatched, what status each returned, what's next.

## Completion
Output `<promise>DONE</promise>` only when every success criterion in PROMPT.md
is satisfied and PROGRESS.md is fully up to date.
```

- [ ] **Step 2: Verify file was created**

```bash
wc -l agents/orchestrator/system.md
```
Expected: 60+ lines, no error.

- [ ] **Step 3: Commit**

```bash
git add agents/orchestrator/system.md
git commit -m "feat: add orchestrator system prompt"
```

---

### Task 3: Create specialist agent system prompts

**Files:**
- Create: `agents/implementer/system.md`
- Create: `agents/test-quality/system.md`
- Create: `agents/performance/system.md`
- Create: `agents/documentation/system.md`
- Create: `agents/literature/system.md`
- Create: `agents/research/system.md`

- [ ] **Step 1: Create implementer prompt**

```markdown
<!-- agents/implementer/system.md -->
You are an implementer agent. You write code to make failing tests pass.

## Rules
- Read the task description fully before writing any code.
- Write tests first if the task asks you to create a new module.
- Run tests after every meaningful change.
- Commit when tests pass. One commit per logical unit.
- Do NOT modify files outside those listed in your task.
- Do NOT write to PROGRESS.md.

## When done, output:
```xml
<result>
  <status>DONE</status>
  <summary>What you implemented and which tests now pass.</summary>
  <files_changed>comma,separated,list</files_changed>
</result>
```

If you cannot complete the task:
```xml
<result>
  <status>BLOCKED</status>
  <summary>What you tried and why you're stuck.</summary>
  <files_changed></files_changed>
</result>
```

If you need more information:
```xml
<result>
  <status>NEEDS_CONTEXT</status>
  <summary>Exactly what information you need and why.</summary>
  <files_changed></files_changed>
</result>
```
```

- [ ] **Step 2: Create test-quality prompt**

```markdown
<!-- agents/test-quality/system.md -->
You are a test quality agent. You improve the test harness.

## Rules
- Add edge cases and boundary condition tests.
- Improve error messages so failures are self-explanatory.
- Never delete existing passing tests.
- Keep test output concise (≤10 lines on success, ≤20 on failure).
- Do NOT modify src/ files.
- Do NOT write to PROGRESS.md.

## Output
```xml
<result>
  <status>DONE</status>
  <summary>What tests you added and what gaps you covered.</summary>
  <files_changed>comma,separated,list</files_changed>
</result>
```
```

- [ ] **Step 3: Create performance prompt**

```markdown
<!-- agents/performance/system.md -->
You are a performance agent. You profile code and optimize runtime and memory.

## Rules
- Measure before optimizing. Record baseline in your result summary.
- Only optimize code covered by tests. Never break a passing test.
- Prefer algorithmic improvements over micro-optimizations.
- Investigate faster inference engines (vLLM, TensorRT-LLM) if applicable —
  record findings in your result summary, not in PROGRESS.md.
- Do NOT write to PROGRESS.md.

## Output
```xml
<result>
  <status>DONE</status>
  <summary>Baseline, optimization applied, and measured improvement.</summary>
  <files_changed>comma,separated,list</files_changed>
</result>
```
```

- [ ] **Step 4: Create documentation prompt**

```markdown
<!-- agents/documentation/system.md -->
You are a documentation agent. You keep docstrings and DESIGN.md in sync with code.

## Rules
- Update docstrings to reflect actual behavior, not intended behavior.
- Update DESIGN.md §Architecture if module structure has changed.
- Do NOT write to PROGRESS.md — that is the orchestrator's responsibility.
- Do NOT change code logic. Documentation only.

## Output
```xml
<result>
  <status>DONE</status>
  <summary>Which docstrings and DESIGN.md sections you updated.</summary>
  <files_changed>comma,separated,list</files_changed>
</result>
```
```

- [ ] **Step 5: Create literature prompt**

```markdown
<!-- agents/literature/system.md -->
You are a literature agent. You review related work and keep the project aligned with state-of-the-art.

## Rules
- Use web search to find recent relevant papers.
- Check if the current methodology aligns with best practices.
- Flag relevant new papers with a one-line summary of why they matter.
- Do NOT write to PROGRESS.md.
- Do NOT modify code.

## Output
```xml
<result>
  <status>DONE</status>
  <summary>Papers reviewed, alignment assessment, and any flags.</summary>
  <files_changed></files_changed>
</result>
```
```

- [ ] **Step 6: Create research prompt**

```markdown
<!-- agents/research/system.md -->
You are the research agent — the scientific lead for introspection.
You do not write code. You interrogate results.

## After every experiment, run this protocol:

1. **Ask why.** Why did this result occur? Mechanistic explanation or confound?
2. **Find counterexamples.** Where does the finding almost break down?
3. **Rule out trivial explanations.** Could model size, data leakage, or
   metric quirks explain it? Eliminate these first.
4. **Quantify surprise.** Effect size, not just significance.
5. **Generate follow-up questions.** 2-3 questions that are relevant,
   interesting, and would change how results are interpreted.

## Rules
- Read experiment results from experiments/*/results/ directly.
- Do NOT write to PROGRESS.md — return your findings in the result block.
- Do NOT modify code.
- Be skeptical. A confirmed hypothesis is not interesting until you've tried to break it.

## Output
```xml
<result>
  <status>DONE</status>
  <summary>
    Finding: [confirmed/denied/partial]
    Why: [mechanistic explanation]
    Counterexamples: [where it breaks]
    Trivial explanation ruled out: [yes/no and reasoning]
    Effect size: [quantified]
    Follow-up questions:
    1. [question]
    2. [question]
    3. [question]
  </summary>
  <files_changed></files_changed>
</result>
```
```

- [ ] **Step 7: Verify all prompt files exist**

```bash
ls agents/implementer/system.md agents/test-quality/system.md agents/performance/system.md \
   agents/documentation/system.md agents/literature/system.md agents/research/system.md
```
Expected: all six paths printed, no errors.

- [ ] **Step 8: Commit all prompts**

```bash
git add agents/
git commit -m "feat: add specialist agent system prompts"
```

---

## Chunk 2: Shell Libraries

### Task 4: Create scripts/lib/worktree.sh

**Files:**
- Create: `scripts/lib/worktree.sh`
- Create: `tests/shell/test_worktree.sh`

- [ ] **Step 1: Create directories**

```bash
mkdir -p scripts/lib tests/shell
```

- [ ] **Step 2: Write failing test**

Create `tests/shell/test_worktree.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/lib/worktree.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_DIR/scripts/lib/worktree.sh"

PASS=0; FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"; ((PASS++))
    else
        echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; ((FAIL++))
    fi
}

# Setup: temp git repo for tests
TMPDIR_TEST=$(mktemp -d)
trap "rm -rf $TMPDIR_TEST" EXIT
cd "$TMPDIR_TEST"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > file.txt
git add . && git commit -q -m "init"

echo "=== test: worktree_path ==="
path=$(worktree_path "implementer" 3 1)
assert_eq "path contains role" "1" "$(echo $path | grep -c 'implementer')"
assert_eq "path contains iter" "1" "$(echo $path | grep -c 'iter3')"

echo "=== test: create_worktree ==="
WT=$(create_worktree "implementer" 1 0)
assert_eq "worktree dir exists" "1" "$([ -d $WT ] && echo 1 || echo 0)"
assert_eq "worktree is git repo" "1" "$([ -d $WT/.git ] && echo 1 || echo 0)"

echo "=== test: merge_worktree success ==="
echo "change" > "$WT/file.txt"
cd "$WT" && git add . && git commit -q -m "change" && cd "$TMPDIR_TEST"
result=$(merge_worktree "$WT" 2>&1); status=$?
assert_eq "merge exits 0" "0" "$status"
assert_eq "merge success output" "1" "$(echo $result | grep -c 'MERGED')"

echo "=== test: cleanup_worktree ==="
cleanup_worktree "$WT"
assert_eq "worktree removed" "0" "$([ -d $WT ] && echo 1 || echo 0)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 3: Run test to verify it fails**

```bash
bash tests/shell/test_worktree.sh 2>&1 | tail -5
```
Expected: error — `worktree_path: command not found` or similar.

- [ ] **Step 4: Implement scripts/lib/worktree.sh**

```bash
#!/usr/bin/env bash
# scripts/lib/worktree.sh
# Git worktree lifecycle functions for the parallel orchestrator.

# worktree_path <role> <iteration> <index>
# Returns the path for a new worktree. Includes timestamp to prevent collisions.
worktree_path() {
    local role="$1" iteration="$2" index="$3"
    local ts; ts=$(date +%s)
    echo ".worktrees/${role}-iter${iteration}-${index}-${ts}"
}

# create_worktree <role> <iteration> <index>
# Creates a new git worktree on a fresh branch. Prints the worktree path.
create_worktree() {
    local role="$1" iteration="$2" index="$3"
    local path; path=$(worktree_path "$role" "$iteration" "$index")
    local branch="agent/${role}-iter${iteration}-${index}-$(date +%s)"
    git worktree add -q "$path" -b "$branch"
    echo "$path"
}

# merge_worktree <path>
# Merges the worktree branch into the current branch using --no-ff.
# Prints MERGED on success, CONFLICT on failure (captures files BEFORE abort).
# Returns 0 on success, 1 on conflict.
merge_worktree() {
    local path="$1"
    local branch; branch=$(git -C "$path" rev-parse --abbrev-ref HEAD)
    if git merge --no-ff --no-edit "$branch" 2>/dev/null; then
        echo "MERGED: $branch"
        return 0
    else
        # Capture conflicting files BEFORE aborting the merge
        local conflicting; conflicting=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        git merge --abort 2>/dev/null || true
        echo "CONFLICT: $branch (worktree: $path) (files: ${conflicting:-unknown})"
        return 1
    fi
}

# cleanup_worktree <path>
# Removes the worktree and deletes its branch.
cleanup_worktree() {
    local path="$1"
    local branch; branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    git worktree remove --force "$path" 2>/dev/null || true
    [[ -n "$branch" ]] && git branch -D "$branch" 2>/dev/null || true
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
bash tests/shell/test_worktree.sh
```
Expected: `Results: 7 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/worktree.sh tests/shell/test_worktree.sh
git commit -m "feat: add worktree shell library with tests"
```

---

### Task 5: Create scripts/lib/dispatch.sh

**Files:**
- Create: `scripts/lib/dispatch.sh`
- Create: `tests/shell/test_dispatch.sh`

- [ ] **Step 1: Write failing test**

Create `tests/shell/test_dispatch.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/lib/dispatch.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_DIR/scripts/lib/dispatch.sh"

PASS=0; FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"; ((PASS++))
    else
        echo "  FAIL: $desc"; echo "    expected: [$expected]"; echo "    actual:   [$actual]"; ((FAIL++))
    fi
}

# --- parse_dispatch_mode ---
echo "=== test: parse_dispatch_mode ==="
INPUT='<dispatch mode="parallel"><agent role="implementer" task="do x" files="a.py"/></dispatch>'
assert_eq "parallel mode" "parallel" "$(parse_dispatch_mode "$INPUT")"

INPUT2='<dispatch mode="sequential"><agent role="research" task="do y" files=""/></dispatch>'
assert_eq "sequential mode" "sequential" "$(parse_dispatch_mode "$INPUT2")"

# --- parse_agents_json ---
echo "=== test: parse_agents_json ==="
INPUT='<dispatch mode="parallel">
  <agent role="implementer" model="claude-haiku-4-5-20251001"
         task="implement foo" files="src/foo.py,tests/test_foo.py"/>
  <agent role="test-quality" task="improve tests" files="tests/test_bar.py"/>
</dispatch>'
JSON=$(parse_agents_json "$INPUT")
assert_eq "agent count" "2" "$(echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))")"
assert_eq "first role" "implementer" "$(echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['role'])")"
assert_eq "first model" "claude-haiku-4-5-20251001" "$(echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['model'])")"
assert_eq "second role" "test-quality" "$(echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[1]['role'])")"

# --- files_overlap ---
echo "=== test: files_overlap ==="
assert_eq "overlap detected"  "1" "$(files_overlap "src/a.py,src/b.py" "src/b.py,src/c.py" && echo 1 || echo 0)"
assert_eq "no overlap"        "0" "$(files_overlap "src/a.py" "src/b.py" && echo 1 || echo 0)"
assert_eq "empty files no overlap" "0" "$(files_overlap "" "src/b.py" && echo 1 || echo 0)"

# --- parse_result_status ---
echo "=== test: parse_result_status ==="
OUT='<result><status>DONE</status><summary>all good</summary><files_changed>a.py</files_changed></result>'
assert_eq "DONE status" "DONE" "$(parse_result_status "$OUT")"

OUT2='<result><status>BLOCKED</status><summary>stuck</summary><files_changed></files_changed></result>'
assert_eq "BLOCKED status" "BLOCKED" "$(parse_result_status "$OUT2")"

OUT3='no result block here'
assert_eq "missing result" "UNKNOWN" "$(parse_result_status "$OUT3")"

# --- load_model_for_role ---
echo "=== test: load_model_for_role ==="
TMPCONFIG=$(mktemp)
cat > "$TMPCONFIG" <<'EOF'
orchestrator: claude-sonnet-4-6
implementer:  claude-haiku-4-5-20251001
EOF
assert_eq "known role" "claude-sonnet-4-6"      "$(load_model_for_role "orchestrator" "$TMPCONFIG")"
assert_eq "implementer"  "claude-haiku-4-5-20251001" "$(load_model_for_role "implementer" "$TMPCONFIG")"
assert_eq "unknown role" "" "$(load_model_for_role "nonexistent" "$TMPCONFIG")"
rm "$TMPCONFIG"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/shell/test_dispatch.sh 2>&1 | tail -5
```
Expected: error — `parse_dispatch_mode: command not found` or similar.

- [ ] **Step 3: Implement scripts/lib/dispatch.sh**

```bash
#!/usr/bin/env bash
# scripts/lib/dispatch.sh
# Agent dispatch functions: parse <dispatch> XML, run agents, collect <result>.

# parse_dispatch_mode <output>
# Extracts mode attribute from <dispatch mode="..."> block.
parse_dispatch_mode() {
    echo "$1" | python3 -c "
import sys, re
content = sys.stdin.read()
m = re.search(r'<dispatch\s+mode=\"(\w+)\"', content)
print(m.group(1) if m else '')
"
}

# parse_agents_json <output>
# Extracts all <agent .../> elements as a JSON array.
# Each element: {role, model, task, files}
# model may be empty string if not specified in the dispatch block.
parse_agents_json() {
    echo "$1" | python3 -c "
import sys, re, json
content = sys.stdin.read()
dispatch = re.search(r'<dispatch[^>]*>(.*?)</dispatch>', content, re.DOTALL)
if not dispatch:
    print('[]'); sys.exit(0)
agents = []
for m in re.finditer(r'<agent\s+(.*?)/>', dispatch.group(1), re.DOTALL):
    attrs = {}
    for a in re.finditer(r'(\w[\w-]*)\s*=\s*\"((?:[^\"])*?)\"', m.group(1), re.DOTALL):
        attrs[a.group(1)] = a.group(2).strip()
    agents.append({
        'role':  attrs.get('role', ''),
        'model': attrs.get('model', ''),
        'task':  attrs.get('task', ''),
        'files': attrs.get('files', ''),
    })
print(json.dumps(agents))
"
}

# files_overlap <files_a> <files_b>
# Returns 0 (true) if the two comma-separated file lists share any file, 1 otherwise.
# Uses sys.argv to avoid shell variable interpolation into Python string literals.
files_overlap() {
    local files_a="$1" files_b="$2"
    [[ -z "$files_a" || -z "$files_b" ]] && return 1
    python3 - "$files_a" "$files_b" <<'PYEOF'
import sys
a = set(f.strip() for f in sys.argv[1].split(',') if f.strip())
b = set(f.strip() for f in sys.argv[2].split(',') if f.strip())
sys.exit(0 if a & b else 1)
PYEOF
}

# parse_result_status <output>
# Extracts status from <result><status>...</status></result> block.
# Prints UNKNOWN if no result block found.
parse_result_status() {
    echo "$1" | python3 -c "
import sys, re
content = sys.stdin.read()
m = re.search(r'<status>(.*?)</status>', content, re.DOTALL)
print(m.group(1).strip() if m else 'UNKNOWN')
"
}

# parse_result_summary <output>
parse_result_summary() {
    echo "$1" | python3 -c "
import sys, re
content = sys.stdin.read()
m = re.search(r'<summary>(.*?)</summary>', content, re.DOTALL)
print(m.group(1).strip() if m else '')
"
}

# load_model_for_role <role> <config_path>
# Reads the default model for a role from agents/config.yaml.
# Prints empty string if role not found.
# Uses sys.argv to avoid shell variable interpolation into Python string literals.
load_model_for_role() {
    local role="$1" config="$2"
    python3 - "$role" "$config" <<'PYEOF'
import yaml, sys
try:
    d = yaml.safe_load(open(sys.argv[2]))
    print(d.get(sys.argv[1], '') or '')
except Exception:
    print('')
PYEOF
}

# write_progress_issue <type> <iteration> <role> <task_excerpt> <summary> [worktree]
# Appends a structured issue entry to PROGRESS.md.
write_progress_issue() {
    local type="$1" iteration="$2" role="$3" task_excerpt="$4" summary="$5" worktree="${6:-main}"
    cat >> PROGRESS.md <<EOF

## Agent issue — iteration ${iteration}
- **Status:** ${type}
- **Role:** ${role}
- **Task:** ${task_excerpt}
- **Summary:** ${summary}
- **Worktree:** ${worktree}
EOF
}

# write_progress_conflict <iteration> <role> <worktree> <merged_so_far> <conflicting_files>
# Appends a structured merge conflict entry to PROGRESS.md.
write_progress_conflict() {
    local iteration="$1" role="$2" worktree="$3" merged_so_far="$4" conflicting_files="$5"
    cat >> PROGRESS.md <<EOF

## Merge conflict — iteration ${iteration}
- **Conflicting worktree:** ${worktree} (role: ${role})
- **Merged successfully before conflict:** ${merged_so_far:-none}
- **Conflicting files:** ${conflicting_files}
- **Likely cause:** indirect dependency not captured in \`files\` declaration
- **Resolution:** pending orchestrator decision
EOF
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash tests/shell/test_dispatch.sh
```
Expected: `Results: 15 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/dispatch.sh tests/shell/test_dispatch.sh
git commit -m "feat: add dispatch shell library with tests"
```

---

## Chunk 3: Main Orchestrator Script

### Task 6: Create scripts/orchestrator.sh

**Files:**
- Create: `scripts/orchestrator.sh`

- [ ] **Step 1: Implement scripts/orchestrator.sh**

```bash
#!/usr/bin/env bash
# scripts/orchestrator.sh
# Parallel orchestrator: ralph loop for an orchestrator LLM that dispatches
# specialist agents in parallel (via git worktrees) or sequentially.
#
# Usage:
#   ./scripts/orchestrator.sh                      # default: 20 iterations
#   ./scripts/orchestrator.sh -n 50               # more iterations
#   ./scripts/orchestrator.sh -s                   # inside tmux
#   ./scripts/orchestrator.sh -s -t my_session     # custom tmux session
#
# Environment variables:
#   AGENT_TIMEOUT_SECONDS   per-agent timeout in seconds (default: 1800)
#
# See: docs/superpowers/specs/2026-03-31-parallel-orchestrator-design.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/worktree.sh"
source "$SCRIPT_DIR/lib/dispatch.sh"

# --- Defaults ---
MAX_ITERATIONS=20
USE_TMUX=false
TMUX_SESSION="orchestrator"
CONFIG_FILE="$PROJECT_DIR/agents/config.yaml"
ORCHESTRATOR_SYSTEM="$PROJECT_DIR/agents/orchestrator/system.md"
PROMPT_FILE="$PROJECT_DIR/PROMPT.md"
AGENT_TIMEOUT_SECONDS="${AGENT_TIMEOUT_SECONDS:-1800}"

# --- Parse args ---
usage() {
    echo "Usage: $0 [-n max_iterations] [-s] [-t session_name] [-h]"
    echo "  -n  Max iterations (default: $MAX_ITERATIONS)"
    echo "  -s  Run inside a new tmux session"
    echo "  -t  tmux session name (default: $TMUX_SESSION)"
    exit 1
}

while getopts "n:st:h" opt; do
    case $opt in
        n) MAX_ITERATIONS="$OPTARG" ;;
        s) USE_TMUX=true ;;
        t) TMUX_SESSION="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# --- Validate ---
[[ ! -f "$PROMPT_FILE" ]]           && echo "ERROR: PROMPT.md not found: $PROMPT_FILE" && exit 1
[[ ! -f "$CONFIG_FILE" ]]           && echo "ERROR: agents/config.yaml not found: $CONFIG_FILE" && exit 1
[[ ! -f "$ORCHESTRATOR_SYSTEM" ]]   && echo "ERROR: agents/orchestrator/system.md not found" && exit 1

ORCHESTRATOR_MODEL=$(load_model_for_role "orchestrator" "$CONFIG_FILE")
[[ -z "$ORCHESTRATOR_MODEL" ]] && echo "ERROR: 'orchestrator' role not found in agents/config.yaml" && exit 1

mkdir -p "$PROJECT_DIR/.worktrees"

# --- Run a single agent (parallel or sequential) ---
# run_agent <role> <model> <task> <workdir>
# Runs claude in a subshell so cd side-effects don't leak to caller.
# Prints the full claude output.
run_agent() {
    local role="$1" model="$2" task="$3" workdir="${4:-$PROJECT_DIR}"
    local system_prompt="$PROJECT_DIR/agents/${role}/system.md"

    if [[ ! -f "$system_prompt" ]]; then
        echo "<result><status>BLOCKED</status><summary>System prompt not found: $system_prompt</summary><files_changed></files_changed></result>"
        return
    fi

    local prompt_text
    prompt_text=$(printf '%s\n\n---\n\n%s' "$(cat "$system_prompt")" "$task")

    # Run entirely in a subshell — cd never affects the parent process
    local exit_code=0
    (
        cd "$workdir"
        printf '%s' "$prompt_text" | timeout "$AGENT_TIMEOUT_SECONDS" \
            claude --model "$model" --print --dangerously-skip-permissions 2>&1
    ) || exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        echo "<result><status>BLOCKED</status><summary>Agent timed out after ${AGENT_TIMEOUT_SECONDS}s</summary><files_changed></files_changed></result>"
    fi
}

# --- Dispatch parallel agents ---
dispatch_parallel() {
    local agents_json="$1" iteration="$2"
    local count; count=$(echo "$agents_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
    local pids=() worktrees=() roles=() outputs=()

    for idx in $(seq 0 $((count - 1))); do
        local role model task files
        role=$(echo  "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['role'])")
        task=$(echo  "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['task'])")
        files=$(echo "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['files'])")
        model=$(echo "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['model'])")
        [[ -z "$model" ]] && model=$(load_model_for_role "$role" "$CONFIG_FILE")

        local wt; wt=$(create_worktree "$role" "$iteration" "$idx")
        worktrees+=("$wt")
        roles+=("$role")

        local outfile; outfile=$(mktemp)
        outputs+=("$outfile")

        echo "  → Dispatching $role (parallel, worktree: $wt)"
        run_agent "$role" "$model" "$task" "$wt" > "$outfile" &
        pids+=($!)
    done

    # Wait for all agents
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    # Process results and merge worktrees
    local merged_so_far=""
    for idx in $(seq 0 $((count - 1))); do
        local output; output=$(cat "${outputs[$idx]}")
        local status; status=$(parse_result_status "$output")
        local summary; summary=$(parse_result_summary "$output")
        local role="${roles[$idx]}"
        local wt="${worktrees[$idx]}"

        echo "  ← $role returned: $status"

        # Handle stash for timed-out parallel agents (partial work in worktree)
        if [[ "$status" == "BLOCKED" ]]; then
            local task_excerpt; task_excerpt=$(echo "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['task'][:100])")
            write_progress_issue "BLOCKED" "$iteration" "$role" "$task_excerpt" "$summary" "$wt"
            cleanup_worktree "$wt"
            continue
        fi

        if [[ "$status" == "NEEDS_CONTEXT" ]]; then
            local task_excerpt; task_excerpt=$(echo "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['task'][:100])")
            write_progress_issue "NEEDS_CONTEXT" "$iteration" "$role" "$task_excerpt" "$summary" "$wt"
            cleanup_worktree "$wt"
            continue
        fi

        # Merge worktree
        cd "$PROJECT_DIR"
        local merge_output; merge_output=$(merge_worktree "$wt" 2>&1)
        if echo "$merge_output" | grep -q "^MERGED"; then
            cleanup_worktree "$wt"
            merged_so_far="${merged_so_far:+$merged_so_far, }$wt"
        else
            # Conflicting files are embedded in merge_output by merge_worktree
            # (captured before git merge --abort, so they are not lost)
            local conflicting_files; conflicting_files=$(echo "$merge_output" | grep -oP '(?<=\(files: )[^)]+' || echo "unknown")
            write_progress_conflict "$iteration" "$role" "$wt" "$merged_so_far" "$conflicting_files"
            echo "  ! Merge conflict for $role — worktree left at $wt"
        fi
    done

    # Cleanup temp output files
    for f in "${outputs[@]}"; do rm -f "$f"; done
}

# --- Dispatch sequential agents ---
dispatch_sequential() {
    local agents_json="$1" iteration="$2"
    local count; count=$(echo "$agents_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

    for idx in $(seq 0 $((count - 1))); do
        local role model task
        role=$(echo  "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['role'])")
        task=$(echo  "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['task'])")
        model=$(echo "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['model'])")
        [[ -z "$model" ]] && model=$(load_model_for_role "$role" "$CONFIG_FILE")

        echo "  → Dispatching $role (sequential)"
        local output; output=$(run_agent "$role" "$model" "$task" "")
        local status; status=$(parse_result_status "$output")
        local summary; summary=$(parse_result_summary "$output")

        echo "  ← $role returned: $status"

        if [[ "$status" == "BLOCKED" ]]; then
            # Stash partial changes if tree is dirty
            if ! git -C "$PROJECT_DIR" diff --quiet 2>/dev/null; then
                git -C "$PROJECT_DIR" stash push -m "partial: $role iter$iteration" 2>/dev/null || true
                summary="$summary (partial changes stashed)"
            fi
            local task_excerpt; task_excerpt=$(echo "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['task'][:100])")
            write_progress_issue "BLOCKED" "$iteration" "$role" "$task_excerpt" "$summary" "main"
            echo "  ! $role BLOCKED — halting sequential dispatch for this iteration"
            return
        fi

        if [[ "$status" == "NEEDS_CONTEXT" ]]; then
            local task_excerpt; task_excerpt=$(echo "$agents_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$idx]['task'][:100])")
            write_progress_issue "NEEDS_CONTEXT" "$iteration" "$role" "$task_excerpt" "$summary" "main"
            echo "  ! $role NEEDS_CONTEXT — halting sequential dispatch for this iteration"
            return
        fi
    done
}

# --- Main orchestrator loop ---
run_orchestrator() {
    cd "$PROJECT_DIR"
    echo "=== Parallel Orchestrator ==="
    echo "Project:     $PROJECT_DIR"
    echo "Prompt:      $PROMPT_FILE"
    echo "Max iter:    $MAX_ITERATIONS"
    echo "Orch model:  $ORCHESTRATOR_MODEL"
    echo "Agent timeout: ${AGENT_TIMEOUT_SECONDS}s"
    echo "Started:     $(date -Iseconds)"
    echo "============================="

    local iteration=1
    while [[ $iteration -le $MAX_ITERATIONS ]]; do
        echo ""
        echo "--- Iteration $iteration/$MAX_ITERATIONS [$(date -Iseconds)] ---"

        # 1. Call orchestrator
        local output
        output=$(
            (cat "$ORCHESTRATOR_SYSTEM"; echo; cat "$PROMPT_FILE") \
            | claude --model "$ORCHESTRATOR_MODEL" --continue --print \
                     --dangerously-skip-permissions 2>&1
        ) || true

        echo "$output"

        # 2. Rate limit check
        if echo "$output" | grep -qiE 'rate.?limit|usage.?limit|too many requests|overloaded|429|capacity|quota'; then
            echo ""
            echo "=== RATE LIMIT at iteration $iteration — waiting 1 hour ==="
            sleep 3600
            continue  # retry same iteration (while loop, not for loop)
        fi

        # 3. Completion check
        if echo "$output" | grep -q '<promise>DONE</promise>'; then
            echo ""
            echo "=== DONE at iteration $iteration [$(date -Iseconds)] ==="
            exit 0
        fi

        # 4. Parse dispatch block
        local mode; mode=$(parse_dispatch_mode "$output")
        if [[ -z "$mode" ]]; then
            echo "  ! No <dispatch> block found in orchestrator output. Continuing..."
            ((iteration++))
            continue
        fi

        local agents_json; agents_json=$(parse_agents_json "$output")
        local agent_count; agent_count=$(echo "$agents_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
        echo "  Dispatch: mode=$mode, agents=$agent_count"

        # 5. Parallel safety check
        if [[ "$mode" == "parallel" ]]; then
            local overlap_check; overlap_check=$(
                echo "$agents_json" | python3 -c "
import sys, json
agents = json.load(sys.stdin)
for i in range(len(agents)):
    for j in range(i+1, len(agents)):
        a = set(f.strip() for f in agents[i]['files'].split(',') if f.strip())
        b = set(f.strip() for f in agents[j]['files'].split(',') if f.strip())
        if a & b:
            print(f\"OVERLAP: {agents[i]['role']} and {agents[j]['role']} share: {','.join(a&b)}\")
            exit(0)
" 2>/dev/null || true
            )
            if [[ -n "$overlap_check" ]]; then
                echo "  ! File overlap detected — downgrading to sequential: $overlap_check"
                mode="sequential"
            fi
        fi

        # 6. Dispatch
        if [[ "$mode" == "parallel" ]]; then
            dispatch_parallel "$agents_json" "$iteration"
        else
            dispatch_sequential "$agents_json" "$iteration"
        fi

        ((iteration++))
    done

    echo ""
    echo "=== MAX ITERATIONS ($MAX_ITERATIONS) REACHED WITHOUT COMPLETION ==="
    echo "Review PROGRESS.md and git log for current state."
    exit 1
}

# --- Launch ---
if [[ "$USE_TMUX" == true ]]; then
    echo "Launching orchestrator in tmux session: $TMUX_SESSION"
    echo "Detach: Ctrl-b d  |  Reattach: tmux attach -t $TMUX_SESSION"
    tmux new-session -d -s "$TMUX_SESSION" \
        "cd $PROJECT_DIR && bash $0 -n $MAX_ITERATIONS; exec bash"
    tmux attach -t "$TMUX_SESSION"
else
    run_orchestrator
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/orchestrator.sh
```

- [ ] **Step 3: Smoke test — validate without running a full loop**

```bash
cd "A:/dev/_WorkSpace/research/ml-research-template"
bash -n scripts/orchestrator.sh && echo "Syntax OK"
```
Expected: `Syntax OK`

```bash
bash scripts/orchestrator.sh -h 2>&1 | head -5
```
Expected: usage text printed, exits 1.

```bash
# Missing PROMPT.md should error gracefully
bash scripts/orchestrator.sh 2>&1 | head -3
```
Expected: `ERROR: PROMPT.md not found:...`

- [ ] **Step 4: Commit**

```bash
git add scripts/orchestrator.sh
git commit -m "feat: add parallel orchestrator main script"
```

---

### Task 7: Update CLAUDE.md — document the orchestrator

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add orchestrator usage to the "Long-running autonomous sessions" section**

In `CLAUDE.md`, find the line that reads exactly:
```
See the template `PROMPT.md` in the project root.
```
Insert the following block immediately after that line:

```markdown
### Parallel orchestrator

For multi-agent work where tasks can be parallelized:

```bash
# Edit PROMPT.md with your task and completion criteria
# Then launch:
./scripts/orchestrator.sh                    # default: 20 iterations
./scripts/orchestrator.sh -n 50             # more iterations
./scripts/orchestrator.sh -s                # inside tmux (for HPC/detached use)
./scripts/orchestrator.sh -s -t my_session  # custom tmux session name

# Tune per-agent timeout (default: 1800s):
AGENT_TIMEOUT_SECONDS=3600 ./scripts/orchestrator.sh
```

The orchestrator runs on sonnet. Specialist agents (implementer, test-quality,
performance, documentation, literature, research) are dispatched in parallel
when tasks are file-disjoint, or sequentially otherwise.

Configure models in `agents/config.yaml`. Add project-specific context to
`agents/orchestrator/system.md`. Ensure `DESIGN.md` has a `## Module dependencies`
section so the orchestrator can reason about what is safe to parallelize.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document parallel orchestrator in CLAUDE.md"
```

---

## Final Verification

- [ ] **Run all shell tests**

```bash
bash tests/shell/test_worktree.sh && bash tests/shell/test_dispatch.sh
```
Expected: both print `Results: N passed, 0 failed`

- [ ] **Confirm file structure**

```bash
find agents/ scripts/lib/ tests/shell/ -type f | sort
```
Expected:
```
agents/config.yaml
agents/documentation/system.md
agents/implementer/system.md
agents/literature/system.md
agents/orchestrator/system.md
agents/performance/system.md
agents/research/system.md
agents/test-quality/system.md
scripts/lib/dispatch.sh
scripts/lib/worktree.sh
tests/shell/test_dispatch.sh
tests/shell/test_worktree.sh
```

- [ ] **Final commit**

```bash
git add -A
git status  # verify nothing unexpected
git commit -m "feat: complete parallel orchestrator implementation" --allow-empty-message || true
```
