# code/analysis/

Holds the R and Python analysis code the pipeline's later stages call:
`plot_kmer_swarm.R` and `plot_kmer_tree.R` (called by
`60_plot_kmer.sh`), and `plot_alignment_grid.py` (called by
`70_plot_alignment.sh`). Grouped here rather than under `scripts/`
because visualization is itself a form of analysis -- each of these
does real statistical/categorical work (e.g. the swarm plot's
comparison-category logic, the windowed-pi callable-base masking), not
just formatting; the figure is the output, not the point of the
distinction. Each script takes its inputs and output path as
command-line arguments; see `-h`/`--help` on any of them for details.
