# code/bin/

Generic location for compiled binaries from this project's standard
directory scaffold (source tracked in `code/src/`, compiled artifacts
gitignored here). Nothing in this pipeline is compiled -- every tool
it calls is either an external dependency (see `environment.yml`) or a
script in `code/scripts/`/`code/src/`. Left in place only for
consistency with the scaffold's directory structure; safe to ignore
unless a compiled tool is added later.
