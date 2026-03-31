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
