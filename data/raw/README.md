# data/raw/

Holds the as-downloaded genome assemblies (FASTA, one file per
assembly), written by `10_download_genomes.sh` per the source URLs
listed in `config/genomes.tsv`. Filenames derive from that control
file's `strain`/`suffix` columns.

Not version-controlled; re-downloaded on a fresh run. Read by stage 2
(`20_extract_euchromatin.sh`) and nothing downstream of it.
