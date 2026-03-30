# [Project Name] Development Guide

## What is this?

<!-- Fill in: 1-2 sentence description of the research project -->

Full architecture and research design details are in **DESIGN.md**. This file covers
development instructions and conventions.

## Research scope

<!-- Fill in for each project -->

- **Research question(s):**
- **Hypotheses:**
- **Oracle / ground truth:** <!-- e.g., known-good reference implementation, established benchmark, analytical solution -->
- **Success criteria / accuracy targets:**

| Target | Metric | Threshold |
|--------|--------|-----------|
| <!-- e.g., Baseline reproduction --> | <!-- e.g., F1 score --> | <!-- e.g., within 1% of reference --> |

## Quick reference

- **Design document**: `DESIGN.md` (read this first)
- **Progress log**: `PROGRESS.md`
- **Experiments**: `experiments/`

## Directory structure

```
project/
├── CLAUDE.md              # Development guide and conventions (this file)
├── DESIGN.md              # Research design, hypotheses, methodology
├── PROGRESS.md            # Running log of findings, decisions, failed approaches
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
1. Read `PROGRESS.md` to see what's done and what's next.
2. Run `pytest tests/ -v --fast 2>&1 | tail -20` to see current test status.
3. Pick the next failing test or unchecked item from PROGRESS.md.
4. When you finish a unit of work, update PROGRESS.md before stopping.

---

## Principles for autonomous development

### 1. Define your ground truth — tests are everything

Every research project has some form of ground truth, even if imperfect:
- **Oracle**: A known-good reference implementation, analytical solution, or
  established benchmark to match against.
- **Hypothesis-driven**: Expected behaviors, statistical properties, or
  invariants derived from your research hypotheses.
- **Sanity checks**: Boundary conditions, conservation laws, known edge cases,
  or reproducing published results.

<!-- Fill in: what serves as ground truth for this project? -->

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
- When no oracle exists, encode your hypotheses as testable assertions. A test
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

<!-- Adjust to your project's needs. Common roles: -->

- **Implementer agents**: Write module code to pass tests.
- **Test quality agent**: Reviews and improves the test harness. Adds edge
  cases, improves error messages, catches gaps in coverage.
- **Performance agent**: Profiles the code, identifies bottlenecks, optimizes
  runtime and memory usage.
- **Code quality agent**: Looks for duplicated code, inconsistent patterns,
  missing type hints, unclear variable names. Refactors.
- **Documentation agent**: Keeps PROGRESS.md, docstrings, and DESIGN.md
  in sync with actual code.
- **Literature agent**: Reviews related work, checks if methods align with
  state-of-the-art, flags relevant new papers.

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
- Summarize key results in PROGRESS.md with a pointer to the experiment folder.

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

<!-- Add project-specific conventions below -->

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

<!-- Add project-specific testing notes below -->

---

## Progress tracking

The three key documents serve distinct roles:

- **CLAUDE.md** (this file): Stable rules and conventions. Rarely changes.
- **DESIGN.md**: Research design, hypotheses, methodology, architecture.
  Updated when the research direction evolves.
- **PROGRESS.md**: Living log of what's done, what's next, what failed.
  Updated after every unit of work.

### PROGRESS.md format

```markdown
## Current status
<!-- What's working, what's broken, what's next -->

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

---

## Long-running autonomous sessions

For multi-day autonomous work, use the Ralph loop pattern. The same prompt is
fed to Claude repeatedly; each iteration sees its own previous work in files
and git history, building incrementally toward the goal.

### Running

```bash
# Edit PROMPT.md with your task and completion criteria
# Then launch:
./scripts/ralph-loop.sh                    # default: 20 iterations
./scripts/ralph-loop.sh -n 50             # more iterations
./scripts/ralph-loop.sh -s                 # inside tmux (for HPC/detached use)
./scripts/ralph-loop.sh -s -t my_session   # custom tmux session name
```

### Remote monitoring

Because agents commit and push after every unit of work, you can monitor
progress remotely via git history:
```bash
git log --oneline -20                      # recent commits
git diff HEAD~5                            # last 5 commits of changes
```

### PROMPT.md

The prompt file (`PROMPT.md`) is the task definition fed each iteration.
It must include:
- Clear task description with success criteria.
- Instruction to read CLAUDE.md and PROGRESS.md.
- A completion promise: `<promise>DONE</promise>` that the agent outputs
  only when the task is truly finished to specification.

See the template `PROMPT.md` in the project root.
