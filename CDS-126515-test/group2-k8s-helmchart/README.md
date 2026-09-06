# Group 2 -- Kubernetes service, manifest source = Helm Chart

Same flag, different manifest type: a Kubernetes-type service whose
manifest source is a Helm Chart. `optionalValuesYaml` applies to the
values file declared on the manifest's `valuesPaths` -- the test is
whether that declared path resolves (the file exists) or not, and
whether the flag lets an unresolved path be skipped instead of failing
the render. This is separate from the chart's own `chart/values.yaml`,
which is never declared via `valuesPaths` and is always present.

## Layout

    chart/
      Chart.yaml
      values.yaml              chart's OWN defaults -- always present, never optional
      templates/deployment.yaml
    values/present.yaml        the values file declared via valuesPaths on the manifest
    pipeline-group2.yaml
    README.md

`missing-1.yaml` / `missing-2.yaml` in the table below are NEVER created.

## Key behavioral difference from group1

Group1's raw K8s Manifest has no built-in defaults, so a missing
optional file renders every field as literal, unrendered
`{{ .Values.X }}`. Helm always has `chart/values.yaml` to fall back to,
so here a missing optional file renders the CHART'S DEFAULTS, not
unrendered template syntax and not `<no value>`. Both are correct --
just don't expect group1's "everything blank" signature here.

## Service configuration

    service:
      name: svc-cds126515-group2
      identifier: svc_cds126515_group2
      serviceDefinition:
        type: Kubernetes
        spec:
          manifests:
            - manifest:
                identifier: helmchart
                type: HelmChart
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: account.cdautomationtest
                      gitFetchType: Branch
                      branch: main
                      paths:
                        - CDS-126515-test/group2-k8s-helmchart/chart
                  valuesPaths:
                    - <SET PER ROW BELOW>
                  optionalValuesYaml: <SET PER ROW BELOW>
                  skipResourceVersioning: false

Swap `connectorRef` if your GitHub connector to this repo has a
different id.

## How to run

Same as group1: create the service, paste `pipeline-group2.yaml`, fill
in placeholders, then for each row set `valuesPaths` /
`optionalValuesYaml` on the service and re-run.

## Test matrix

| # | valuesPaths | optionalValuesYaml | Expected Render step | Expected rendered output |
|---|---|---|---|---|
| B1 | `[present.yaml]` | `false` (unset) | PASS | `appName=cds126515-present`, `optional-marker=present-value-applied` |
| B2 | `[missing-1.yaml]` | `false` (unset) | **FAIL** -- regression guard: fetch fails on a non-optional missing file | not reached |
| B3 | `[present.yaml]` | `true` | PASS | same as B1 |
| B4 | `[missing-1.yaml]` | `true` | **PASS** -- the fix under test | `appName=chart-default`, `optional-marker=chart-default-flag` (chart defaults, not blank) |
| B5 | `[present.yaml, missing-1.yaml]` | `true` | PASS | same as B1/B3 -- present.yaml wins, missing path silently dropped |
| B6 | `[missing-1.yaml, missing-2.yaml]` | `true` | PASS | same as B4 -- chart defaults throughout |

## Reading step 1 (`signal evidence`)

Same as group1: `overrides` should list whatever's declared;
`optionalOverrides` should list only the paths where the flag is true
-- confirm it never includes the chart's own `values.yaml` (that file
is never declared via `valuesPaths`, so it should never appear in
either expression).
