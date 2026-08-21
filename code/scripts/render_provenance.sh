#!/usr/bin/env bash
#
# render_provenance.sh
#
# Regenerates figures/canton_s_provenance.svg from
# code/analysis/canton_s_provenance.py and rasterizes it to PNG. This
# figure has no input data file (it's a hand-curated illustration, not
# a pipeline output), so it isn't part of 00run_pipeline.sh. Uses a
# small dedicated conda env (svgtools, just librsvg) rather than adding
# a graphics dependency to the pipeline's own validate_cs environment.
#
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-o FIGDIR] [-w WIDTH_PX]

Options:
  -o DIR    Output directory for the figure (default: figures)
  -w INT    PNG raster width in pixels; height keeps the 1260:700 aspect
            ratio (default: 3780, i.e. 3x the SVG's native 1260px width)
  -h        Show this help message
EOF
    exit 1
}

FIGDIR="figures"
WIDTH=3780

while getopts "o:w:h" opt; do
    case "$opt" in
        o) FIGDIR=$OPTARG ;;
        w) WIDTH=$OPTARG ;;
        h) usage ;;
        *) usage ;;
    esac
done

command -v mamba >/dev/null 2>&1 || { echo "Error: mamba not found on PATH" >&2; exit 1; }
mamba env list | awk '{print $1}' | grep -qx svgtools || {
    echo "Error: svgtools env not found. Create it with:" >&2
    echo "  mamba create -n svgtools -c conda-forge librsvg -y" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$FIGDIR"

HEIGHT=$(( WIDTH * 700 / 1260 ))

echo "==> Generating SVG..."
python3 "$SCRIPT_DIR/../analysis/canton_s_provenance.py" -o "$FIGDIR/canton_s_provenance.svg"

echo "==> Rasterizing to PNG (${WIDTH}x${HEIGHT})..."
mamba run -n svgtools rsvg-convert \
    -w "$WIDTH" -h "$HEIGHT" --background-color=white \
    -o "$FIGDIR/canton_s_provenance.png" "$FIGDIR/canton_s_provenance.svg"

echo "Done. Wrote $FIGDIR/canton_s_provenance.svg and $FIGDIR/canton_s_provenance.png"
