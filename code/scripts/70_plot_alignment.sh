#!/usr/bin/env bash
#
# 70_plot_alignment.sh
#
# Produces the windowed-pi grid figure from stage 5's .calls.txt files:
# one row per curated comparison (config/pi_comparisons.tsv order), one
# column per Muller arm. See code/analysis/plot_alignment_grid.py.
#
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-i COMPARISONS.tsv] [-p PROCESSED_DIR] [-o FIGDIR] [-w WINDOW] [-s STEP] [-y YMAX]

Options:
  -i FILE   Pi-comparison control file (default: config/pi_comparisons.tsv)
  -p DIR    Directory of stage 5's .calls.txt files (default: data/processed)
  -o DIR    Output directory for figures (default: output/figures)
  -w INT    Window size in bp (default: 100000, matching the manuscript)
  -s INT    Step between window starts in bp (default: 10000, matching the manuscript)
  -y FLOAT  Top of the y-axis (default: 0.015)
  -h        Show this help message
EOF
    exit 1
}

COMPARISONS="config/pi_comparisons.tsv"
PROCESSED="data/processed"
FIGDIR="output/figures"
WINDOW=100000
STEP=10000
YMAX=0.015

while getopts "i:p:o:w:s:y:h" opt; do
    case "$opt" in
        i) COMPARISONS=$OPTARG ;;
        p) PROCESSED=$OPTARG ;;
        o) FIGDIR=$OPTARG ;;
        w) WINDOW=$OPTARG ;;
        s) STEP=$OPTARG ;;
        y) YMAX=$OPTARG ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -f "$COMPARISONS" ]] || { echo "Error: pi-comparison list not found: $COMPARISONS" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found on PATH" >&2; exit 1; }

SCRIPT_DIR="$(dirname "$0")"
mkdir -p "$FIGDIR"

python3 "$SCRIPT_DIR/../analysis/plot_alignment_grid.py" \
    --comparisons "$COMPARISONS" --processed "$PROCESSED" \
    --output "$FIGDIR/pi_grid.svg" \
    --window "$WINDOW" --step "$STEP" --ymax "$YMAX"

echo "Done. Figure written to $FIGDIR/pi_grid.svg"
