#!/bin/bash
# run_parallel.sh — submit two .slurm scripts as a single job, both running
# in parallel on the same node.  SBATCH directives from the first file win
# on conflicts.  The first script runs in the background; the job exits when
# the second script finishes, then kills the first.
#
# Usage: ./run_parallel.sh <primary.slurm> <secondary.slurm> [extra sbatch args...]

set -euo pipefail

usage() {
    cat >&2 <<EOF
Usage: $0 <primary.slurm> <secondary.slurm> [extra sbatch args...]

  Merges SBATCH directives (primary wins on conflicts), then submits a combined
  job that runs both script bodies in parallel on the same node.
  The primary runs in the background; the job ends when the secondary exits.
EOF
    exit 1
}

[[ $# -lt 2 ]] && usage
PRIMARY="$1"
SECONDARY="$2"
shift 2
EXTRA_ARGS=("$@")

[[ ! -f "$PRIMARY" ]]   && { echo "Error: not found: $PRIMARY" >&2; exit 1; }
[[ ! -f "$SECONDARY" ]] && { echo "Error: not found: $SECONDARY" >&2; exit 1; }

# Returns the flag key from an #SBATCH line for conflict detection.
# Handles: --flag=value, --flag value, -f value, -f=value
sbatch_flag_key() {
    local arg
    arg=$(sed 's/^#SBATCH[[:space:]]*//' <<< "$1")
    echo "${arg%%[= ]*}"
}

# Collect #SBATCH lines; primary entries are added first and win on key conflicts.
declare -A seen_flags
sbatch_lines=()

while IFS= read -r line; do
    if [[ "$line" =~ ^#SBATCH[[:space:]] ]]; then
        key=$(sbatch_flag_key "$line")
        if [[ -z "${seen_flags[$key]+x}" ]]; then
            seen_flags["$key"]=1
            sbatch_lines+=("$line")
        fi
    fi
done < "$PRIMARY"

while IFS= read -r line; do
    if [[ "$line" =~ ^#SBATCH[[:space:]] ]]; then
        key=$(sbatch_flag_key "$line")
        if [[ -z "${seen_flags[$key]+x}" ]]; then
            seen_flags["$key"]=1
            sbatch_lines+=("$line")
        fi
    fi
done < "$SECONDARY"

# Strip shebang and #SBATCH lines from a file, leaving the runnable body.
body_of() { grep -v '^#!' "$1" | grep -v '^#SBATCH'; }

TMPSCRIPT=$(mktemp /tmp/combined_slurm_XXXXXX.slurm)
trap 'rm -f "$TMPSCRIPT"' EXIT

{
    echo "#!/bin/bash"
    for line in "${sbatch_lines[@]}"; do echo "$line"; done
    echo ""
    echo "### --- $(basename "$PRIMARY") (background) --- ###"
    echo "("
    body_of "$PRIMARY"
    echo ") &"
    echo "_PRIMARY_PID=\$!"
    echo ""
    echo "### --- $(basename "$SECONDARY") (foreground) --- ###"
    echo "("
    body_of "$SECONDARY"
    echo ")"
    echo ""
    echo "kill \$_PRIMARY_PID 2>/dev/null"
    echo "wait \$_PRIMARY_PID 2>/dev/null || true"
} > "$TMPSCRIPT"

echo "=== Combined script: $TMPSCRIPT ===" >&2
cat "$TMPSCRIPT" >&2
echo "======================================" >&2

sbatch "${EXTRA_ARGS[@]}" "$TMPSCRIPT"
