# Group 1 -- Kubernetes service, manifest source = K8s Manifest

Tests CDS-126515's `optionalValuesYaml` flag on a raw K8s Manifest source.
The flag applies to the WHOLE manifest's `valuesPaths` list, not per file
(`isOptionalValuesYaml()` in `ManifestTemplatesPathsUtils`), so every test
case below is the SAME service and pipeline -- only the manifest's
`valuesPaths` list and `optionalValuesYaml` flag change between runs.

## Layout

    manifests/deployment.yaml   the manifest under test (go-template)
    values/present.yaml         the only real values file this group needs
    pipeline-group1.yaml
    README.md

`missing-1.yaml` / `missing-2.yaml`, referenced in the table below, are
NEVER created. That is the point -- they must not exist on disk.

## Service configuration

    service:
      name: svc-cds126515-group1
      identifier: svc_cds126515_group1
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
                        - CDS-126515-test/group1-k8s-manifest/manifests
                  valuesPaths:
                    - <SET PER ROW BELOW>
                  optionalValuesYaml: <SET PER ROW BELOW>
                  skipResourceVersioning: false

Swap `connectorRef` for whatever GitHub connector you have pointed at
`datmedevil17/test-test` (or `datmedevil17/pipelinesngautomation`, the
repo's renamed remote) if it isn't `account.cdautomationtest`.

## How to run

1. Repo is already pushed. Re-push after any local edit here.
2. Create the service above.
3. Paste `pipeline-group1.yaml`, replace the `<YOUR_...>` placeholders.
4. For each row below: set `valuesPaths` / `optionalValuesYaml` on the
   service to that row's config, run the pipeline, record step 2's
   pass/fail and step 3's rendered output (if reached).

## Test matrix

| # | valuesPaths | optionalValuesYaml | Expected step 2 (Dry Run) | Expected step 3 (rendered) |
|---|---|---|---|---|
| A1 | `[present.yaml]` | `false` (unset) | PASS | `appName=cds126515-present`, `optional-marker=present-value-applied` |
| A2 | `[missing-1.yaml]` | `false` (unset) | **FAIL** -- regression guard: missing file on a non-optional manifest must still break the deploy | not reached |
| A3 | `[present.yaml]` | `true` | PASS | same as A1 -- flag is a no-op when the file exists |
| A4 | `[missing-1.yaml]` | `true` | **PASS** -- the actual fix under test | every field renders as `<no value>` (Go template's default for a missing key against an empty values map -- no values loaded at all) |
| A5 | `[present.yaml, missing-1.yaml]` | `true` | PASS | same as A1/A3 -- present.yaml's fields applied, the missing path is silently dropped |
| A6 | `[missing-1.yaml, missing-2.yaml]` | `true` | PASS | every field `<no value>`, same as A4 |

## Reading step 1 (`signal evidence`)

Regardless of row, it prints `serviceOutput.manifests.overrides` and
`.optionalOverrides`. Sanity-check per row:

- A1-A3: `overrides` should list `present.yaml`; `optionalOverrides`
  should be empty for A1/unset flag, and list `present.yaml` for A3
  (flag is true even though the file exists).
- A4/A6: `overrides` lists the missing path(s); `optionalOverrides`
  lists the same, confirming Java tagged them optional before the Go
  plugin ever tries to fetch them.
- A2: whatever `overrides` shows, the run fails downstream regardless,
  since nothing is tagged optional.

## If a row disagrees with its expectation

- A2 passing (deploy succeeds with a required file missing) means the
  optional-skip logic is leaking to non-flagged manifests -- too broad.
- A4/A6 failing (deploy dies on "no such file") means
  `PLUGIN_OPTIONAL_VALUES_PATH` isn't reaching the Go plugin, or the
  plugin's `availableValuesPaths()` filter isn't wired for this
  manifest/step combination.
