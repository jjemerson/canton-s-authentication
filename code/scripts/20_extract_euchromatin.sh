#!/usr/bin/env bash
#
# 20_extract_euchromatin.sh
#
# For every genome in the genome-list control file, lifts the reference
# genome's euchromatin/heterochromatin boundaries onto that genome (via
# code/src/carryover) and extracts the corresponding arm-labeled
# sequence. Produces one per-arm euchromatin FASTA per genome in
# data/processed/, the shared input to both downstream analyses.
#
# The reference genome is included in its own output (aligned against
# itself) so it participates in Part 1's exhaustive all-pairs comparison
# like every other panel member, rather than being special-cased.
#
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-i GENOMES.tsv] [-c BOUNDARIES.bed] [-r RAWDIR] [-o OUTDIR] [-t THREADS] [-j THREADS_PER_JOB] [-m MINLEN] [-F]

Options:
  -i FILE   Genome-list control file (default: config/genomes.tsv)
  -c FILE   Heterochromatin boundaries BED (default: config/het_boundaries.bed)
  -r DIR    Directory of downloaded genomes, from stage 1 (default: data/raw)
  -o DIR    Output directory for extracted euchromatin FASTA (default: data/processed)
  -t INT    Total threads available (default: nproc, this machine's total)
  -j INT    Threads given to each concurrent genome's minimap2 --
            concurrency rounds UP to cover -t (e.g. 14 threads at the
            default 8 gives 2 concurrent genomes, 16 requested --
            mildly oversubscribed, same reasoning as stages 3/5).
            Default: 8
  -m INT    Minimum sane extracted-arm length in bp; anything shorter
            fails the run (catches an arm whose lift found no qualifying
            alignment support -- see below). Default: 15000000
  -F        Force re-extraction, overwriting existing output
  -h        Show this help message
EOF
    exit 1
}

GENOMES="config/genomes.tsv"
BOUNDARIES="config/het_boundaries.bed"
RAWDIR="data/raw"
OUTDIR="data/processed"
THREADS=$(nproc)
THREADS_PER_JOB=8
MINLEN=15000000
FORCE=0

while getopts "i:c:r:o:t:j:m:Fh" opt; do
    case "$opt" in
        i) GENOMES=$OPTARG ;;
        c) BOUNDARIES=$OPTARG ;;
        r) RAWDIR=$OPTARG ;;
        o) OUTDIR=$OPTARG ;;
        t) THREADS=$OPTARG ;;
        j) THREADS_PER_JOB=$OPTARG ;;
        m) MINLEN=$OPTARG ;;
        F) FORCE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -f "$GENOMES" ]]    || { echo "Error: genome list not found: $GENOMES" >&2; exit 1; }
[[ -f "$BOUNDARIES" ]] || { echo "Error: boundaries file not found: $BOUNDARIES" >&2; exit 1; }
command -v parallel >/dev/null 2>&1 || { echo "Error: GNU parallel not found on PATH" >&2; exit 1; }

CARRYOVER="$(dirname "$0")/../src/carryover"
[[ -x "$CARRYOVER" ]] || { echo "Error: carryover tool not found or not executable: $CARRYOVER" >&2; exit 1; }

# Resolve a genome's downloaded file by label, whichever extension
# 10_download_genomes.sh gave it.
resolve_genome() {
    local label=$1
    if [[ -e "$RAWDIR/${label}.fna.gz" ]]; then
        echo "$RAWDIR/${label}.fna.gz"
    elif [[ -e "$RAWDIR/${label}.fasta" ]]; then
        echo "$RAWDIR/${label}.fasta"
    else
        return 1
    fi
}

# ---------------------------------------------------------------------
# Locate the reference genome (role=reference; exactly one, already
# validated by 10_download_genomes.sh, but re-checked here since this
# stage can run independently).
# ---------------------------------------------------------------------
ref_row=$(tail -n +2 "$GENOMES" | awk -F'\t' '$3 == "reference"')
ref_count=$(echo "$ref_row" | grep -c . || true)
if [[ "$ref_count" -ne 1 ]]; then
    echo "Error: expected exactly one 'reference' genome in $GENOMES, found $ref_count" >&2
    exit 1
fi

