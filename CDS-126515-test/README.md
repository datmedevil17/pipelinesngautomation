# CDS-126515 manual test kit

## Setup (one time)
1. In File Store, upload `chart/` (Chart.yaml, values.yaml, templates/configmap.yaml) to `account:/cds126515-test/chart`.
2. Do **not** upload anything to `account:/cds126515-test/values-missing.yaml` — that path must stay missing.
3. Create the service from `service.yaml`, filling in your org/project.
4. Create the pipeline from `pipeline.yaml`, filling in a real environment + infra (any k8s infra works).

## Case A — optional file missing, flag true (should PASS)
Run as-is (`optionalValuesYaml: true`, `values-missing.yaml` not uploaded).
Expected: ManifestsStep/RenderingStep skip the missing file instead of failing, Helm deploy succeeds using the chart's own `values.yaml` (`message: from-chart-default-values`).

## Case B — optional file missing, flag false (should FAIL — pre-fix behavior / regression check)
Edit `service.yaml`: set `optionalValuesYaml: false` (or delete the line). Re-run.
Expected: fetch/render step fails hard because the declared values file doesn't exist.

## Case C — file present (control, should PASS either way)
Upload `values-present.yaml` to `account:/cds126515-test/values-missing.yaml` (i.e. give it that exact filename in File Store). Re-run with either flag value.
Expected: pass, and the rendered ConfigMap shows `message: from-override-values` instead of the chart default — proves the override is actually applied when present.
