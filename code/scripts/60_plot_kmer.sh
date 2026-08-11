#!/usr/bin/env bash
#
# 60_plot_kmer.sh
#
# Produces the two k-mer/Mash-D figures from stage 4's distances.tsv:
# the swarm plot (categorized by strain relative to the focal assembly)
# and the Neighbor-Joining tree (with same-strain highlight boxes). Both
# are driven entirely by config/genomes.tsv's strain/role columns --
# see code/analysis/plot_kmer_swarm.R and plot_kmer_tree.R for the
# generic, no-hardcoded-names logic.
#
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-d DISTANCES.tsv] [-g GENOMES.tsv] [-o FIGDIR]

Options:
  -d FILE   Pairwise distances TSV, from stage 4 (default: data/processed/distances.tsv)
  -g FILE   Genome-list control file (default: config/genomes.tsv)
  -o DIR    Output directory for figures (default: output/figures)
  -h        Show this help message
EOF
    exit 1
}

DISTANCES="data/processed/distances.tsv"
GENOMES="config/genomes.tsv"
FIGDIR="output/figures"

while getopts "d:g:o:h" opt; do
    case "$opt" in
        d) DISTANCES=$OPTARG ;;
        g) GENOMES=$OPTARG ;;
        o) FIGDIR=$OPTARG ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -f "$DISTANCES" ]] || { echo "Error: distances file not found: $DISTANCES (run 40_mash_distance.sh first)" >&2; exit 1; }
[[ -f "$GENOMES" ]]   || { echo "Error: genome list not found: $GENOMES" >&2; exit 1; }
command -v Rscript >/dev/null 2>&1 || { echo "Error: Rscript not found on PATH" >&2; exit 1; }

SCRIPT_DIR="$(dirname "$0")"
mkdir -p "$FIGDIR"

echo "==> Swarm plot..."
Rscript "$SCRIPT_DIR/../analysis/plot_kmer_swarm.R" \
    -d "$DISTANCES" -g "$GENOMES" -o "$FIGDIR/swarm_plot.svg"

echo "==> NJ tree..."
Rscript "$SCRIPT_DIR/../analysis/plot_kmer_tree.R" \
    -d "$DISTANCES" -g "$GENOMES" -o "$FIGDIR/nj_tree.svg"

echo "Done. Figures written to $FIGDIR/"
