# CDS-126515-test — optional values-YAML files must not fail a deploy

## The question

CDS-126515 adds an `optionalValuesYaml` flag to a manifest source. If that
manifest's declared values file is missing on fetch, the deploy should
**skip** the file and continue -- not fail. A values file with no such flag
(the default) must keep failing the deploy when missing, exactly as before.

This kit proves both halves in one service, using one manifest that is
required and one that is optional.

## Layout

    CDS-126515-test/
      k8s/
        deployment.yaml         <- the manifest under test
        (deliberately NO values.yaml here -- avoid auto-discovery masking the test)
      k8sValues/
        values-required.yaml    <- declared on the REQUIRED manifest, always present
        (values-optional.yaml deliberately DOES NOT EXIST -- that is the point)
      pipeline-cds126515.yaml
      README.md

`values-optional.yaml` is never committed to this repo. The `values_optional`
manifest below declares it anyway with `optionalValuesYaml: true`, so every
run of this fixture exercises the "declared but missing, and that's fine"
path by construction.

## Service configuration

Create a **classic Kubernetes service** (the unified v1 stage still reads
this shape) with **two manifest entries**:

```yaml
service:
  name: svc-cds126515-k8s-optional
  identifier: svc_cds126515_k8s_optional
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
                    - CDS-126515-test/k8s
              valuesPaths:
                - CDS-126515-test/k8sValues/values-required.yaml
              skipResourceVersioning: false
        - manifest:
            identifier: values_optional
            type: Values
            spec:
              store:
                type: Github
                spec:
                  connectorRef: account.cdautomationtest
                  gitFetchType: Branch
                  branch: main
              valuesPaths:
                - CDS-126515-test/k8sValues/values-optional.yaml
              optionalValuesYaml: true
```

Swap `connectorRef` for whatever GitHub connector you actually have pointed
at `datmedevil17/test-test` if it isn't `account.cdautomationtest`.

The `k8s` manifest has **no** `optionalValuesYaml` key -- default is falsy,
so its declared file stays required. The `values_optional` manifest is the
only one flagged optional. This mirrors the Java logic
(`isOptionalValuesYaml(inputs)` in `ManifestTemplatesPathsUtils`), which
applies the flag to **all** of a manifest's `valuesPaths` at once, not
per-file -- hence two manifests instead of one manifest with a mixed list.

## How to run

1. This repo is already pushed (`datmedevil17/test-test`, branch `main`) --
   the pipeline fetches from git, not your working copy, so re-push after any
   edit here.
2. Create the service above (swap the connector if needed).
3. Paste `pipeline-cds126515.yaml`, replace every `<YOUR_...>` placeholder
   (env id, infra id, service id if you named it differently).
4. Run.

## What each step is for

| # | step | role |
|---|---|---|
| 1 | `CDS-126515 signal evidence` | Prints `overrides` and `optionalOverrides`. Confirms Java tagged the right path as optional. Always runs. |
| 2 | `Dry Run` | **Expected to PASS.** This is the actual fix under test -- a missing optional file must not fail the render/apply chain. |
| 3 | `CDS-126515 rendered manifest` | Asserts the required fields rendered from `values-required.yaml`, and that the optional field is cleanly unsupplied (not a failure, just absent). |

## Expected results

### After the fix (target state)

    step 1: overrides         : .../k8sValues/values-required.yaml,.../k8sValues/values-optional.yaml
            optionalOverrides : .../k8sValues/values-optional.yaml
    step 2: PASS -- missing optional file was skipped, not fatal
    step 3: PASS  appName       cds126515-k8s-required
            PASS  replicas      2
            PASS  image         nginx:1.25
            PASS  containerPort 8080
            PASS  optional-feature-flag is unsupplied (<no value>), as expected

### Before the fix (or if the flag isn't wired through)

    step 2: FAILS -- the plugin tries to pass a nonexistent file to
            kubectl/helm's -f/-f equivalent and the whole deploy dies on a
            "no such file" error, even though only the OPTIONAL manifest's
            file was missing.

## Regression guard -- prove the flag is per-manifest, not global

To confirm `optionalValuesYaml: true` on `values_optional` does **not**
accidentally make the `k8s` manifest's required file optional too:

1. Temporarily point the `k8s` manifest's `valuesPaths` at a path that does
   not exist (e.g. `CDS-126515-test/k8sValues/does-not-exist.yaml`), leaving
   `optionalValuesYaml` unset on that manifest.
2. Re-run. Step 2 (`Dry Run`) must **FAIL** -- a missing file on a
   non-optional manifest still breaks the deploy.
3. Revert the path back to `values-required.yaml` before moving on.

If step 2 instead PASSES with a missing required file, the skip logic is
leaking across manifests and the fix is too broad.

## To test with the optional file actually present

Add `k8sValues/values-optional.yaml` to this folder (e.g.
`featureFlag: enabled-via-optional-values`), commit, push, and re-run. Step 3
should then show `optional-feature-flag: enabled-via-optional-values` instead
of `<no value>` -- proving the optional file is still applied normally when
it *does* exist, and `optionalValuesYaml` only changes behavior on the
missing-file path.
