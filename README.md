<p align="center">
  <h1 align="center">ML Research Template</h1>
  <p align="center">
    A batteries-included project template for long-running ML research with autonomous AI agents.
    <br />
    Based on <a href="https://www.anthropic.com/research/long-running-Claude"><strong>Tips for Long-Running Claude Sessions</strong></a> by Anthropic.
    <br /><br />
    <a href="#getting-started"><strong>Get Started</strong></a>
    &middot;
    <a href="#project-structure"><strong>Structure</strong></a>
    &middot;
    <a href="#autonomous-agents"><strong>Autonomous Agents</strong></a>
    &middot;
    <a href="#experiment-tracking"><strong>Experiments</strong></a>
  </p>
</p>

<br />

## Why this template?

Running ML research with AI coding agents (Claude Code, etc.) over days or weeks
requires discipline that most project templates don't address:

- **Session continuity** &mdash; agents start fresh every time. They need orientation docs, not tribal knowledge.
- **Reproducibility by default** &mdash; every result traces back to a git hash, config, and run command.
- **Test-driven research** &mdash; ground truth isn't optional. Encode hypotheses as tests, not hopes.
- **Anti-drift loops** &mdash; Ralph loop pattern keeps agents on task across dozens of iterations.

This template encodes [lessons from running long-lived Claude agents](https://www.anthropic.com/research/long-running-Claude)
into a reusable project scaffold for ML research.

---

## Getting Started

### Use this template

```bash
# Clone and rename
git clone https://github.com/prucsakos/ml-research-template.git my-research-project
cd my-research-project
rm -rf .git && git init

# Install dependencies
pip install -r requirements.txt  # customize for your project
```

### Customize for your project

1. **`DESIGN.md`** &mdash; Write your research design, goals, success criteria, methodology, and architecture. The orchestrator manages Status/Resolved fields going forward.
2. **`CLAUDE.md`** &mdash; Development conventions for agents. Generally leave as-is.
3. **`RESULTS.md`** &mdash; Research journal. Agents write findings, introspections, and novelty classifications here.
4. **`PROGRESS.md`** &mdash; Lean working memory (~200 lines max). Agents maintain this automatically.
5. **`PROMPT.md`** &mdash; Workflow skeleton for agent loops. No need to edit.

---

## Project Structure

```
project/
├── CLAUDE.md              # Agent instructions and development conventions
├── DESIGN.md              # Research design, hypotheses, methodology (orchestrator-managed)
├── RESULTS.md             # Research journal: findings, introspections, novelty classification
├── PROGRESS.md            # Lean working memory: status, tasks, failed approaches
├── PROMPT.md              # Task definition for autonomous agent loops
├── README.md              # This file
├── requirements.txt       # Python dependencies
│
├── src/                   # Reusable code (models, data loaders, utils)
│   └── <project_name>/   # Named package for importability
├── experiments/           # One subfolder per experiment, self-contained
│   └── exp_001_baseline/
│       ├── config.yaml    # Full config (no external state needed)
│       ├── run.sh         # Exact command to reproduce
│       └── results/       # Outputs, metrics, logs
├── notebooks/             # Exploration, visualization, analysis
├── data/                  # Raw + processed (or symlinks if large)
├── paper/                 # LaTeX source, figures, references.bib
├── scripts/               # CLI scripts (data gen, evaluation, ralph loop)
├── configs/               # Shared / base configs
└── tests/                 # Automated tests
```

### Key documents

| File | Role | Update frequency |
|------|------|-----------------|
| `CLAUDE.md` | Stable rules and conventions | Rarely |
| `DESIGN.md` | Research design and methodology | Orchestrator manages going forward |
| `RESULTS.md` | Research journal, introspections, novelty | After each experiment |
| `PROGRESS.md` | Lean working memory (~200 lines max) | After every unit of work |
| `PROMPT.md` | Workflow skeleton for agent loops | Rarely (if ever) |

---

## Autonomous Agents

This template is designed for AI coding agents that work autonomously over
extended periods. The conventions in `CLAUDE.md` address the core challenges:

### Session orientation

Every new agent session starts by reading `PROGRESS.md` and running the fast
test suite. No context is assumed from previous sessions.

### Ralph loop

For multi-day autonomous work, the [Ralph loop](https://ghuntley.com/ralph/)
feeds the same prompt to the agent repeatedly. Each iteration sees its own
previous work in files and git history.

```bash
# Define your goals in DESIGN.md, then:
./scripts/ralph-loop.sh              # 20 iterations (default)
./scripts/ralph-loop.sh -n 50        # more iterations
./scripts/ralph-loop.sh -s           # inside tmux (HPC / detached)
```

### Remote monitoring

Agents commit and push after every meaningful unit of work:

```bash
git log --oneline -20     # check progress from anywhere
```

---

## Experiment Tracking

Experiments are numbered, self-contained, and reproducible:

```
experiments/
└── exp_001_baseline/
    ├── config.yaml       # Full config (standalone)
    ├── run.sh            # Git hash + seed + exact command
    └── results/          # Metrics, logs, checkpoints
```

### Provenance rules

- Every result links to a git commit hash, full config, and run command.
- Results are never overwritten &mdash; re-runs get new folders.
- Preprocessing scripts and their git hashes are recorded.

---

## Paper Writing

```
paper/
├── main.tex
├── figures/              # Generated from experiment results
└── references.bib
```

Figures are generated by scripts that read from `experiments/*/results/` and
write to `paper/figures/`. Never copy figures manually &mdash; re-run the script.

---

## Development Principles

The full set of rules lives in [`CLAUDE.md`](CLAUDE.md). Highlights:

- **Test-first** &mdash; write the test (expected behavior), then make it pass
- **Fast tests** &mdash; `--fast` mode runs a 10% subsample for rapid iteration
- **Small commits** &mdash; one thing per commit, all tests passing
- **Conventional commits** &mdash; `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `exp:`
- **No fudge factors** &mdash; find the real bug, don't patch the symptom
- **Failed approaches documented** &mdash; so agents don't retry dead ends

---

## Credits

Built on lessons from [Long-running Claude](https://www.anthropic.com/research/long-running-Claude)
and the [Ralph loop](https://ghuntley.com/ralph/) pattern.

---

## License

<!-- Choose your license -->

MIT
