# Group 5 -- Kubernetes service, manifest source = K8s Manifest, VM/Docker stage runtime

Identical fixture and test matrix to `group1-k8s-manifest/`, run on a
**non-K8s stage runtime** (`runtime: docker: {}`) instead of
`runtime: kubernetes:`.

## Why this group exists

Groups 1-4 all use `runtime: kubernetes:`, which routes manifest
fetch/render through `ManifestsStep`/`RenderingStep`'s **K8-infra**
branch (`StageInfraDetails.Type.K8` -> `handleK8AsyncFailureResponse`).
None of them ever reach the **VM/DLITE_VM-infra** branch
(`handleAsyncResponses` in `RenderingStep`, `handleVmAsyncSuccessResponses`/
`handleVmAsyncFailureResponses` in `ManifestsStep`).

The latest review round changed both branches:
- `RenderingStep.handleK8AsyncFailureResponse` was reverted to a
  void/throw shape (`ManifestCollectionException`) -- covered by
  groups 1-4's FAIL rows (A2/B2/C2/D3 equivalents).
- `ManifestsStep.handleVmAsyncSuccessResponses` had its redundant
  `!CommandExecutionStatus.FAILURE.equals(...)` filter removed, on the
  theory that `handleVmAsyncFailureResponses` already short-circuits to
  `FAILED` upstream before this method ever sees a failure entry.
  **Nothing in this repo previously exercised that code path at all.**
  This group closes that gap.

Precedent for the runtime-swap technique:
`CDS-130653-repro/pipelines/case07-k8s-stage-infra.yaml` (K8) vs
`case08-docker-runtime.yaml` (docker) -- same service, same steps, only
the stage `runtime:` block differs.

## Layout

    manifests/deployment.yaml   same content as group1's
    values/present.yaml         same content as group1's
    pipeline-group5.yaml
    README.md

`missing-1.yaml` / `missing-2.yaml` are NEVER created -- same convention
as group1.

## Service configuration

Reuse group1's service shape, just repoint the manifest's `paths` at this
folder:

    service:
      name: svc-cds126515-group5
      identifier: svc_cds126515_group5
      serviceDefinition:
        type: Kubernetes
        spec:
          manifests:
            - manifest:
                identifier: k8s
                type: K8sManifest
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: account.cdautomationtest
                      gitFetchType: Branch
                      branch: main
                      paths:
                        - CDS-126515-test/group5-vm-infra/manifests
                  valuesPaths:
                    - <SET PER ROW BELOW>
                  optionalValuesYaml: <SET PER ROW BELOW>
                  skipResourceVersioning: false

The environment/infrastructure target can be the SAME one used for
groups 1-4 -- only the STAGE's `runtime:` block needs to be `docker: {}`
instead of `kubernetes:`, per the case07/case08 precedent. If your infra
setup requires a distinct VM-capable environment, swap
`<YOUR_ENV_ID>`/`<YOUR_INFRA_ID>` accordingly.

## How to run

Same as group1: create the service, paste `pipeline-group5.yaml`, fill
in placeholders, then for each row set `valuesPaths` / `optionalValuesYaml`
on the service and re-run.

## Test matrix

Same 6 rows as group1 (A1-A6), renumbered E1-E6 to keep evidence separate:

| # | valuesPaths | optionalValuesYaml | Expected step 2 (Dry Run) | Expected step 3 (rendered) |
|---|---|---|---|---|
| E1 | `[present.yaml]` | `false` (unset) | PASS | `appName=cds126515-present`, `optional-marker=present-value-applied` |
| E2 | `[missing-1.yaml]` | `false` (unset) | **FAIL** -- regression guard on the VM path | not reached |
| E3 | `[present.yaml]` | `true` | PASS | same as E1 |
| E4 | `[missing-1.yaml]` | `true` | **PASS** -- the fix under test, on the VM path | every field `<no value>` (same as group1's A4) |
| E5 | `[present.yaml, missing-1.yaml]` | `true` | PASS | same as E1/E3 |
| E6 | `[missing-1.yaml, missing-2.yaml]` | `true` | PASS | every field `<no value>`, same as E4 |

## What this row set is actually proving

- **E1/E3/E5** exercise `handleVmAsyncSuccessResponses` on a genuine
  SUCCESS response -- confirms removing the `FAILURE` filter didn't
  break the normal success path (nothing to filter out, so the map
  should be unchanged from before the review fix).
- **E2** exercises `handleVmAsyncFailureResponses` -- confirms it alone
  (without help from `handleVmAsyncSuccessResponses`'s removed filter)
  still short-circuits the stage to FAILED when the fetch plugin
  reports `CommandExecutionStatus.FAILURE`. This is the row that would
  catch a regression if the filter removal was wrong.
- **E4/E6** confirm the optional-skip behavior itself is infra-agnostic
  -- same outcome as K8-infra's A4/A6, just reached via
  `handleAsyncResponses` instead of `handleK8AsyncFailureResponse`.

## If a row disagrees with its expectation

- E2 passing (deploy succeeds with a required file missing) on the VM
  path specifically -- and NOT on group1's equivalent K8-infra row --
  would mean the filter removal in `handleVmAsyncSuccessResponses` was
  in fact load-bearing, i.e. `handleVmAsyncFailureResponses` does not
  reliably short-circuit before it runs. That's the one regression this
  group is built to catch.
- E4/E6 failing means the VM-side fetch plugin isn't receiving/honoring
  `PLUGIN_OPTIONAL_VALUES_PATH` the same way the K8 path does -- worth
  comparing against group1's A4 result on the same commit.
