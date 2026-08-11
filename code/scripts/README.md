# code/scripts/

Holds the pipeline itself: the seven numbered stage scripts
(`10_download_genomes.sh` through `70_plot_alignment.sh`), the
`00run_pipeline.sh` orchestrator, and `configure.sh` (one-time
environment bootstrap). Run these from the repo root, e.g.
`./code/scripts/00run_pipeline.sh` -- they resolve `config/`, `data/`,
and `output/` relative to the caller's working directory, not their
own location. See the top-level README's Installation section for the
full setup sequence, and `-h`/`--help` on any individual script for its
own options.
