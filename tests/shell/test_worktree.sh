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
        echo "  PASS: $desc"; ((++PASS))
    else
        echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; ((++FAIL))
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
assert_eq "worktree is git repo" "1" "$([ -e $WT/.git ] && echo 1 || echo 0)"

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
