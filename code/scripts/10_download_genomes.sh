#!/usr/bin/env bash
#
# 10_download_genomes.sh
#
# Downloads every genome assembly listed in the genome-list control file
# to data/raw/, named by each genome's combined {strain}{suffix} label.
# Validates that the control file has exactly one `focal` and one
# `reference` genome before downloading anything.
#
# Downloads run with modest concurrency (GNU parallel, default 4) --
# unlike stages 3/4, the bottleneck here is network bandwidth and the
# remote server's willingness to serve concurrent connections, not local
# CPU, so this isn't about using more cores. 4 is deliberately not
# pushed higher, to stay a good citizen toward shared public
# infrastructure rather than squeeze out maximum throughput.
#
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-i GENOMES.tsv] [-o OUTDIR] [-j CONCURRENT] [-F]

Options:
  -i FILE   Genome-list control file (default: config/genomes.tsv)
  -o DIR    Output directory for downloaded assemblies (default: data/raw)
  -j INT    Concurrent downloads (default: 4)
  -F        Force re-download, overwriting existing files
  -h        Show this help message
EOF
    exit 1
}

GENOMES="config/genomes.tsv"
OUTDIR="data/raw"
CONCURRENT=4
FORCE=0

while getopts "i:o:j:Fh" opt; do
    case "$opt" in
        i) GENOMES=$OPTARG ;;
        o) OUTDIR=$OPTARG ;;
        j) CONCURRENT=$OPTARG ;;
        F) FORCE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -f "$GENOMES" ]] || { echo "Error: genome list not found: $GENOMES" >&2; exit 1; }
command -v parallel >/dev/null 2>&1 || { echo "Error: GNU parallel not found on PATH" >&2; exit 1; }

# ---------------------------------------------------------------------
# Validate roles: exactly one focal, exactly one reference.
# ---------------------------------------------------------------------
n_focal=$(tail -n +2 "$GENOMES" | awk -F'\t' '$3 == "focal"' | wc -l)
n_reference=$(tail -n +2 "$GENOMES" | awk -F'\t' '$3 == "reference"' | wc -l)

if [[ "$n_focal" -ne 1 ]]; then
    echo "Error: expected exactly one 'focal' genome in $GENOMES, found $n_focal" >&2
    exit 1
fi
if [[ "$n_reference" -ne 1 ]]; then
    echo "Error: expected exactly one 'reference' genome in $GENOMES, found $n_reference" >&2
    exit 1
fi

mkdir -p "$OUTDIR"

# ---------------------------------------------------------------------
# Download one genome. Output extension is decided by sniffing the
# downloaded content's gzip magic bytes, not by guessing from the URL --
# e.g. the Google-Drive-hosted genome has no filename in its URL at all,
# and isn't gzip-compressed while the NCBI ones are.
# ---------------------------------------------------------------------
download_genome() {
    local strain=$1 suffix=$2 role=$3 url=$4
    local label="${strain}_${suffix}"

    local existing=""
    [[ -e "$OUTDIR/${label}.fna.gz" ]] && existing="$OUTDIR/${label}.fna.gz"
    [[ -e "$OUTDIR/${label}.fasta"  ]] && existing="$OUTDIR/${label}.fasta"
    if [[ -n "$existing" && "$FORCE" -ne 1 ]]; then
        echo "==> $label already present ($existing), skipping. Use -F to re-download."
        return 0
    fi

    echo "==> Downloading $label ($role)..."
    local tmp
    tmp=$(mktemp "$OUTDIR/.download.XXXXXX")
    wget -q -O "$tmp" "$url"

    local magic out
    magic=$(head -c2 "$tmp" | od -An -tx1 | tr -d ' \n')
    if [[ "$magic" == "1f8b" ]]; then
        out="$OUTDIR/${label}.fna.gz"
    else
        out="$OUTDIR/${label}.fasta"
    fi

    mv "$tmp" "$out"
    echo "    -> $out"
}
export -f download_genome
export OUTDIR FORCE

set +e
tail -n +2 "$GENOMES" | awk 'NF' | parallel --colsep '\t' -j "$CONCURRENT" download_genome {1} {2} {3} {4}
parallel_status=$?
set -e

if [[ "$parallel_status" -ne 0 ]]; then
    echo "Error: one or more downloads failed (see above)." >&2
    exit 1
fi

echo "Done. Genomes written to $OUTDIR/"
