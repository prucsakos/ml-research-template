# Development Rules

This file contains development conventions and rules for autonomous agents.
It is project-agnostic. All project-specific context — goals, hypotheses,
ground truth, targets, architecture — lives in **DESIGN.md**.

## Quick reference

- **Project context**: `DESIGN.md` (read this first — orchestrator manages this file)
- **Results journal**: `RESULTS.md` (findings, introspections, SOTA analysis, novelty)
- **Progress log**: `PROGRESS.md` (lean working memory — max ~200 lines)
- **Experiments**: `experiments/`
- **API tokens**: `.env` (never commit this file)

## Environment and secrets

API tokens are stored in `.env` in the project root. Load them with:

```python
from dotenv import load_dotenv
load_dotenv()
```

Or in shell scripts:

```bash
source .env
```

Document the variables your project uses in `.env.example` (committed, no values).

**Rules:**
- `.env` is in `.gitignore`. Never commit it.
- Never hardcode tokens in source code.
- Scripts that need tokens must load them from `.env` or environment variables.

## Setup

```bash
pip install -r requirements.txt
```

---

## Directory structure

```
project/
├── CLAUDE.md              # Development rules and conventions (this file)
├── DESIGN.md              # Research design, hypotheses, methodology, targets (orchestrator-managed)
├── RESULTS.md             # Research journal: findings, introspections, SOTA, novelty classification
├── PROGRESS.md            # Lean working memory: status, tasks, failed approaches (~200 lines max)
├── README.md              # Public-facing description for publication/sharing
├── LICENSE
├── requirements.txt       # or environment.yml
├── pyproject.toml         # if installable package
├── src/                   # Reusable code (models, data loaders, utils)
│   └── <project_name>/   # Named package for importability
├── experiments/           # One subfolder per experiment, self-contained
│   └── exp_001_baseline/
│       ├── config.yaml    # Full config (reproducible without external state)
│       ├── run.sh         # Exact command to reproduce
│       └── results/       # Outputs, metrics, logs
├── notebooks/             # Exploration, visualization, analysis
├── data/                  # Raw + processed (or symlinks/pointers if large)
├── paper/                 # LaTeX drafts, figures, references.bib
├── scripts/               # Shared CLI scripts (data generation, evaluation)
├── configs/               # Shared/base configs
└── tests/                 # Automated tests
```

---

## Orientation (read this first when starting a session)

When you start a new session, orient yourself:
1. Read `DESIGN.md` to understand the project goals, ground truth, and targets.
2. Read `PROGRESS.md` to see what's done and what's next.
3. Run `pytest tests/ -v --fast 2>&1 | tail -20` to see current test status.
4. Pick the next failing test or unchecked item from PROGRESS.md.
5. When you finish a unit of work, update PROGRESS.md before stopping.
6. When all DESIGN.md success criteria are met, output `<promise>DONE</promise>`.

---

## Principles for autonomous development

### 1. Ground truth and tests are everything

Every research project has some form of ground truth. It is defined in
DESIGN.md and may be an oracle (reference implementation, analytical solution,
benchmark), hypothesis-driven assertions, or sanity checks. Refer to DESIGN.md
for what applies to this project.

The test harness is the most important part of the project. If the tests are
wrong or incomplete, agents will solve the wrong problem.

**Rules:**
- Never merge or commit code that breaks existing passing tests.
- Every new module must have a corresponding test file BEFORE implementation.
  Write the test first (specifying expected behavior), then make it pass.
- When you find a bug, add a test that reproduces it before fixing it.
- Invest heavily in the test harness: generate high-quality reference data,
  write clear verifiers, and watch for failure modes so you can add targeted tests.
- When a discrepancy is found, trace upstream through the pipeline to find the
  first module where things diverge. Fix there; downstream improves automatically.
- When no oracle exists, encode hypotheses as testable assertions. A test
  that checks "model output has property X under condition Y" is more valuable
  than no test at all.

### 2. Concise test output (context window hygiene)

LLMs have finite context windows. Every line of noisy test output displaces
useful information and degrades reasoning quality.

**Rules:**
- Tests print at most 5-10 lines on success, ~20 lines on failure.
- Use `pytest -q` by default. Never dump large arrays/dataframes to stdout.
- Log verbose diagnostics to `test_logs/` files, not stdout.
- Pre-compute aggregate summary statistics. Print them, not raw data.
- When comparing numerical results, print: max error, where it occurs, and
  the overall pass rate. Not the full arrays.
