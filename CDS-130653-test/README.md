# CDS-130653-test — the templating gate reads a list it can never see

## The question

`TemplatingStep` decides whether to run at all by looking at
`serviceOutput.manifests.toTemplate`. But every templating plugin template
feeds the plugin `serviceOutput.manifests.overrides`.

> If those two lists can disagree, the step either skips work it should do, or
> runs a container that has nothing to work on.

This kit proves they **always** disagree for a unified `k8s` service.

## Why they disagree (source-level, not a guess)

`ServiceEntityProcessor` fills both keys from the same `inputs` map, but by
different rules:

| output key | filled from |
|---|---|
| `manifests.overrides` | the **first** of `overrides`, `values`, `params`, `valuesPaths`, `paramsPaths`, `patchesPaths`, `filePath` |
| `manifests.toTemplate` | **exactly one** key, chosen by manifest type — for `k8s` that is only `valuesPaths` |

`ManifestTemplatesPathsUtils.getInputsKeyForFilesToTemplateOrRender()` never
returns the short form `values` — only `valuesPaths`. And the unified bean
`K8sManifest.java:45` has a `values` field and **no `valuesPaths` field at
all**.

So in a unified service you can only spell it `values:` → `overrides` gets the
file, `toTemplate` stays empty → the gate is false → templating is skipped even
though a real override file was declared.

Both writes are guarded by `isNotEmpty`, so an empty list means the key is
**absent**, not present-and-empty. That is why the expression resolves to
nothing rather than to `[]`.

## Why nobody noticed

`TemplatingStep.java:81`

    MANIFEST_TYPES_ALWAYS_TEMPLATE = { serverless, aws-sam, kustomize, openshift }

Those four bypass the gate entirely. `helm` returns early on service type. So
**`k8s` is effectively the only swimlane that reaches this gate** — and it is
the one where `toTemplate` can never be populated.

Note the variable inside `willRunTemplating()` is even named `overridesFiles`
while it holds the `toTemplate` value. The names were already confused.

## Layout

    CDS-130653-test/
      k8s/
        templates/
          deployment.yaml          <- the manifest under test, fully templated
        (deliberately NO values.yaml here)
      k8sValues/
        values-declared.yaml       <- the DECLARED override file
      pipeline-cds130653.yaml

### The deliberate omission

There is **no `values.yaml` inside `k8s/`**. `k8s-template` auto-discovers that
filename off disk, which would supply the values even when the declared file
never arrives — masking exactly the skip we want to observe. If you add one,
this kit stops proving anything.

Every key in `deployment.yaml` (`proof`, `replicaCount`, `image`, `port`) is
supplied **only** by `k8sValues/values-declared.yaml`. No key has another
source.

## Service config

Create a **unified** Kubernetes service pointing at this repo:

    manifest:
      uses: k8s
      inputs:
        paths:
          - CDS-130653-test/k8s
        values:
          - CDS-130653-test/k8sValues/values-declared.yaml

Use `values:` — that is the only spelling the unified bean accepts, and it is
the spelling that triggers the bug. If you instead hand-write the legacy
`valuesPaths:` key, both lists get populated and **the bug hides**. That is
also why the older `noBaitTest` kit never hit this: it used `valuesPaths`.

## How to run

1. **Commit and push** `CDS-130653-test/`. The pipeline fetches from git, not
   from your working copy.
2. Create the service above.
3. Paste `pipeline-cds130653.yaml`, replace every `<YOUR_...>` placeholder.
4. Run. Read **step 1** first, whatever else happens.

## What each step is for

| # | step | role |
|---|---|---|
| 1 | `CDS-130653 gate evidence` | **The repro.** Prints `overrides` and `toTemplate` and names the verdict. Always runs. No cluster reasoning needed. |
| 2 | `Dry Run` | LOAD-BEARING — the injected Rendering/Templating steps hang off a step consuming `runtime.manifestPath`. **Expected to FAIL before the fix.** |
| 3 | `CDS-130653 rendered manifest` | Asserts the declared values actually landed. Only reachable once step 2 passes. |

Do not delete or reorder step 2. Without it the implicit steps are never
injected and step 1 prints nothing useful.

## Expected results

### Before the fix

    step 1: overrides    : /harness/CDS-130653-test/k8sValues/values-declared.yaml
            toTemplate   : (empty)
            BUG PRESENT -- wrongly SKIPS
    step 2: FAILS -- replicas is still "{{ .Values.replicaCount }}", not an int
    step 3: not reached

**Step 2's failure is the repro, not a broken fixture.** Raw go-template left
in the manifest is the visible consequence of the skipped templating step.

### After the fix

    step 1: overrides    : /harness/CDS-130653-test/k8sValues/values-declared.yaml
            toTemplate   : /harness/CDS-130653-test/k8sValues/values-declared.yaml
            gate will pass, payload is non-empty -- consistent
    step 2: PASS
    step 3: PASS  proof            TEMPLATING-RAN
            PASS  replicas         7
            PASS  image            nginx:1.25
            PASS  containerPort    8080

## Reading the outcome

| step 1 verdict | step 2 | means |
|---|---|---|
| BUG PRESENT — wrongly SKIPS | FAIL | The bug, unfixed. Gate read `toTemplate`, payload wanted `overrides`. |
| BUG PRESENT — wrongly RUNS | FAIL or empty-op | Reverse case: gate passed, `PLUGIN_VALUES_PATH` resolved to nothing. A container ran and did nothing. |
| consistent | PASS | Gate and payload agree. Fixed. |
| consistent | FAIL | Gate is fixed but the plugin still isn't applying the file. Look past the gate — at the plugin's output contract. |
| INCONCLUSIVE | — | Service misconfigured, not the bug. Re-check `paths` and `values`. |
| consistent, step 3 shows `<no value>` | PASS | Templating ran but the declared file never reached the plugin. Gate fixed, payload key still wrong. |

## Scope

This kit tests **the gate only** — which list `willRunTemplating()` reads.

It does **not** test:

- the union-vs-filter defect (`mergePathsWithManifestOutput` unions declared ∪
  fetched and never removes anything; the real intersection helper
  `filterPathsByFetchOutput` has zero callers)
- pre-template hooks producing files after the only fetch has already run
- the fetch plugin's flat output contract (the ticket's actual subject — the
  plugin publishes one path-keyed map and loses the discovered-vs-declared
  distinction it already knows internally)
- expression-driven default-values discovery — that is CDS-131005, and
  `values-declared.yaml` deliberately contains no Harness expression so the two
  do not interfere.
