# Careful: `values.yml` here is BOTH declared and default-named

This folder is the CDS-131003 fixture (`manifests.overrides` must not absorb
fetched manifest paths). Do not repoint it at CDS-131005.

Worth knowing though: `values.yml` is declared in the service `values:` block
AND it matches the default filename convention that CDS-131005 introduces. So
after CDS-131005 the same file arrives through both routes. It must be applied
ONCE, not twice -- `PrependDefaultValueFilePaths` dedupes on the canonical
(absolute, symlink-resolved) path, so it is skipped as a default when it is
already in the declared list.

Applying it twice would not change the merge result, but it would make the step
log claim a layer that is not really there. This folder is the cheapest
real-world check of that dedup: run the CDS-131003 pipeline after CDS-131005
merges and confirm the step log lists `values.yml` exactly once.
