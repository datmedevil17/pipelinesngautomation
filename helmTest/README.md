# helmTest — CDS-131003 smoke fixture (Helm swimlane)

This fixture exists for ONE reason: `RenderingStep.saveRenderingStepOutput` is
manifest-type agnostic, and `k8sHelmTemplateAction` defaults its `values` input
to `${{manifests.overrides}}`. So the CDS-131003 change reaches Helm too, and
this proves it did not break the Helm swimlane.

It is NOT a CDS-131005 test. Helm reads its chart's own `values.yaml` natively;
there is no "discovery by convention" for the manager to get wrong.

Service layout:

    helmTest/chart/              <- manifest path (store.spec.paths)
      Chart.yaml
      values.yaml                <- the chart's OWN values, read natively by helm
      values-leak.yaml           <- CDS-131003 canary; helm can NEVER read this
      templates/
        deployment.yaml          <- the manifest under test
    helmTest/helmValues/
      values-a.yaml              <- DECLARED via manifest.spec.valuesPaths[0]
      values-b.yaml              <- DECLARED via manifest.spec.valuesPaths[1]

## Assert table — rendered output

| field            | PASS                | FAIL means                                      |
|------------------|---------------------|-------------------------------------------------|
| `metadata.name`  | `cds131003-helm`    | empty -> chart values not read at all           |
| `spec.replicas`  | `3`                 | empty -> chart values not read at all           |
| `image`          | `nginx:1.25`        | empty -> chart values not read at all           |
| `tier`           | `qa`                | `default-tier` -> chart values applied LAST     |
| `containerPort`  | `256`               | `512`/`1024` -> not last-declared-wins          |
| `owner`          | the service name    | `<+service.name>` -> not resolved via toTemplate|
| `leak-canary`    | empty               | `LEAK-DETECTED` -> CDS-131003 leak present      |

Note: helm renders an unsupplied key as an EMPTY string, not Go
text/template's `<no value>` (verified against helm v4.2.1). The k8s fixture's
equivalent canary prints `<no value>`; the assert accepts either.

Two independent detectors for the same regression:

1. **`leak-canary`** — fires only if `values-leak.yaml` reached the `-f` list.
2. **`tier` / `containerPort`** — the union in the old `RenderingStep` APPENDED
   fetched paths after the declared ones, so a leaked `chart/values.yaml` would
   land LAST on the `-f` list and win. `default-tier` / `1024` is that failure.

## Overrides assert (CDS-131003)

`serviceOutput.manifests.overrides` must contain EXACTLY the two declared files
and nothing else — no `chart/values.yaml`, no `values-leak.yaml`, no
`Chart.yaml`, no `deployment.yaml`.
