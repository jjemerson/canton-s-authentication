# figures/

Hand-curated figures for the manuscript that aren't outputs of the
genome-analysis pipeline (contrast with `output/figures/`, which is
entirely regenerated from `config/genomes.tsv` and isn't
version-controlled). These have no input data file, so the rendered
images are committed here; the generator code lives in
`code/analysis/canton_s_provenance.py` and is run via
`code/scripts/render_provenance.sh`.

- `canton_s_provenance.svg` / `canton_s_provenance.png` -- Canton-S
  custody, propagation, and public deposition across stock centers and
  labs, drawn to a real calendar-year scale. Embedded in the top-level
  README as Supplementary Figure S1.

## Regenerating

```
mamba create -n svgtools -c conda-forge librsvg -y   # one-time
./code/scripts/render_provenance.sh
```
