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

| Group | Service type | Manifest source | Stage runtime | Folder |
|---|---|---|---|---|
| 1 | Kubernetes | K8s Manifest | Kubernetes | `group1-k8s-manifest/` |
| 2 | Kubernetes | Helm Chart | Kubernetes | `group2-k8s-helmchart/` |
| 3 | Helm (`NativeHelm`) | Helm Chart | Kubernetes | `group3-helm-service/` |
| 4 | Kubernetes | K8s Manifest (primary) + Values (secondary) | Kubernetes | `group4-mixed-manifests/` |
| 5 | Kubernetes | K8s Manifest (same fixture as group 1) | **Docker/VM** | `group5-vm-infra/` |
| 6 | Kubernetes | K8s Manifest (same fixture as group 1) | Kubernetes | `group6-delegate-failure/` |

Group 4 is different from 1-3: instead of testing the flag on a single
manifest, it tests whether a SECONDARY manifest's own `optionalValuesYaml`
is honored when the PRIMARY manifest is required. `RenderingStep` currently
resolves the flag off the primary manifest only
(`resolvePrimaryManifestOptionalValuesYaml`), while `overrides` /
`optionalOverrides` are aggregated across all manifest sources
(`ServiceEntityProcessor.getOverrideFilePathsFromInputs`) -- a suspected gap
this group is built to confirm or rule out. See its own README for the
critical row (D4).

Group 5 is also different from 1-3, but along a different axis: it
reuses group 1's exact manifest/values fixture, but runs the stage on a
**Docker/VM runtime** instead of Kubernetes. Groups 1-4 only exercise
`RenderingStep`/`ManifestsStep`'s K8-infra branch
(`handleK8AsyncFailureResponse`); group 5 exists specifically to
exercise the VM/DLITE_VM-infra branch (`handleAsyncResponses`,
`handleVmAsyncSuccessResponses`/`handleVmAsyncFailureResponses`), which
none of the other groups can reach. See its own README for why this
matters for the latest review round's changes.

Group 6 is different again: groups 1-5's "failure" rows are all a
clean fetch that simply doesn't find a declared file
(`StepStatusTaskResponseData` with `FAILURE`). Group 6 instead breaks
the fetch itself (bad branch/connector), producing
`ErrorNotifyResponseData` -- the OTHER failure shape
`handleK8AsyncFailureResponse` handles. It confirms the delegate's own
error text survives intact through the reverted void/throw method.

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
4. Group 5 -- same fixture as group 1, but on a Docker/VM stage runtime.
   Confirms the fix (and this session's review-feedback changes) isn't
   K8-infra-specific either.
5. Group 6 -- same fixture as group 1 again, but breaks the fetch
   itself (bad branch/connector) instead of a missing file. Confirms
   the delegate/task-failure path still surfaces a real error message.

All groups reuse the same connector (`account.cdautomationtest`)
and namespace (`do-not-delete-serverless`) already proven working
elsewhere in this repo (see `smokeTest/`, `CDS-130653-test/`). Swap the
connector if yours differs.
