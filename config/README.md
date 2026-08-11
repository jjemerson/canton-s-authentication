# config/

Holds the pipeline's control files: `genomes.tsv` (the genome panel --
strain, author-abbreviation suffix, role, source URL), `het_boundaries.bed`
(reference heterochromatin/euchromatin boundaries per Muller element),
and `pi_comparisons.tsv` (the curated pairwise comparisons stages 5
and 7 use). Editing these files changes the pipeline's behavior
without touching any code -- see the top-level README's Methods
section for how each is used.
