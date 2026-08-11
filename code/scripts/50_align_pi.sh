#!/usr/bin/env bash
#
# 50_align_pi.sh
#
# For every pair listed in the curated pi-comparison control file, aligns
# the two genomes' extracted euchromatin sequence (stage 2 output) and
# calls substitutions -- the input to stage 7's windowed pi plots. Also
# writes a genome-wide pi summary table as a cheap byproduct of the same
# paftools.js call output.
#
# Not exhaustive all-pairs, unlike stage 4: only the pairs listed in
# config/pi_comparisons.tsv are aligned, in that file's order (which
# stage 7 uses as figure row order).
#
# Pairs run concurrently with GNU parallel, same reasoning as stages 1/3/4.
# Each pair's own pipeline is inherently sequential (align -> sort ->
# call, each step depending on the last), but the pairs are independent
# of each other. minimap2 itself has internal parallelism that plateaus
# the same way jellyfish/sort's did, so this follows stage 3's model:
# concurrency and per-job threads both derive from -t (total) and -j
# (per-job), not a hardcoded number.
#
set -euo pipefail
export LC_ALL=C

usage() {
    cat <<EOF
Usage: $(basename "$0") [-i COMPARISONS.tsv] [-p PROCESSED_DIR] [-o SUMMARY_DIR] [-e REPORTS_DIR] [-t THREADS] [-j THREADS_PER_JOB] [-F]

Options:
  -i FILE   Pi-comparison control file (default: config/pi_comparisons.tsv)
  -p DIR    Directory of extracted euchromatin FASTA, from stage 2 (default: data/processed)
  -o DIR    Output directory for the genome-wide pi summary table (default: output/tables)
  -e DIR    Output directory for per-pair alignment reports (.stats) (default: output/reports)
  -t INT    Total threads available (default: nproc, this machine's total)
  -j INT    Threads given to each concurrent pair's minimap2 -- concurrency
            is -t / -j pairs at once. Default: 8 (same plateau reasoning
            as stage 3). Capped at -t on smaller machines.
  -F        Force realignment, overwriting existing output
  -h        Show this help message
EOF
    exit 1
}

COMPARISONS="config/pi_comparisons.tsv"
PROCESSED="data/processed"
SUMMARY_DIR="output/tables"
REPORTS_DIR="output/reports"
THREADS=$(nproc)
THREADS_PER_JOB=8
FORCE=0

while getopts "i:p:o:e:t:j:Fh" opt; do
    case "$opt" in
        i) COMPARISONS=$OPTARG ;;
        p) PROCESSED=$OPTARG ;;
        o) SUMMARY_DIR=$OPTARG ;;
        e) REPORTS_DIR=$OPTARG ;;
        t) THREADS=$OPTARG ;;
        j) THREADS_PER_JOB=$OPTARG ;;
        F) FORCE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -f "$COMPARISONS" ]] || { echo "Error: pi-comparison list not found: $COMPARISONS" >&2; exit 1; }
command -v minimap2  >/dev/null 2>&1 || { echo "Error: minimap2 not found on PATH" >&2; exit 1; }
command -v paftools.js >/dev/null 2>&1 || { echo "Error: paftools.js not found on PATH" >&2; exit 1; }
command -v parallel   >/dev/null 2>&1 || { echo "Error: GNU parallel not found on PATH" >&2; exit 1; }

# Every asm1/asm2 in the comparison list must have a euchromatin FASTA
# from stage 2 -- check up front so a typo doesn't surface halfway
# through an otherwise-successful concurrent batch.
missing=0
while IFS=$'\t' read -r a b; do
    [[ -z "$a" ]] && continue
    for g in "$a" "$b"; do
        [[ -e "$PROCESSED/${g}.fa" ]] || {
            echo "Error: euchromatin FASTA not found for $g: $PROCESSED/${g}.fa (run 20_extract_euchromatin.sh first)" >&2
            missing=1
        }
    done
done < <(tail -n +2 "$COMPARISONS")
[[ "$missing" -eq 0 ]] || exit 1

# Concurrency rounds UP, not down: THREADS_PER_JOB always stays at -j's
# value rather than being redistributed to fit THREADS exactly. Mild
# oversubscription (e.g. 14 threads -> 2 jobs of 8, 16 requested) is a
# well-understood, generally graceful degradation for this kind of mixed
# CPU/IO work.
CONCURRENT=$(( (THREADS + THREADS_PER_JOB - 1) / THREADS_PER_JOB ))
[[ "$CONCURRENT" -lt 1 ]] && CONCURRENT=1

