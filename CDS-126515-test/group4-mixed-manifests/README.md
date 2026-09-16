# Group 4 -- mixed manifests: primary required + secondary optional

This group does NOT test the same thing as groups 1-3. Those all test a
**single** manifest source's `optionalValuesYaml` flag. This group tests a
suspected gap in how that flag interacts with **multiple** manifest sources
on the same service:

- `ServiceEntityProcessor.getOverrideFilePathsFromInputs()` aggregates
  `overrides` / `optionalOverrides` across **every** manifest source on the
  service (primary and non-primary).
- `RenderingStep.resolvePrimaryManifestOptionalValuesYaml()` -- the flag that
  actually gates the missing-file filtering in `saveRenderingStepOutput` --
  only reads the **PRIMARY** manifest's `optionalValuesYaml`.

So: if the primary manifest is required (`optionalValuesYaml: false`) but a
SECONDARY manifest is optional and its file is missing, the design intent is
for that missing file to be silently skipped (same as if it were the
primary that was optional). Whether that actually happens is what this group
checks.

## Layout

    manifests/deployment.yaml        primary manifest's content (go-template)
    values/present-primary.yaml      primary manifest's values file -- ALWAYS present, ALWAYS required
    values/present-secondary.yaml    secondary (Values-type) manifest's file -- present in baseline rows only
    pipeline-group4.yaml
    README.md

`missing-secondary.yaml`, referenced in the table below, is NEVER created.

## Service configuration

    service:
      name: svc-cds126515-group4
      identifier: svc_cds126515_group4
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
                        - CDS-126515-test/group4-mixed-manifests/manifests
                  valuesPaths:
                    - CDS-126515-test/group4-mixed-manifests/values/present-primary.yaml
                  optionalValuesYaml: false
                  skipResourceVersioning: false
            - manifest:
                identifier: extravalues
                type: Values
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: account.cdautomationtest
                      gitFetchType: Branch
                      branch: main
                      paths:
                        - <SET PER ROW BELOW>
                  optionalValuesYaml: <SET PER ROW BELOW>

Swap `connectorRef` if your GitHub connector to this repo has a different id.

**If the UI doesn't expose an "Optional" toggle for a `Values`-type
manifest** (CDS-126515's UI work may have only wired the checkbox onto
K8sManifest/HelmChart), open the manifest in the YAML editor and add
`optionalValuesYaml: true` under its `spec` by hand -- the Java-side flag
(`ManifestTemplatesPathsUtils.isOptionalValuesYaml`) reads generically off
any manifest's inputs, regardless of type, so it should still take effect
even if the UI control isn't there yet.

## How to run

1. Repo is already pushed. Re-push after any local edit here.
2. Create the service above (primary manifest config never changes).
3. Paste `pipeline-group4.yaml`, replace the `<YOUR_...>` placeholders.
4. For each row below: set the SECONDARY manifest's path / `optionalValuesYaml`
   to that row's config, run the pipeline, record step 2's pass/fail and
   step 3's rendered output (if reached).

## Test matrix

Primary manifest is fixed for every row: `valuesPaths: [present-primary.yaml]`, `optionalValuesYaml: false`.

| # | Secondary path | Secondary optionalValuesYaml | Design-intent result | If the bug is present |
|---|---|---|---|---|
| D1 | `[present-secondary.yaml]` | `false` (unset) | PASS -- baseline, nothing missing | same, no divergence |
| D2 | `[present-secondary.yaml]` | `true` | PASS -- flag is a no-op when the file exists | same, no divergence |
| D3 | `[missing-secondary.yaml]` | `false` (unset) | **FAIL** -- regression guard: a required secondary file missing must still break the deploy | same, no divergence |
| D4 | `[missing-secondary.yaml]` | `true` | **PASS** -- this is the actual case under test: secondary is optional, its file is missing, primary is untouched and required | **FAILS** -- because `resolvePrimaryManifestOptionalValuesYaml` reads only the primary's `false`, so `saveRenderingStepOutput` never filters the missing secondary path out of the aggregated `overrides` list, and it gets passed downstream as if it were a real file |

**D4 is the row that answers the open question.** If D4 passes, the gap
described above doesn't actually manifest (maybe something else already
guards it -- worth re-checking the code path that consumes `overrides`
before concluding that). If D4 fails, it confirms the primary-only check is
the bug: a secondary manifest's own optional flag is being ignored in favor
of the primary's, even though `overrides`/`optionalOverrides` are already
built as an aggregate across all manifests.

## Reading step 1 (`signal evidence`)

- D1-D3: `optionalOverrides` should be empty for D1/D3 (secondary flag
  unset), and list the secondary path for D2 (flag true even though the
  file exists).
- D4: `optionalOverrides` SHOULD list the secondary (missing) path -- that
  part of the aggregation (`ServiceEntityProcessor`) is not in question.
  What's in question is whether that listing is actually *acted on* before
  the path reaches the plugin, which step 1 alone can't show you -- that's
  what step 2's pass/fail tells you.

## If a row disagrees with its expectation

- D3 passing (deploy succeeds with the required secondary file missing)
  means the optional-skip logic is leaking to non-flagged manifests -- too
  broad, unrelated to this group's main question but worth flagging on its
  own.
- D4 failing is the expected confirmation of the reported gap, not a
  surprise -- see `RenderingStep.saveRenderingStepOutput` /
  `resolvePrimaryManifestOptionalValuesYaml`.
- D4 passing despite the code reading only the primary flag would be
  surprising and worth re-tracing (e.g. maybe the Go plugin's own
  `availableValuesPaths()` file-exists check independently no-ops on a
  missing path regardless of what Java decided -- if so, the "bug" may be
  cosmetic/non-fatal rather than deploy-breaking, which changes how urgent
  the Java-side fix actually is).
