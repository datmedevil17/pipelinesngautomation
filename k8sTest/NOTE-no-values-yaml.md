# Deliberately NO `values.yaml` in this folder

The k8s-template plugin auto-probes the manifest dir for `values.yml` /
`values.yaml` and prepends whatever it finds. A file with that name here would
silently become an extra values layer and would confound the ordering
assertions in the pipeline.

The undeclared-`values.yaml` case is already covered by the separate fixture at
`CDS-131003-test/repo-fixtures/k8s/` + `pipeline-k8s-regression.yaml`.
Keep the two cases in different repo folders.
