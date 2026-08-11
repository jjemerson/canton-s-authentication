#!/usr/bin/env python3
"""
Windowed pi grid: one row per curated comparison (config/pi_comparisons.tsv
order, matching stage 5's alignment order), one column per chromosome
arm, shared fixed y-range across all panels. This grid layout
(row=comparison, column=arm) is what the manuscript's Figure 2 uses.

Input files are stage 5's output: data/processed/{asm1}_vs_{asm2}.calls.txt
"""
import argparse
import sys
from collections import defaultdict
import numpy as np

ARM_ORDER = ["X", "2L", "2R", "3L", "3R"]


def load_calls(path):
    cov = defaultdict(list)   # chrom -> [(start, end), ...]
    subs = defaultdict(list)  # chrom -> [pos, ...]  (substitutions only, no indels)
    with open(path) as f:
        for line in f:
            t = line.rstrip("\n").split("\t")
            if t[0] == "R":
                cov[t[1]].append((int(t[2]), int(t[3])))
            elif t[0] == "V":
                ref, alt = t[6], t[7]
                if ref != "-" and alt != "-":
                    subs[t[1]].append(int(t[2]))
    return cov, subs


def windowed_pi(cov, subs, window, step):
    """Returns {chrom: [(window_start, pi), ...]} using prefix sums so
    overlapping (sliding) windows are cheap."""
    rows = {}
    for chrom, intervals in cov.items():
        if not intervals:
            continue
        size = max(end for _, end in intervals)
        size = max(size, (max(subs.get(chrom, [0]), default=0) + 1))

        callable_mask = np.zeros(size, dtype=bool)
        for start, end in intervals:
            callable_mask[start:end] = True
        prefix_cov = np.concatenate(([0], np.cumsum(callable_mask, dtype=np.int64)))

        # Only count a substitution if its position is actually covered --
        # paftools.js call emits some V records just outside the "covered
        # by exactly one contig" R intervals (near alignment-block
        # transitions), and counting those unconditionally can make a
        # window's substitution count exceed its own callable-base count,
        # inflating pi past 1 in windows with few real callable bases.
        sub_counts = np.zeros(size, dtype=np.int64)
        for pos in subs.get(chrom, []):
            if pos < size and callable_mask[pos]:
                sub_counts[pos] += 1
        prefix_subs = np.concatenate(([0], np.cumsum(sub_counts, dtype=np.int64)))

        pts = []
        for w in range(0, size, step):
            end = min(w + window, size)
            bases = prefix_cov[end] - prefix_cov[w]
            if bases > 0:
                s = prefix_subs[end] - prefix_subs[w]
                pts.append((w, s / bases))
        rows[chrom] = pts
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--comparisons", default="config/pi_comparisons.tsv",
                         help="Curated pi-comparison control file (default: %(default)s)")
    parser.add_argument("--processed", default="data/processed",
                         help="Directory of stage 5's .calls.txt files (default: %(default)s)")
    parser.add_argument("--output", default="output/figures/pi_grid.svg",
                         help="Output file (default: %(default)s)")
    parser.add_argument("--window", type=int, default=100000,
                         help="Window size in bp (default: %(default)s, matching the manuscript)")
    parser.add_argument("--step", type=int, default=10000,
                         help="Step between window starts in bp (default: %(default)s, matching the manuscript)")
    parser.add_argument("--ymax", type=float, default=0.015,
                         help="Top of the y-axis (default: %(default)s)")
    args = parser.parse_args()

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    pairs = []
    with open(args.comparisons) as f:
        next(f)  # header
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            a, b = line.split("\t")
            pairs.append((a, b))

    data = {}       # (a,b) -> {arm: [(pos, pi), ...]}
    all_arms = set()
    for a, b in pairs:
        path = f"{args.processed}/{a}_vs_{b}.calls.txt"
        try:
            cov, subs = load_calls(path)
        except FileNotFoundError:
            sys.exit(f"Error: {path} not found (run 50_align_pi.sh first)")
        rows = windowed_pi(cov, subs, args.window, args.step)
        data[(a, b)] = rows
        all_arms.update(rows.keys())

    arms = [x for x in ARM_ORDER if x in all_arms] + sorted(all_arms - set(ARM_ORDER))
    n_rows, n_cols = len(pairs), len(arms)

    # padding so lines sitting at pi=0 aren't clipped by the axis line
    pad = args.ymax * 0.03

    fig, axes = plt.subplots(n_rows, n_cols,
                              figsize=(3.0 * n_cols, 1.8 * n_rows),
                              sharex=False, sharey=True, squeeze=False)

    for r, (a, b) in enumerate(pairs):
        for c, arm in enumerate(arms):
            ax = axes[r][c]
            pts = data[(a, b)].get(arm, [])
            if pts:
                ax.plot([p[0] for p in pts], [p[1] for p in pts],
                        linewidth=0.8, color="C0")
            ax.set_ylim(-pad, args.ymax + pad)
            ax.tick_params(labelsize=8)
            if c > 0:
                ax.tick_params(labelleft=False)  # sharey=True -- redundant on cols 1+
            if r == 0:
                ax.set_title(arm, fontsize=11)
            if r == n_rows - 1:
                ax.set_xlabel("position (bp)", fontsize=9)

    plt.tight_layout()
    fig.subplots_adjust(left=0.22)

    # Row labels as horizontal fig-level text rather than each panel's own
    # rotated ylabel -- rotated text stays hard to read at any font size once
    # the whole grid is shrunk to print width, horizontal text doesn't.
    # Anchored off each row's actual y-tick-label extent (not the axes edge,
    # which sits to the right of the tick numbers) so the row label clears
    # the numeric ticks instead of overlapping/intercalating with them.
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    for r, (a, b) in enumerate(pairs):
        ax0 = axes[r][0]
        pos = ax0.get_position()
        y_center = (pos.y0 + pos.y1) / 2
        ticklabels = ax0.get_yticklabels()
        if ticklabels:
            x0_display = min(t.get_window_extent(renderer).x0 for t in ticklabels)
        else:
            x0_display = pos.x0 * fig.bbox.width
        x_fig = fig.transFigure.inverted().transform((x0_display - 8, 0))[0]
        label = f"{a}\nvs {b}".replace("_", " ")
        fig.text(x_fig, y_center, label, ha="right", va="center", fontsize=9)

    plt.savefig(args.output)
    print(f"wrote {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
