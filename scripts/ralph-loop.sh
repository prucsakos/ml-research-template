#!/usr/bin/env bash
# Ralph Loop Runner
# Runs Claude Code in a self-referential loop for long-running autonomous work.
# Based on: https://ghuntley.com/ralph/
# See also: https://www.anthropic.com/research/long-running-Claude
#
# Usage:
#   ./scripts/ralph-loop.sh                          # defaults: 20 iterations, PROMPT.md
#   ./scripts/ralph-loop.sh -n 50                    # custom max iterations
#   ./scripts/ralph-loop.sh -p my_prompt.md           # custom prompt file
#   ./scripts/ralph-loop.sh -n 30 -p PROMPT.md -s     # run inside a new tmux session
#
# The loop feeds the same prompt to Claude each iteration. Claude sees its own
# previous work in files and git history, building incrementally toward the goal.
#
# To signal completion, the prompt should instruct Claude to output:
#   <promise>DONE</promise>
# when the task is truly finished to specification.

set -euo pipefail

# --- Defaults ---
MAX_ITERATIONS=20
PROMPT_FILE="PROMPT.md"
USE_TMUX=false
TMUX_SESSION="ralph"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- Parse args ---
usage() {
    echo "Usage: $0 [-n max_iterations] [-p prompt_file] [-s] [-t session_name]"
    echo ""
    echo "Options:"
    echo "  -n  Max iterations (default: $MAX_ITERATIONS)"
    echo "  -p  Prompt file (default: $PROMPT_FILE)"
    echo "  -s  Run inside a new tmux session (for HPC/detached use)"
    echo "  -t  tmux session name (default: $TMUX_SESSION)"
    echo "  -h  Show this help"
    exit 1
}

while getopts "n:p:st:h" opt; do
    case $opt in
        n) MAX_ITERATIONS="$OPTARG" ;;
        p) PROMPT_FILE="$OPTARG" ;;
        s) USE_TMUX=true ;;
        t) TMUX_SESSION="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# --- Validate ---
PROMPT_PATH="$PROJECT_DIR/$PROMPT_FILE"
if [[ ! -f "$PROMPT_PATH" ]]; then
    echo "ERROR: Prompt file not found: $PROMPT_PATH"
    echo ""
    echo "Create a PROMPT.md in the project root with your task description."
    echo "Include the line: 'When finished, output <promise>DONE</promise>'"
    exit 1
fi

# --- Ralph loop function ---
run_ralph() {
    cd "$PROJECT_DIR"
    echo "=== Ralph Loop ==="
    echo "Project:    $PROJECT_DIR"
    echo "Prompt:     $PROMPT_FILE"
    echo "Max iter:   $MAX_ITERATIONS"
    echo "Started:    $(date -Iseconds)"
    echo "==================="
    echo ""

    for i in $(seq 1 "$MAX_ITERATIONS"); do
        echo ""
        echo "--- Iteration $i/$MAX_ITERATIONS [$(date -Iseconds)] ---"
        echo ""

        # Feed the prompt to Claude Code with --continue to preserve session
        OUTPUT=$(cat "$PROMPT_PATH" | claude --continue --print 2>&1) || true

        echo "$OUTPUT"

        # Check for completion promise
        if echo "$OUTPUT" | grep -q '<promise>DONE</promise>'; then
            echo ""
            echo "=== COMPLETION DETECTED at iteration $i ==="
            echo "Finished: $(date -Iseconds)"
            exit 0
        fi

        echo ""
        echo "--- Iteration $i complete, no completion promise found. Continuing... ---"
    done

    echo ""
    echo "=== MAX ITERATIONS ($MAX_ITERATIONS) REACHED WITHOUT COMPLETION ==="
    echo "Review PROGRESS.md and git log for current state."
    exit 1
}

# --- Launch ---
if [[ "$USE_TMUX" == true ]]; then
    echo "Launching Ralph loop in tmux session: $TMUX_SESSION"
    echo "Detach with: Ctrl-b d"
    echo "Reattach with: tmux attach -t $TMUX_SESSION"
    tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && bash $0 -n $MAX_ITERATIONS -p $PROMPT_FILE; exec bash"
    tmux attach -t "$TMUX_SESSION"
else
    run_ralph
fi
