# code/src/

Holds reusable command-line tools shared across pipeline stages,
distinct from the single-purpose plotting scripts in `code/scripts/`.
Currently contains `carryover`, the evidence-based liftover/extraction
tool stage 2 (`20_extract_euchromatin.sh`) uses to lift the reference
assembly's heterochromatin/euchromatin boundaries onto each target
assembly's own coordinates.
