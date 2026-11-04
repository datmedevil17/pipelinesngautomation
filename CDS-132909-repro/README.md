# CDS-132909 fixture

Service `CDS132909Svc` (Kubernetes) -> Manifests -> K8s Manifest:
- Store: GitHub, repo `datmedevil17/test-test`, branch `main` (use your GitHub connector)
- Paths: `CDS-132909-repro/manifests`
- No values file, no artifact needed.

Runs: literal items (pipeline.yaml as-is) -> podIps expression -> stage-variable items -> bash-loop workaround.