- Error messages should be greppable: put ERROR and the reason on one line
  so `grep ERROR logfile` works.

Good:
```
FAILED test_model.py::test_accuracy - max rel err 3.2% at sample_id=1089
  Expected acc=0.95, got acc=0.92
  (23/25 metrics pass at <1%, 2 at <5%)
```

Bad:
```
FAILED - arrays not equal:
  [0.9521, 0.9518, 0.9499, ...]  (500 more lines)
```

### 3. Fast tests to avoid time blindness

LLMs can't tell time and will happily spend hours running full test suites
instead of making progress.

**Rules:**
- Every test file has a `--fast` mode (via pytest fixture or marker).
- `--fast` runs a deterministic ~10% subsample of the full test data.
- Default development cycle: run `--fast` after every change, full suite
  only before committing.
- Mark slow tests with `@pytest.mark.slow` so they can be skipped during
  rapid iteration with `pytest -m "not slow"`.

```python
@pytest.fixture
def fast_mode(request):
    return request.config.getoption("--fast", default=False)

def test_model_accuracy(fast_mode, test_data):
    samples = test_data
    if fast_mode:
        samples = samples[::10]  # every 10th sample
    ...
```

### 4. Keep PROGRESS.md current (agent orientation)

Each agent session drops into a fresh context with no memory of what happened
before. PROGRESS.md is the shared memory. Without it, agents waste time
re-discovering what's done and what's broken.

**Rules:**
- Update PROGRESS.md after every meaningful unit of work.
- Check off completed items with dates.
- Note what worked, what didn't, what's blocked.
- **Record failed approaches** so they aren't re-attempted. E.g.:
  "Tried using learning rate 1e-3 with Adam -- diverges after epoch 50.
  Switched to 1e-4 with cosine schedule."
- Add new tasks discovered during implementation.
- When stuck, maintain a running doc of attempts in PROGRESS.md.

### 5. Prevent regressions (CI discipline)

Once the codebase grows, new features frequently break existing functionality.

**Rules:**
- Run `pytest tests/ -q --fast` before every commit.
- If anything regresses, fix it before committing. Never "fix it later."
- If a new feature requires changing behavior in an existing test, update the
  test explicitly (don't just delete or skip it).
- Track test pass rates over time in PROGRESS.md.

### 6. Structure work for parallelism

Parallelism is easy when there are many independent failing tests (each agent
picks a different one), but hard when there's one giant failing task (all
agents hit the same bug and overwrite each other).

**Rules:**
- Identify which modules/components are independent and can be worked on
  in parallel. Document these in DESIGN.md.
- For monolithic tasks, break them into sub-tests that can be tackled
  independently.
- **Task claiming:** When working in parallel, note your task in PROGRESS.md
  (e.g., "IN PROGRESS: data loader (@agent-1)"). Check PROGRESS.md before
  starting to avoid duplicate work.

### 7. Small, testable commits

**Rules:**
- Each commit implements one thing (one function, one module, one bugfix).
- Each commit passes all existing tests.
- Each commit includes or updates tests for the new code.
- **Commit and push** after every meaningful unit of work. This creates a
  recoverable history and enables remote monitoring of agent progress.
- Avoid large commits that change multiple modules at once.
- If a refactor touches many files, do it as a separate commit from features.
- Use conventional commit messages: `feat:`, `fix:`, `refactor:`, `test:`,
  `docs:`, `exp:` (for experiment-related changes).
- Commit messages must reference the relevant experiment ID when applicable
  (e.g., `exp: add baseline config for exp_001`).

### 8. Document for the next session, not for users

Each agent starts with zero context. Documentation is not a nicety;
it's a critical coordination mechanism.

**Every module should have a docstring explaining:**
- What it does and why (with references to papers/methods where applicable).
- What it takes as input and produces as output (types, shapes).
- Any non-obvious choices (why this hyperparameter? why this architecture?).
- Known limitations or accuracy issues.

### 9. Specialized agent roles

Beyond "write code" agents, use specialized agents for distinct concerns:

- **Implementer agents**: Write module code to pass tests.
- **Test quality agent**: Reviews and improves the test harness. Adds edge
  cases, improves error messages, catches gaps in coverage.
- **Performance agent**: Profiles the code, identifies bottlenecks, optimizes
  runtime and memory usage.
- **Code quality agent**: Looks for duplicated code, inconsistent patterns,
  missing type hints, unclear variable names. Refactors.
