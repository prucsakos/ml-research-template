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
FORCE_ALL=false
USE_TMUX=false
TMUX_SESSION="orchestrator"
CONFIG_FILE="$PROJECT_DIR/agents/config.yaml"
ORCHESTRATOR_SYSTEM="$PROJECT_DIR/agents/orchestrator/system.md"
PROMPT_FILE="$PROJECT_DIR/PROMPT.md"
AGENT_TIMEOUT_SECONDS="${AGENT_TIMEOUT_SECONDS:-1800}"

# --- Parse args ---
usage() {
    echo "Usage: $0 [-n max_iterations] [-f] [-s] [-t session_name] [-h]"
    echo "  -n  Max iterations (default: $MAX_ITERATIONS)"
    echo "  -f  Force all N iterations (ignore completion promise)"
    echo "  -s  Run inside a new tmux session"
    echo "  -t  tmux session name (default: $TMUX_SESSION)"
    exit 1
}

while getopts "n:fst:h" opt; do
    case $opt in
        n) MAX_ITERATIONS="$OPTARG" ;;
        f) FORCE_ALL=true ;;
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
python3 -c "import yaml" 2>/dev/null || { echo "ERROR: pyyaml is required — pip install pyyaml"; exit 1; }

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
    echo "Force all:   $FORCE_ALL"
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
        if echo "$output" | grep -qiE 'rate.?limit|usage.?limit|hit.?your.?limit|too many requests|overloaded|429|capacity|quota'; then
            echo ""
            echo "=== RATE LIMIT at iteration $iteration — waiting 1 hour ==="
            sleep 3600
            continue  # retry same iteration (while loop, not for loop)
        fi

        # 3. Completion check (skip if -f flag is set)
        if [[ "$FORCE_ALL" == false ]] && echo "$output" | grep -q '<promise>DONE</promise>'; then
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
    FORCE_FLAG=""
    [[ "$FORCE_ALL" == true ]] && FORCE_FLAG="-f"
    tmux new-session -d -s "$TMUX_SESSION" \
        "cd $PROJECT_DIR && bash $0 -n $MAX_ITERATIONS $FORCE_FLAG; exec bash"
    tmux attach -t "$TMUX_SESSION"
else
    run_orchestrator
fi
