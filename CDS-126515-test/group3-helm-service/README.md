# Group 3 -- Helm service, manifest source = Helm Chart

Same chart/fixture as group2, but the SERVICE ITSELF is Helm-type
(`serviceDefinition.type: NativeHelm`), not a Kubernetes-type service
using a Helm Chart as its manifest source. This is the only group that
exercises a genuinely Helm-type service end to end.

## Layout

    chart/
      Chart.yaml
      values.yaml              chart's OWN defaults -- always present, never optional
      templates/deployment.yaml
    values/present.yaml        the extra override file this group needs
    pipeline-group3.yaml
    README.md

`missing-1.yaml` / `missing-2.yaml` in the table below are NEVER created.

Same behavioral note as group2 applies: a missing optional file falls
back to the chart's own defaults (not blank, not `<no value>`).

## Service configuration

    service:
      name: svc-cds126515-group3
      identifier: svc_cds126515_group3
      serviceDefinition:
        type: NativeHelm
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
                        - CDS-126515-test/group3-helm-service/chart
                  valuesPaths:
                    - <SET PER ROW BELOW>
                  optionalValuesYaml: <SET PER ROW BELOW>
                  skipResourceVersioning: false

Swap `connectorRef` if your GitHub connector to this repo has a
different id.

## How to run

Same as group1/group2: create the Helm-type service, paste
`pipeline-group3.yaml`, fill in placeholders, then for each row set
`valuesPaths` / `optionalValuesYaml` on the service and re-run.

## Test matrix

| # | valuesPaths | optionalValuesYaml | Expected Render step | Expected rendered output |
|---|---|---|---|---|
| C1 | `[present.yaml]` | `false` (unset) | PASS | `appName=cds126515-present`, `optional-marker=present-value-applied` |
| C2 | `[missing-1.yaml]` | `false` (unset) | **FAIL** -- regression guard | not reached |
| C3 | `[present.yaml]` | `true` | PASS | same as C1 |
| C4 | `[missing-1.yaml]` | `true` | **PASS** -- the fix under test | `appName=chart-default`, `optional-marker=chart-default-flag` |
| C5 | `[present.yaml, missing-1.yaml]` | `true` | PASS | same as C1/C3 |
| C6 | `[missing-1.yaml, missing-2.yaml]` | `true` | PASS | same as C4 |

## Why this group matters separately from group2

The four Go plugins under CDS-126515 split along TWO axes, not one:
`manifestPlugin/{helm,kubernetes}` and `kubernetes-plugin/{helm-template,
k8s-template}`. A Kubernetes-type service rendering a Helm Chart
(group2) and a genuinely Helm-type service (group3) are not guaranteed
to route through the exact same plugin/template -- this group exists to
catch a fix that only landed in one of the two.