- **Documentation agent**: Keeps PROGRESS.md, RESULTS.md, docstrings, and
  DESIGN.md in sync with actual code.
- **Literature agent**: Actively searches the web (arXiv, Semantic Scholar,
  conference proceedings) for current state-of-the-art methods, benchmarks,
  and evaluation frameworks relevant to the project's goals. Compares SOTA
  approaches against the project's current methodology and flags gaps,
  superior alternatives, or complementary techniques. This is critical to
  avoid reinventing solved problems or pursuing suboptimal solutions.
  Specifically: reviews related work, checks if methods align with SOTA,
  flags relevant new papers, and recommends concrete methodology changes
  when the literature suggests a better path.
- **Research agent**: The scientific lead. Does not write code. Runs the
  introspection protocol after each experiment — questions why results look
  the way they do, hunts for counterexamples, and rules out trivial
  explanations. Synthesizes findings across experiments to connect dots,
  refine hypotheses, and set research direction based on information gain.
  Maintains the paper narrative and acts as a quality gate: no result enters
  the paper until this agent has interrogated it.

---

## Experiment tracking conventions

### Naming

Experiments are numbered sequentially with a short descriptive slug:
- `exp_001_baseline`
- `exp_002_larger_lr`
- `exp_003_dropout_ablation`

### Each experiment folder must contain

1. **`config.yaml`** — Full configuration. Must be self-contained: anyone
   can reproduce the run from this file alone, without external state.
2. **`run.sh`** — Exact command to reproduce, including:
   - Git commit hash of the code used
   - Python environment snapshot (`pip freeze` output or reference to `requirements.txt`)
   - Random seed(s)
   - Any environment variables that affect behavior
3. **`results/`** — Outputs, metrics, logs, saved models/checkpoints.

### Provenance rules

Every result must be traceable back to the exact code and config that produced it.

- Record the git commit hash in `run.sh` and in the results metadata.
- Record the full config (not just deltas from a base config).
- Record the exact run command.
- If data was preprocessed, record the preprocessing script and its git hash.
- Never overwrite results. If you re-run an experiment, create a new experiment
  folder (e.g., `exp_001b_baseline_rerun`).

### Logging

- Log metrics to a structured format (JSON, CSV) inside `results/`.
- Log hyperparameters alongside metrics so they are always co-located.
- Summarize key results in RESULTS.md with a pointer to the experiment folder.
  Add a 1-line summary with metrics to PROGRESS.md.

---

## Paper writing conventions

- Paper source lives in `paper/` with `main.tex` as the entry point.
- Figures are generated from experiment results via scripts in `scripts/`
  and saved to `paper/figures/`. Never manually copy figures.
- Every figure script should be reproducible: reads from `experiments/*/results/`,
  writes to `paper/figures/`.
- Use BibTeX (`references.bib`) for all citations.
- When results change, re-run figure scripts rather than manually updating.
- Track which experiment each figure comes from in a comment at the top of
  the figure script (e.g., `# Source: exp_003_dropout_ablation`).

### Paper results.tex

All experimental results referenced in the paper must be recorded in
`paper/results.tex` (included by `main.tex` via `\input{results}`).
This file is the LaTeX macro layer for traceable numbers.

**Rules:**
- Never hardcode numbers in `main.tex`. Always use commands defined in
  `results.tex` (e.g., `\expOneAccuracy`).
- Each entry must include the git commit hash and reproduction command.
- When results update, update both `results.tex` and `RESULTS.md`.

---

## Coding conventions

- **Python 3.10+** as minimum version.
- **Type hints** on all public functions.
- **snake_case** for everything (functions, variables, files, folders).
- **Docstrings** on all public functions and classes (see principle 8).
- **No mutable global state**. Prefer pure functions where possible.
- **Config over magic numbers**. Hardcoded values belong in config files,
  not scattered through code.
- **Reproducibility by default**. Every script that involves randomness
  must accept a seed parameter and set it explicitly.

---

## Testing and debugging workflow

Each module gets two types of tests:
1. **Correctness tests**: compare outputs against ground truth / expected behavior.
2. **Robustness tests**: edge cases, boundary conditions, varying inputs.

Always write the test first (expected behavior), then make it pass.

### Debugging discrepancies

