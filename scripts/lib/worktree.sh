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
