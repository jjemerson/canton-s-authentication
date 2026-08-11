#!/usr/bin/env bash
#
# configure.sh
#
# One-time environment bootstrap: creates the validate_cs conda/mamba
# environment from environment.yml if it doesn't already exist. Every
# pipeline script assumes its tools are already on PATH (see
# 00run_pipeline.sh's own environment check) -- this script only
# creates the environment, it doesn't activate it. Activate it yourself
# before running any stage:
#
#   conda activate validate_cs
#
set -euo pipefail

# environment.yml lives at the repo root; this script is two levels
# down, in code/scripts/.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_NAME="validate_cs"
ENV_FILE="$REPO_ROOT/environment.yml"

usage() {
    cat <<EOF
Usage: $(basename "$0") [-F|--force] [-h|--help]

Creates the '$ENV_NAME' conda/mamba environment from environment.yml if
it doesn't already exist. Prefers mamba (faster solve) over conda, if
both are on PATH.

Options:
  -F, --force   Remove and recreate the environment if it already exists.
  -h, --help    Show this help message
EOF
    exit 1
}

FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -F|--force) FORCE=1; shift ;;
        -h|--help)  usage ;;
        *)          echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[[ -f "$ENV_FILE" ]] || { echo "Error: environment.yml not found at $ENV_FILE" >&2; exit 1; }

if command -v mamba >/dev/null 2>&1; then
    CONDA_BIN=mamba
elif command -v conda >/dev/null 2>&1; then
    CONDA_BIN=conda
else
    echo "Error: neither mamba nor conda found on PATH." >&2
    exit 1
fi

ENV_EXISTS=0
if "$CONDA_BIN" env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    ENV_EXISTS=1
fi

if [[ "$ENV_EXISTS" -eq 1 && "$FORCE" -eq 0 ]]; then
    echo "Environment '$ENV_NAME' already exists. Use -F to remove and recreate it."
    echo "Activate it with: conda activate $ENV_NAME"
    exit 0
fi

if [[ "$ENV_EXISTS" -eq 1 && "$FORCE" -eq 1 ]]; then
    echo "==> Removing existing '$ENV_NAME' environment..."
    "$CONDA_BIN" env remove -n "$ENV_NAME" -y
fi

echo "==> Creating '$ENV_NAME' environment from $ENV_FILE (using $CONDA_BIN)..."
# channel_priority=flexible: strict (this system's default) fails to solve
# some bioconda/conda-forge-split packages otherwise -- flexible resolves
# it with no other change. Set via env var, not --channel-priority: mamba
# env create accepts that flag, but plain conda's env create subcommand
# doesn't (rejects it as an unrecognized argument), so the flag form isn't
# portable across the two. The env var is honored by both.
CONDA_CHANNEL_PRIORITY=flexible "$CONDA_BIN" env create -f "$ENV_FILE"

echo
echo "Done. Activate it before running the pipeline:"
echo "  conda activate $ENV_NAME"