When results don't match expectations, bisect through the pipeline:
1. Is the data loading correct?
2. Is the preprocessing correct?
3. Are intermediate representations correct?
4. Is the model/algorithm producing expected outputs on known inputs?
5. Is the evaluation metric computed correctly?

Fix the upstream issue; downstream improves automatically.

### Never add fudge factors

If a test fails with unexpected error, there is a real bug — a sign error,
a wrong index, a mismatched dimension, an off-by-one. Find the actual bug.
Do NOT multiply by a correction constant or add offsets to make the test pass.

### Test at many parameter points, not just defaults

A bug that hides at default hyperparameters will surface when parameters change.
Test with varied configurations:
- Different random seeds
- Different dataset sizes / splits
- Perturbed hyperparameters (±20% from default)
- Edge cases specific to your domain

---

## Research introspection

After completing an experiment or answering a research question, do not
move on immediately. Stop and interrogate your own findings.

### When a hypothesis is confirmed or denied

1. **Ask why.** Do not accept a result at face value. Ask: *Why did this
   happen?* Is there a mechanistic explanation, or is the result merely
   correlational? Could there be a confound?
2. **Look for counterexamples.** If H1 is confirmed, find the models or
   conditions where it almost fails. If H2 is denied, find the subset
   where it does hold. Boundary cases are more informative than averages.
3. **Check if the answer is trivial.** Could the result be explained by a
   simpler mechanism? Rule out trivial explanations before claiming a
   non-trivial finding.
4. **Quantify surprise.** How much does this result deviate from the prior
   expectation? A barely-significant confirmation is less interesting than
   a strong rejection. Record the effect size, not just significance.

### When a research question is answered

1. **Challenge the answer.** What would change if the benchmark were
   different? If the evaluation set were larger? If the models were
   evaluated on a different task type?
2. **Identify what you still don't know.** Every answered question reveals
   gaps. What assumption did you rely on that remains untested?
3. **Generate follow-up questions.** After confirming or denying each
   hypothesis, produce 2-3 new questions that are:
   - **Relevant** — they follow directly from the finding.
   - **Interesting** — they challenge or deepen the result.
   - **Important** — answering them would change how the results are interpreted.

### Recording introspection

Document all introspection in **RESULTS.md** under a dedicated section per
experiment or research question:

```markdown
## Introspection: <hypothesis or question>
- **Finding:** Confirmed / Denied / Partially confirmed
- **Novelty:** N0–N5 (see §Novelty classification below)
- **Why this result:** <mechanistic explanation or hypothesis>
- **Counterexamples:** <conditions where it breaks down>
- **Trivial explanation ruled out?** Yes/No — <reasoning>
- **Effect size:** <quantified>
- **Follow-up questions:**
  1. <new question>
  2. <new question>
  3. <new question>
```

Also update DESIGN.md to append newly generated questions under the
`## Emergent research questions` section, and update Status/Resolved
fields on any questions or hypotheses that were addressed.

---

## Progress tracking

The four key documents serve distinct roles:

- **CLAUDE.md** (this file): Stable rules and conventions. Project-agnostic.
- **DESIGN.md**: Project-specific context — research questions, hypotheses,
  ground truth, targets, architecture. The user seeds it; the orchestrator
  manages it going forward (updates Status/Resolved fields, appends emergent
  questions, adds further directions).
- **RESULTS.md**: Research journal — experiment findings, introspections,
  literature alignment, novelty classification. This is where deep analysis
  lives. Updated after each experiment or literature review.
- **PROGRESS.md**: Lean working memory — current status, task lists, failed
  approaches, discovered tasks. **Max ~200 lines.** No introspections, no
  literature analysis, no verbose findings. Updated after every unit of work.
  Points to RESULTS.md for details.

### PROGRESS.md format

```markdown
## Current status
<!-- 5-10 lines: what's working, what's broken, what's next -->

## Completed
- [x] 2026-03-15: exp_001_baseline — baseline reproduces published results
- [x] 2026-03-18: exp_002_larger_lr — learning rate ablation complete

## In progress
- [ ] exp_003_dropout_ablation (@agent-1)

## Failed approaches
- Tried X because Y — didn't work because Z (2026-03-16)

## Discovered tasks
- Need to investigate W
```

**Rules for PROGRESS.md:**
- Keep it under ~200 lines. If it grows beyond that, move content to RESULTS.md.
- No experiment introspections — those go in RESULTS.md.
- No literature analysis — that goes in RESULTS.md.
- Summarize experiment outcomes in 1-3 lines with a pointer: "See RESULTS.md §exp_002".
- Record key metrics inline but not detailed analysis.