mkdir -p "$PROCESSED" "$SUMMARY_DIR" "$REPORTS_DIR" tmp

echo "Running up to $CONCURRENT pair(s) concurrently, $THREADS_PER_JOB threads each (of $THREADS total)."

# ---------------------------------------------------------------------
# Align and call substitutions for one pair. asm1 is the target/
# reference (minimap2's first positional arg, and paftools.js call -f);
# asm2 is the query -- order preserved from the control file, since
# stage 7 uses it for figure row labeling.
# ---------------------------------------------------------------------
align_pair() {
    local a=$1 b=$2
    local pair="${a}_vs_${b}"
    local calls="$PROCESSED/${pair}.calls.txt"

    if [[ -e "$calls" && "$FORCE" -ne 1 ]]; then
        echo "==> $pair already aligned ($calls), skipping. Use -F to realign."
        return 0
    fi

    echo "==> Aligning $pair..."
    local raw_paf="tmp/${pair}.paf"
    local sorted_paf="$PROCESSED/${pair}.sorted.paf"
    local vcf="$PROCESSED/${pair}.vcf"
    local stats="$REPORTS_DIR/${pair}.stats"

    # asm10, not asm5: asm5 is tuned for ~0.1% divergence (same-individual/
    # isogenic-line territory), well below real between-genome Drosophila
    # nucleotide diversity (commonly ~0.5-1% genome-wide). Under asm5,
    # more-divergent pairs fragment into many short, ambiguous alignment
    # blocks instead of a few long ones, dropping a large and
    # non-random (more-divergent-than-average) slice of the genome from
    # the callable-base count. Extraction (carryover, stage 2) stays on
    # asm5 -- boundary placement there only needs alignment blocks near
    # each arm edge, not comprehensive coverage, so it isn't sensitive to
    # this same tradeoff.
    minimap2 -t "$THREADS_PER_JOB" -cx asm10 --cs "$PROCESSED/${a}.fa" "$PROCESSED/${b}.fa" \
        | tee "$raw_paf" \
        | sort -k6,6 -k8,8n \
        > "$sorted_paf"

    # paftools.js call is run twice -- once per output format needed
    # (-f for VCF, plain for stage 7's calls.txt) -- but both compute the
    # same stats (bases covered, substitutions, indels) from the same
    # alignment, so only the first invocation's stderr is kept; the
    # second's would just be a redundant duplicate appended to the same
    # file, not new information.
    paftools.js call -f "$PROCESSED/${a}.fa" "$sorted_paf" > "$vcf" 2> "$stats"
    paftools.js call "$sorted_paf" > "$calls" 2>/dev/null

    if [[ ! -s "$calls" ]]; then
        echo "Error: no calls produced for $pair -- something's wrong upstream" >&2
        return 1
    fi
    echo "    -> $calls"
}
export -f align_pair
export PROCESSED REPORTS_DIR THREADS_PER_JOB FORCE

set +e
tail -n +2 "$COMPARISONS" | awk 'NF' | parallel --colsep '\t' -j "$CONCURRENT" align_pair {1} {2}
parallel_status=$?
set -e

find tmp -mindepth 1 -not -name README.md -delete

if [[ "$parallel_status" -ne 0 ]]; then
    echo "Error: one or more pairs failed (see above)." >&2
    exit 1
fi

# ---------------------------------------------------------------------
# Genome-wide pi summary: substitutions per callable base, from the
# .stats reports paftools.js call already wrote. Not reported directly
# in the manuscript's text or tables; kept for its own diagnostic value,
# e.g. sanity-checking the windowed figure against a single number.
# ---------------------------------------------------------------------
summary="$SUMMARY_DIR/pi_summary.tsv"
: > "$summary"
while IFS=$'\t' read -r a b; do
    [[ -z "$a" ]] && continue
    pair="${a}_vs_${b}"
    stats="$REPORTS_DIR/${pair}.stats"
    subs=$(grep 'substitutions' "$stats" | awk '{print $1}')
    bases=$(grep 'covered by exactly one contig' "$stats" | awk '{print $1}')
    awk -v s="$subs" -v b="$bases" -v pair="$pair" \
        'BEGIN{printf "%s\t%.6f\t%d\t%d\n", pair, s/b, s, b}'
done < <(tail -n +2 "$COMPARISONS") >> "$summary"

echo "Done. $(( $(wc -l < "$COMPARISONS") - 1 )) pairs aligned. Calls in $PROCESSED/, summary in $summary"
