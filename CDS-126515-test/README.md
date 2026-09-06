# CDS-126515-test -- optional values-YAML files must not fail a deploy

CDS-126515 adds an `optionalValuesYaml` flag to a manifest source. When
set, a values file declared in that manifest's `valuesPaths` that is
missing on fetch is skipped instead of failing the deploy. The flag
applies to the whole manifest (all its `valuesPaths` at once), not per
file -- confirmed via `isOptionalValuesYaml()` in
`ManifestTemplatesPathsUtils` and the Go plugins' `availableValuesPaths()`.

The manifest-type dropdown for a Kubernetes service offers **K8s
Manifest** or **Helm Chart**; a Helm-type service offers **Helm Chart**
only. That gives three manifest-source combinations, each run through
the same 6-case flag/file-presence matrix -- 18 tests total, split into
three folders below.

| Group | Service type | Manifest source | Folder |
|---|---|---|---|
| 1 | Kubernetes | K8s Manifest | `group1-k8s-manifest/` |
| 2 | Kubernetes | Helm Chart | `group2-k8s-helmchart/` |
| 3 | Helm (`NativeHelm`) | Helm Chart | `group3-helm-service/` |

Each group's README has: the service YAML to create, the pipeline to
run unchanged across all 6 rows, and a table of `valuesPaths` /
`optionalValuesYaml` combinations to set between runs with the exact
expected result for each.

## Order to run in

1. Group 1 first -- it's the simplest case (no chart defaults to
   confuse a missing-file result with a fallback).
2. Group 2 -- same service type, switches the manifest source to a
   Helm Chart. Confirms the flag isn't K8sManifest-specific.
3. Group 3 -- switches the SERVICE type to Helm. Confirms the fix
   landed in the Helm-service code path too, not just the
   Kubernetes-service one.

All three groups reuse the same connector (`account.cdautomationtest`)
and namespace (`do-not-delete-serverless`) already proven working
elsewhere in this repo (see `smokeTest/`, `CDS-130653-test/`). Swap the
connector if yours differs.
