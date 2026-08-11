#!/usr/bin/env bash
#
# 00run_pipeline.sh
#
# Master orchestrator: runs the seven numbered pipeline stages in order,
# using each stage's own defaults. Doesn't maintain any state file of
# its own about what's already run -- each stage script already checks
# for existing output and skips it (or takes -F to force), so this is
# just sequencing plus per-stage/total wall-clock reporting. Re-running
# with -f/-o is always an explicit choice, never a silent auto-resume.
#
set -euo pipefail

# SCRIPT_DIR locates sibling stage scripts (this file lives in
# code/scripts/ alongside them); REPO_ROOT is where CWD needs to be for
# every stage script's own bare-relative paths (config/, data/, output/,
# tmp/) to resolve correctly -- those two are not the same directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

STAGES=(
    10_download_genomes.sh
    20_extract_euchromatin.sh
    30_kmer_count.sh
    40_mash_distance.sh
    50_align_pi.sh
    60_plot_kmer.sh
    70_plot_alignment.sh
)
N_STAGES=${#STAGES[@]}

usage() {
    cat <<EOF
Usage: $(basename "$0") [-f|--from-stage N] [-o|--only-stage N] [-F|--force] [-h|--help]

Runs all seven numbered pipeline stages in order, using each stage's own
default arguments. For custom per-stage arguments (thread counts, control
file overrides, etc.), run that stage script directly instead.

Options:
  -f, --from-stage N   Start from stage N (1-$N_STAGES), skipping earlier stages.
  -o, --only-stage N   Run only stage N (1-$N_STAGES).
  -F, --force          Pass -F (force overwrite) through to stages 1-5.
                        Stages 6-7 (plotting) always overwrite regardless.
  -h, --help           Show this help message

Stages:
$(for i in "${!STAGES[@]}"; do printf '  %d  %s\n' "$((i+1))" "${STAGES[$i]}"; done)
EOF
    exit 1
}

FROM_STAGE=1
ONLY_STAGE=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--from-stage)
            FROM_STAGE="$2"; shift 2 ;;
        -o|--only-stage)
            ONLY_STAGE="$2"; shift 2 ;;
        -F|--force)
            FORCE=1; shift ;;
        -h|--help)
            usage ;;
        *)
            echo "Unknown argument: $1" >&2; usage ;;
    esac
done

for n in "$FROM_STAGE" "$ONLY_STAGE"; do
    if [[ -n "$n" ]] && { ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > N_STAGES )); }; then
        echo "Error: stage number must be between 1 and $N_STAGES, got: $n" >&2
        exit 1
    fi
done

# Fail fast with a clear message rather than several stages deep with a
# confusing "command not found" -- every stage script just assumes its
# tools are already on PATH via normal environment inheritance from
# whatever conda/mamba env is active in the calling shell.
if [[ "${CONDA_DEFAULT_ENV:-}" != "validate_cs" ]]; then
    echo "Error: the 'validate_cs' conda/mamba environment is not active (current: ${CONDA_DEFAULT_ENV:-none})." >&2
    echo "Run ./code/scripts/configure.sh once to create it, then: conda activate validate_cs" >&2
    exit 1
fi

if [[ -n "$ONLY_STAGE" ]]; then
    RUN_FROM=$ONLY_STAGE
    RUN_TO=$ONLY_STAGE
else
    RUN_FROM=$FROM_STAGE
    RUN_TO=$N_STAGES
fi

TOTAL_START=$(date +%s)

for ((n=RUN_FROM; n<=RUN_TO; n++)); do
    stage="${STAGES[$((n-1))]}"
    stage_force=()
    if [[ "$FORCE" -eq 1 && "$n" -le 5 ]]; then
        stage_force=(-F)
    fi
    echo "=================================================================="
    echo "Stage $n/$N_STAGES: $stage"
    echo "=================================================================="
    STAGE_START=$(date +%s)
    "$SCRIPT_DIR/$stage" ${stage_force[@]+"${stage_force[@]}"}
    STAGE_END=$(date +%s)
    printf '\n-> Stage %d (%s) done in %d s\n\n' "$n" "$stage" "$((STAGE_END - STAGE_START))"
done

TOTAL_END=$(date +%s)
printf 'Pipeline complete: stages %d-%d in %d s\n' "$RUN_FROM" "$RUN_TO" "$((TOTAL_END - TOTAL_START))"
