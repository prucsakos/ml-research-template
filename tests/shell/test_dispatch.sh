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
        echo "  PASS: $desc"; ((++PASS))
    else
        echo "  FAIL: $desc"; echo "    expected: [$expected]"; echo "    actual:   [$actual]"; ((++FAIL))
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
