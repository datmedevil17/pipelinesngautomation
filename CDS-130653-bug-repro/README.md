# CDS-130653 -- one-pipeline bug repro

Self-contained. Needs **no new plugin image and no service restart** -- the bug
is entirely manager-side, so it reproduces against whatever ci-manager is
already running.

```
manifests/templates/deployment.yaml   fixture: all {{ }}, and NO values.yaml
service.yaml                          k8s service, values: [], PreHook writes values.yaml
pipeline.yaml                         evidence -> Dry Run -> assert
```

## Run it

1. Commit and push this folder. The pipeline fetches from git, not from your
   working copy.
2. Create the service from `service.yaml`, filling in `<YOUR_GIT_CONNECTOR>`.
   `repo` and `branch` are already set to `test-test` / `main`.
3. Create the pipeline from `pipeline.yaml` and fill in `<YOUR_SERVICE_ID>`,
   `<YOUR_ENV_ID>`, `<YOUR_INFRA_ID>`, `<YOUR_NAMESPACE>`, `<YOUR_K8S_CONNECTOR>`.
4. Run.

## What the bug looks like

| where | before the fix | after the fix |
|---|---|---|
| step `evidence` | `overrides=empty toTemplate=empty toRender=empty`, prints `BUG PRESENT` | lists are populated, prints `gate will pass` |
| stage log tabs | `createValuesFile` -> `manifest-templating` | `createValuesFile` -> **`templating-fetch-files`** -> `manifest-templating` |
| `Dry Run` | FAILS: `replicas: {{ .Values.replicaCount }}` is not an integer | passes |
| step `assert` | "no rendered copy exists", 4 FAILs | 4/4 PASS + `no <no value> left` |

The Dry Run failure IS the repro, not a broken fixture.

## Why it happens

The stage has exactly one fetch, inside `RenderingStep`, and it runs **before**
the pre-hooks. At that moment no values file exists on disk, so the fetch
returns nothing and `manifests.toTemplate` / `overrides` stay empty. The
pre-hook then creates the file, but `handleHookResponses` throws the hook's
output vars away, so the path lists are never refreshed.
`TemplatingStep.willRunTemplating()` reads those stale empty lists and skips
templating.

The fix gives `TemplatingStep` its own fetch link that runs **after** the
pre-hooks, so the two steps stop depending on each other's leftovers.