### RESULTS.md format

```markdown
## Experiment results

### exp_001_baseline (2026-03-15)
**Summary:** <1-3 sentence summary of findings>
**Novelty:** N2 — Extends (justification)

#### Introspection
<full introspection per CLAUDE.md §Research introspection>

### exp_002_larger_lr (2026-03-18)
...

## Literature alignment
### <Topic area>
**SOTA landscape:** ...
**Assessment:** ...
**Our position:** ...

## Novelty classification summary
| Finding | Category | Justification |
|---------|----------|---------------|
| ... | N0–N5 | ... |
```

### Novelty classification

Every research finding and contribution must be classified on the following
scale. Record the classification in RESULTS.md alongside each finding.

| Code | Label | Meaning |
|------|-------|---------|
| **N0** | Confirmatory | Validates known results in a new setting; no new insight |
| **N1** | Incremental | Small improvement or refinement over known approaches |
| **N2** | Extends | Builds meaningfully on existing work — new axis, domain, or method variant |
| **N3** | Orthogonal | Addresses the same problem from a completely different angle |
| **N4** | Novel | No prior work addresses this; first result of its kind |
| **N5** | Breakthrough | Fundamentally changes understanding or opens a new research direction |

**Rules:**
- Every introspection must include a `**Novelty:** Nx — Label` line.
- The novelty classification summary table in RESULTS.md must stay current.
- Be honest: most findings are N0–N2. N4+ requires strong justification.
  Overclaiming novelty damages credibility.
- The orchestrator and research agent must review novelty classifications
  during introspection — challenge any N3+ rating with "could this be N2?"

### DESIGN.md management

DESIGN.md is the single source of truth for research direction. The user
seeds it with initial goals, questions, and hypotheses. The orchestrator
manages it going forward:

**Status fields on every question and hypothesis:**
```markdown
**Q1 (question name):**
**Status:** OPEN | PARTIAL | ANSWERED
**Resolved:** <one-paragraph answer when resolved, empty when open>

<original question text>
```

- `OPEN` — not yet investigated
- `PARTIAL` — evidence gathered but question not fully resolved
- `ANSWERED` — sufficient evidence to provide a resolution

**Orchestrator responsibilities for DESIGN.md:**
- Update `Status:` and `Resolved:` fields as evidence accumulates.
- Append new emergent questions (EQ*) under `## Emergent research questions`.
- Add `## Further directions` sections when new research threads emerge.
- Never delete or substantially rewrite user-authored sections — only annotate.

### Results reproducibility file

`paper/results.tex` remains the LaTeX macro file for paper numbers (traceable
to git commits). RESULTS.md is the human-readable research journal. Both must
stay in sync — when results update, update both.

---

## Long-running autonomous sessions

For multi-day autonomous work, the orchestrator dispatches specialist agents
in parallel (via git worktrees) or sequentially, looping until all success
criteria in DESIGN.md are met.

### Running

```bash
# Define your goals and success criteria in DESIGN.md, then launch:
./scripts/orchestrator.sh                    # default: 20 iterations
./scripts/orchestrator.sh -n 50             # more iterations
./scripts/orchestrator.sh -s                # inside tmux (for HPC/detached use)
./scripts/orchestrator.sh -s -t my_session  # custom tmux session name

# Tune per-agent timeout (default: 1800s):
AGENT_TIMEOUT_SECONDS=3600 ./scripts/orchestrator.sh
```

Configure models in `agents/config.yaml`. Add project-specific context to
`agents/orchestrator/system.md`. Ensure `DESIGN.md` has a `## Module dependencies`
section so the orchestrator can reason about what is safe to parallelize.

For simpler single-agent work, use the Ralph loop directly:

```bash
./scripts/ralph-loop.sh                    # default: 20 iterations
./scripts/ralph-loop.sh -n 50             # more iterations
./scripts/ralph-loop.sh -s                 # inside tmux (for HPC/detached use)
```

### Completion signal

When all success criteria in DESIGN.md are satisfied and PROGRESS.md is fully
up to date, output `<promise>DONE</promise>`. The loop scripts detect this
signal and stop. Do not output it until the work is truly finished.

### Remote monitoring

Agents commit and push after every unit of work. Monitor progress remotely:
```bash
git log --oneline -20                      # recent commits
git diff HEAD~5                            # last 5 commits of changes
```
