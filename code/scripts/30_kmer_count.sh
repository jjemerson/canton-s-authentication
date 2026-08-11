#!/usr/bin/env bash
#
# 30_kmer_count.sh
#
# For every genome's extracted euchromatin FASTA (stage 2 output), counts
# canonical k-mers with Jellyfish and extracts the singleton (count==1)
# k-mers as a sorted list -- the input to stage 4's Jaccard/Mash-D
# calculation.
#
# Genomes are processed with GNU parallel rather than one at a time: a
# single jellyfish/sort invocation's own internal parallelism (-t/
# --parallel) plateaus well before this machine's full core count, so
# using the rest of the cores means running multiple genomes'
# jellyfish+sort pipelines concurrently instead of pushing one pipeline's
# thread count further. Concurrency and per-job threads both derive from
# -t (default: nproc), not a hardcoded number, so this scales down
# gracefully on smaller machines too.
#
# LC_ALL=C: sort's default locale-aware collation is dramatically slower
# than byte-wise comparison for no benefit here (k-mers are plain ACGT,
# no locale-dependent ordering needed). Also makes sort order
# machine-independent, which matters for a reproduction repo.
#
set -euo pipefail
export LC_ALL=C

usage() {
    cat <<EOF
Usage: $(basename "$0") [-i GENOMES.tsv] [-p PROCESSED_DIR] [-k KMER_LEN] [-t THREADS] [-j THREADS_PER_JOB] [-F]

Options:
  -i FILE   Genome-list control file (default: config/genomes.tsv)
  -p DIR    Directory of extracted euchromatin FASTA, from stage 2 (default: data/processed)
  -k INT    K-mer length (default: 21)
  -t INT    Total threads available (default: nproc, this machine's total)
  -j INT    Threads given to each concurrent genome's jellyfish/sort --
            concurrency is -t / -j genomes at once. Default: 8 (near
            where a single sort/jellyfish's own parallelism plateaus;
            see 20260807 discussion in REFACTOR_SPEC.md). Capped at -t
            on smaller machines.
  -F        Force re-count, overwriting existing output
  -h        Show this help message
EOF
    exit 1
}

GENOMES="config/genomes.tsv"
PROCESSED="data/processed"
KMER=21
THREADS=$(nproc)
THREADS_PER_JOB=8
FORCE=0

while getopts "i:p:k:t:j:Fh" opt; do
    case "$opt" in
        i) GENOMES=$OPTARG ;;
        p) PROCESSED=$OPTARG ;;
        k) KMER=$OPTARG ;;
        t) THREADS=$OPTARG ;;
        j) THREADS_PER_JOB=$OPTARG ;;
        F) FORCE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -f "$GENOMES" ]] || { echo "Error: genome list not found: $GENOMES" >&2; exit 1; }
command -v jellyfish >/dev/null 2>&1 || { echo "Error: jellyfish not found on PATH" >&2; exit 1; }
command -v parallel  >/dev/null 2>&1 || { echo "Error: GNU parallel not found on PATH" >&2; exit 1; }

# Concurrency rounds UP, not down: THREADS_PER_JOB always stays at -j's
# value rather than being redistributed to fit THREADS exactly. Mild
# oversubscription (e.g. 14 threads -> 2 jobs of 8, 16 requested) is a
# well-understood, generally graceful degradation for this kind of mixed
# CPU/IO work.
CONCURRENT=$(( (THREADS + THREADS_PER_JOB - 1) / THREADS_PER_JOB ))
[[ "$CONCURRENT" -lt 1 ]] && CONCURRENT=1

mkdir -p "$PROCESSED" tmp

echo "Running up to $CONCURRENT genome(s) concurrently, $THREADS_PER_JOB threads each (of $THREADS total)."

# ---------------------------------------------------------------------
# Count singleton k-mers for one genome. Exported for GNU parallel to
# call directly. Each genome's Jellyfish database (order 1GB) is removed
# right after dumping rather than kept around -- opaque binary format,
# not useful for debugging, and wasteful to accumulate across concurrent
# jobs for no benefit.
# ---------------------------------------------------------------------
process_genome() {
    local strain=$1 suffix=$2 role=$3
    local label="${strain}_${suffix}"

    local euchromatin_fa="$PROCESSED/${label}.fa"
    if [[ ! -e "$euchromatin_fa" ]]; then
        echo "Error: euchromatin FASTA not found for $label: $euchromatin_fa (run 20_extract_euchromatin.sh first)" >&2
        return 1
    fi

    local out_singletons="$PROCESSED/${label}.singletons.txt"
    if [[ -e "$out_singletons" && "$FORCE" -ne 1 ]]; then
        echo "==> $label already counted ($out_singletons), skipping. Use -F to re-count."
        return 0
    fi

    echo "==> Counting ${KMER}-mers for $label..."
    local jf_db="tmp/${label}.jf"
    jellyfish count -m "$KMER" -s 500M -C -t "$THREADS_PER_JOB" "$euchromatin_fa" -o "$jf_db"
    jellyfish dump -L 1 -U 1 -c "$jf_db" \
        | awk '{print $1}' \
        | sort --parallel="$THREADS_PER_JOB" -S 4G > "$out_singletons"
    rm -f "$jf_db"

    if [[ ! -s "$out_singletons" ]]; then
        echo "Error: no singleton k-mers found for $label -- something's wrong upstream" >&2
        return 1
    fi
    echo "    -> $out_singletons ($(wc -l < "$out_singletons") singleton ${KMER}-mers)"
}
export -f process_genome
export PROCESSED KMER THREADS_PER_JOB FORCE

set +e
tail -n +2 "$GENOMES" | awk 'NF' | parallel --colsep '\t' -j "$CONCURRENT" process_genome {1} {2} {3}
parallel_status=$?
set -e

find tmp -mindepth 1 -not -name README.md -delete

if [[ "$parallel_status" -ne 0 ]]; then
    echo "Error: one or more genomes failed (see above)." >&2
    exit 1
fi

echo "Done. Singleton k-mer lists written to $PROCESSED/"
