<!-- Ralph Loop Prompt Template -->
<!-- This file is fed to Claude Code on every iteration of the ralph loop. -->
<!-- Customize for your project, then run: ./scripts/ralph-loop.sh -->

# Task

<!-- Describe the task clearly. Be specific about success criteria. -->

Read DESIGN.md for project goals and targets. Read CLAUDE.md for development
rules. Read PROGRESS.md for current status.

Pick up where you left off:
1. Check PROGRESS.md for what's done and what's next.
2. Run `pytest tests/ -q --fast` to see current test status.
3. Work on the next item. Write tests first, then implementation.
4. Commit and push after each meaningful unit of work.
5. Update PROGRESS.md before finishing.

<!-- Define your completion criteria below -->

When ALL of the following are true, output `<promise>DONE</promise>`:
- [ ] <!-- e.g., All tests pass -->
- [ ] <!-- e.g., Accuracy target met -->
- [ ] <!-- e.g., PROGRESS.md is up to date -->

If the task is NOT fully complete, do NOT output the promise. Instead, describe
what remains in PROGRESS.md and continue working.