ref_strain=$(echo "$ref_row" | cut -f1)
ref_suffix=$(echo "$ref_row" | cut -f2)
ref_label="${ref_strain}_${ref_suffix}"
REF_FASTA=$(resolve_genome "$ref_label") || {
    echo "Error: reference genome '$ref_label' not found in $RAWDIR (run 10_download_genomes.sh first)" >&2
    exit 1
}
echo "Reference genome: $ref_label ($REF_FASTA)"

mkdir -p "$OUTDIR" tmp

CONCURRENT=$(( (THREADS + THREADS_PER_JOB - 1) / THREADS_PER_JOB ))
[[ "$CONCURRENT" -lt 1 ]] && CONCURRENT=1
echo "Running up to $CONCURRENT genome(s) concurrently, $THREADS_PER_JOB threads each (of $THREADS total)."

# ---------------------------------------------------------------------
# Extract one genome's euchromatin sequence. Exported for GNU parallel.
#
# carryover lifts each arm's whole interval and takes the min/max of
# whatever alignment blocks qualify (see carryover -h) -- if a genome's
# assembly is patchy enough near a boundary that essentially nothing
# qualifies, the result can still come back degenerate. Since every real
# Muller arm is tens of Mb, anything under MINLEN is unambiguously that
# failure, not real biology. Both that check and a missing input file
# write their reason to tmp/<label>.failed rather than aborting the
# whole run immediately -- a plain bash array can't collect results
# across parallel's separate subprocesses, and a status file per genome
# means every problem (of either kind, across every genome) still gets
# reported together at the end.
# ---------------------------------------------------------------------
process_genome() {
    local strain=$1 suffix=$2 role=$3
    local label="${strain}_${suffix}"
    local out_fa="$OUTDIR/${label}.fa"

    if [[ -e "$out_fa" && "$FORCE" -ne 1 ]]; then
        echo "==> $label already extracted ($out_fa), skipping. Use -F to re-extract."
    else
        local query_fasta
        query_fasta=$(resolve_genome "$label") || {
            echo "$label: input genome not found in $RAWDIR (run 10_download_genomes.sh first)" > "tmp/${label}.failed"
            return 1
        }

        echo "==> Extracting euchromatin for $label ($role)..."
        "$CARRYOVER" -F -t "$THREADS_PER_JOB" -T tmp \
            -p "tmp/${label}.paf" -c "$BOUNDARIES" -b "tmp/${label}.bed" \
            -r "$REF_FASTA" -f "$out_fa" "$query_fasta"
        echo "    -> $out_fa"
    fi

    local short
    short=$(bioawk -c fastx -v minlen="$MINLEN" \
        '{ if (length($seq) < minlen) print $name"="length($seq)"bp" }' "$out_fa")
    if [[ -n "$short" ]]; then
        echo "$label: $short" > "tmp/${label}.failed"
        return 1
    fi
}
export -f process_genome resolve_genome
export OUTDIR FORCE RAWDIR CARRYOVER THREADS_PER_JOB BOUNDARIES REF_FASTA MINLEN

set +e
tail -n +2 "$GENOMES" | awk 'NF' | parallel --colsep '\t' -j "$CONCURRENT" process_genome {1} {2} {3}
parallel_status=$?
set -e

failed=()
for f in tmp/*.failed; do
    [[ -e "$f" ]] || continue
    failed+=("$(cat "$f")")
done

if [[ "${#failed[@]}" -gt 0 ]]; then
    echo "" >&2
    echo "Error: ${#failed[@]} genome(s) failed (implausibly short arm, or missing input)." >&2
    echo "tmp/*.paf, tmp/*.bed, and tmp/*.failed are left in place (not cleaned up) for debugging." >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi

if [[ "$parallel_status" -ne 0 ]]; then
    echo "Error: one or more genomes failed with no recorded reason (see output above)." >&2
    echo "tmp/ is left in place for debugging." >&2
    exit 1
fi

# tmp/ is scratch space for this stage alone -- nothing downstream reads
# the per-genome .paf/.bed liftover intermediates, so clear them out only
# now that every genome has passed the check above.
find tmp -mindepth 1 -not -name README.md -delete

echo "Done. Euchromatin FASTA written to $OUTDIR/"
