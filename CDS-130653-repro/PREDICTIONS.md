# CDS-130653 — predicted BEFORE-fix outcomes

Written from reading the code, before any run. Every prediction here is for the
**unfixed** branch with **today's published plugin images** unless a row says otherwise.
Record your actual result next to each one.

## The single most important caveat

**A plain "gate reads the wrong list" repro does NOT fire on this branch.** The old
`RenderingStep.saveRenderingStepOutput` unioned declared ∪ fetched into *all three*
keys, so as long as the fetch plugin returned **any** path, `toTemplate` was non-empty
and the gate opened. If you only ever test with a values file that exists in git, the
bug is invisible.

The bug becomes visible exactly when the fetch returns nothing, or returns something of
the wrong role. That is what these cases are built around.

## Where the four defects actually show up

| defect | mechanism | shows up in |
|--------|-----------|-------------|
| 1. union instead of filter | `mergePathsWithManifestOutput` unions and never removes; the real intersection helper `filterPathsByFetchOutput` had **zero callers** | 12, 13 |
| 2. gate reads one list, payload uses another | all six `templates/templating/*.yaml` feed their plugin from `manifests.overrides`, while `willRunTemplating` gated on `toTemplate` | 12, 13, 19 |
| 3. the list is stale | pre-template hooks run inside TemplatingStep link 1, i.e. **after** the only fetch, and `handleHookResponses` discards hook output vars | **14**, 15 |
| 4. flat plugin output | one map, key = path, value = content — the values-vs-manifest split the plugin's own loops already knew was thrown away | 9, 11, 12, 13 |

## Case-by-case

| # | before-fix prediction | how you confirm it | after-fix |
|---|----------------------|--------------------|-----------|
| 1 | **PASS.** union kept `toTemplate` non-empty | proof=TEMPLATING-RAN, replicas=7 | PASS |
| 2 | **PASS.** same | same | PASS |
| 3 | **PASS.** openshift is in `MANIFEST_TYPES_ALWAYS_TEMPLATE`, gate bypassed | params substituted | PASS |
| 4 | **PASS.** kustomize also always-template | replicas=7 from the patch | PASS |
| 5 | **PASS.** serverless also always-template | service/region/stage set | PASS |
| 6 | n/a — no `templates/templating/google-cloud-run.yaml` exists, templating never runs for this type either way | — | unchanged |
| 7 | **PASS trivially.** no extra step exists to be unregistered | baseline Initialize log | PASS **and** the new step id appears in the Initialize container/port table |
| 8 | **PASS.** | | PASS, `templating-fetch-files` tab present on a non-K8s runtime too |
| 9 | **PASS.** fetch auto-discovers `templates/values.yaml`, union writes it into all three keys | proof=DISCOVERED-VALUES | PASS; with a rebuilt image the fetch log now carries `HARNESS_FILES_TO_TEMPLATE=<abs path>` and the lists are **replaced**, not unioned |
| 10 | **FAIL at Dry Run — and that is correct.** nothing to template, `isEmpty(filePaths)` → empty map → gate closes → raw `{{ }}` rejected by kubectl | Dry Run error text; step 1 shows all three lists empty | FAIL identically, but the deploy log now states the skip reason |
| 11 | **PASS, by luck.** chart `values.yaml` and the declared file land in one list with no defined precedence; if discovery order changes, `CHART-DEFAULT` starts winning silently | proof must be TEMPLATING-RAN, **not** CHART-DEFAULT | PASS deliberately — order is the plugin's, published explicitly |
| 12 | **LEAK. stage may still be GREEN.** `templates.yaml` (a manifest) is unioned into `overrides`, and `templating/openshift.yaml` feeds `overrides` → `PLUGIN_PARAMS_PATH`. `oc-template` gets the manifest as a params file | step 1's leak check prints `LEAKED` | clean: `templates.yaml` in `toRender` only; `overrides` = `params.yaml` alone |
| 13 | **LEAK.** `harness-rendering` returns `serverlessUnified.yaml` because it contains an expression — as a manifest — and `templating/serverless.yaml` feeds `overrides` → `PLUGIN_VALUES_PATH` | step 1's leak check prints `LEAKED`; `manifest-no-expression.yaml` must be absent from all three lists | clean |
| **14** | **FAIL. the headline.** fetch runs before the pre-hook → returns nothing → empty map → pre-hook creates `values.yaml` → hook output vars discarded → gate reads stale empty `toTemplate` → templating skipped → raw go-template → Dry Run fails | step 1 prints all three lists `empty` **even though the file exists on disk by templating time** | **PASS.** new fetch runs after the pre-hooks, finds the file, `applyFetchOutput` fills the lists, gate opens. proof=HOOK-CREATED-VALUES / 11 / nginx:1.27 / 8443 |
| 15 | **FAIL** at Dry Run, same cause as 14 (`values: []`). Exactly **three** log tabs: `createValuesFile → manifest-templating (skipped) → afterTemplating`. The post-hook still runs and its stamp check still passes | count the log tabs | **PASS** with **four** tabs: `createValuesFile → templating-fetch-files → manifest-templating → afterTemplating` |
| 16 | **FAIL.** declared path is in `overrides` from service resolution; the hook deletes the file; templating plugin gets a nonexistent path | Dry Run / templating error | **STILL FAILS.** known limitation — the new fetch also errors (path is declared, not optional), `saveTemplatingFetchOutput` swallows it by design, templating runs on the stale list and fails the same way. Needs an optional-path flag the unified `K8sManifest` bean does not expose |
| 17 | not reachable from pipeline YAML — both fetches load the same render template | unit test: `saveTemplatingFetchOutput` catches `Exception` around its whole body while `handleTemplatingResponse` throws `InvalidRequestException` | a templating-fetch failure degrades to the old behaviour instead of failing the deploy |
| 18 | **FAIL at the Rendering step.** force it with a nonexistent image tag in `templates/render/k8s-rendering.yaml` | stage fails before templating is decided | unchanged — a *rendering* fetch failure is still fatal, deliberately |
| 19 | **FAIL at Dry Run.** the interesting part is the log: an absent key resolves to the literal 4-char string `null`, and `isEmpty("null")` is **false**, so the old gate could open templating with nothing to template | step 1 prints `len=4` and the text `null` | FAIL at Dry Run, but `isResolvedNonEmpty` now rejects both the literal `null` and a resolved-to-itself expression |
| 20 | new manager + **old** image → **PASS.** `hasPublishedClassification` false → fall back to `mergeFetchedPathsIntoManifests`, the old union | run cases 1 and 9 before rebuilding any image | this is the backward-compat guarantee that lets the manager ship first |
| 21 | **old** manager + new image → **BREAKS.** the old manager reads `getOutputVars().keySet()` as paths, so `HARNESS_FILES_TO_TEMPLATE` itself becomes a "file path" | only run this to confirm the hazard | **deploy order is manager first, images second** |

## Score if the fix is correct

- flips FAIL → PASS: **14, 15**
- flips leak → clean, status unchanged: **12, 13**
- stays PASS (regression guards): **1, 2, 3, 4, 5, 7, 8, 9, 11, 20**
- stays FAIL, correctly: **10, 19** (nothing to template) and **16** (known limitation)
- not pipeline-testable: **6, 17, 18**
