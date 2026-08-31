# CDS-126515 manual test kit

Built against the real service `service_CDS_126515` (NativeHelm, Helm Chart
manifest `m1`, GitHub store) configured directly in the UI rather than
`service.yaml` in this folder — that file is kept only as a File-Store-based
reference/fallback. The actual test toggles happen in the manifest's
**Edit Manifest** dialog (Chart Path, Values.yaml, Optional Values YAML),
not the outer service panel.

## Setup (one time)
1. Push `chart/` (Chart.yaml, values.yaml, templates/configmap.yaml) to this repo under `CDS-126515-test/chart/` — already done if you're reading this from the repo.
2. Do **not** add a `values-missing.yaml` file next to it — that path must stay missing in the repo.
3. In `service_CDS_126515`'s manifest `m1` (Edit Manifest dialog): Chart Path = `CDS-126515-test/chart/`, Values.yaml = `CDS-126515-test/values-missing.yaml`, Optional Values YAML = **True**. Save inside the dialog, then Save the service.
4. Create the pipeline from `pipeline.yaml`, filling in a real environment/infra/connector/namespace (any k8s infra works), and grab the real `uses: helmDeployStep@x.y.z` version from Pipeline Studio's YAML tab (see comment in the file).

## Case A — optional file missing, flag true (should PASS)
Run as-is (`optionalValuesYaml: true`, `values-missing.yaml` not uploaded).
Expected: ManifestsStep/RenderingStep skip the missing file instead of failing, Helm deploy succeeds using the chart's own `values.yaml` (`message: from-chart-default-values`).

## Case B — optional file missing, flag false (should FAIL — pre-fix behavior / regression check)
In the Edit Manifest dialog, set Optional Values YAML back to **False**. Re-run.
Expected: fetch/render step fails hard because the declared values file doesn't exist.

## Case C — file present (control, should PASS either way)
Commit `values-present.yaml` to the repo as `CDS-126515-test/values-missing.yaml` (same path the manifest points at). Re-run with either flag value.
Expected: pass, and the rendered ConfigMap shows `message: from-override-values` instead of the chart default — proves the override is actually applied when present.
