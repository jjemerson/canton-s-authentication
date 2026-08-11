#!/usr/bin/env bash
#
# 40_mash_distance.sh
#
# For every pairwise combination of genomes, computes Jaccard similarity
# and Mash distance from stage 3's singleton k-mer lists. Exhaustive
# all-pairs (not curated, unlike stage 5's alignment comparisons) --
# C(n,2) pairs for n genomes.
#
# Pairs are run concurrently with GNU parallel, same reasoning as stage
# 3 -- except a single comm/awk pass here has no internal parallelism to
# plateau (unlike jellyfish/sort), so there's no per-job thread count to
# balance against concurrency; -j can go close to nproc directly.
#
# LC_ALL=C: comm's default locale-aware collation is dramatically slower
# than byte-wise comparison for no benefit here (k-mers are plain ACGT,
# no actual locale-dependent ordering needed). Also makes sort order
# machine-independent, which matters for a reproduction repo: byte-wise
# C-locale ordering is stable everywhere, locale-aware ordering can
# differ by what's installed on a given system.
#
set -euo pipefail
export LC_ALL=C

usage() {
    cat <<EOF
Usage: $(basename "$0") [-i GENOMES.tsv] [-p PROCESSED_DIR] [-o OUTFILE] [-k KMER_LEN] [-j CONCURRENT] [-F]

Options:
  -i FILE   Genome-list control file (default: config/genomes.tsv)
  -p DIR    Directory of singleton k-mer lists, from stage 3 (default: data/processed)
  -o FILE   Output distances file (default: data/processed/distances.tsv)
  -k INT    K-mer length, must match stage 3 (default: 21)
  -j INT    Pairwise comparisons to run concurrently (default: nproc, this machine's total)
  -F        Force recomputation even if the output file already exists
  -h        Show this help message
EOF
    exit 1
}

GENOMES="config/genomes.tsv"
PROCESSED="data/processed"
OUTFILE="data/processed/distances.tsv"
KMER=21
CONCURRENT=$(nproc)
FORCE=0

while getopts "i:p:o:k:j:Fh" opt; do
    case "$opt" in
        i) GENOMES=$OPTARG ;;
        p) PROCESSED=$OPTARG ;;
        o) OUTFILE=$OPTARG ;;
        k) KMER=$OPTARG ;;
        j) CONCURRENT=$OPTARG ;;
        F) FORCE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -f "$GENOMES" ]] || { echo "Error: genome list not found: $GENOMES" >&2; exit 1; }
command -v parallel >/dev/null 2>&1 || { echo "Error: GNU parallel not found on PATH" >&2; exit 1; }

if [[ -e "$OUTFILE" && "$FORCE" -ne 1 ]]; then
    echo "==> $OUTFILE already exists, skipping. Use -F to recompute."
    exit 0
fi

labels=()
while IFS= read -r line; do labels+=("$line"); done \
    < <(tail -n +2 "$GENOMES" | awk -F'\t' '{print $1"_"$2}')
n=${#labels[@]}
echo "$n genomes -> $(( n * (n - 1) / 2 )) pairwise comparisons, up to $CONCURRENT concurrent"

# ---------------------------------------------------------------------
# Jaccard/Mash-D for one pair. A single, unsuppressed `comm` pass gives
# all three counts at once (lines unique to A: no leading tab; unique
# to B: one leading tab; common to both: two leading tabs), instead of
# three separate comm passes over the same two files -- same result,
# a third of the I/O.
# ---------------------------------------------------------------------
pair_distance() {
    local a=$1 b=$2
    local fa="$PROCESSED/${a}.singletons.txt"
    local fb="$PROCESSED/${b}.singletons.txt"

    if [[ ! -e "$fa" || ! -e "$fb" ]]; then
        echo "Error: missing singleton list for $a vs $b (run 30_kmer_count.sh first)" >&2
        return 1
    fi

    comm "$fa" "$fb" | awk -v a="$a" -v b="$b" -v k="$KMER" '
        {
            if (substr($0,1,1) != "\t")      aonly++
            else if (substr($0,2,1) != "\t") bonly++
            else                              inter++
        }
        END {
            union = aonly + bonly + inter
            if (union == 0) {
                print "Error: empty union for " a " vs " b > "/dev/stderr"
                exit 1
            }
            j = inter / union
            d = -1/k * log(2*j / (1+j))
            printf "%s\t%s\t%.6f\n", a, b, d
        }
    '
}
export -f pair_distance
export PROCESSED KMER

set +e
{
    for (( i = 0; i < n; i++ )); do
        for (( j = i + 1; j < n; j++ )); do
            printf '%s\t%s\n' "${labels[$i]}" "${labels[$j]}"
        done
    done
} | parallel --colsep '\t' --keep-order -j "$CONCURRENT" pair_distance {1} {2} > "${OUTFILE}.tmp"
parallel_status=$?
set -e

if [[ "$parallel_status" -ne 0 ]]; then
    echo "Error: one or more pairs failed (see above). Partial output left at ${OUTFILE}.tmp for debugging." >&2
    exit 1
fi

mv "${OUTFILE}.tmp" "$OUTFILE"
echo "Done. $(wc -l < "$OUTFILE") pairwise distances written to $OUTFILE"
