# CDS-130653 repro kit

> Stage code should be more robust, independent of swimlane, by adding fetch in the
> templating step too so both steps are now independent, and the fetch plugin owner
> decides what to publish for rendering or templating.

Run everything here **before** applying the fix, record what you see, then apply the
fix and run it again. `PREDICTIONS.md` has the before-fix call for every case, made
from reading the code and committed before any run.

```
fixtures/    manifests + values files. Commit these to a git repo your connector can read.
services/    10 unified service YAMLs. Paste into the service YAML editor.
pipelines/   16 pipeline YAMLs, one per runnable case.
PREDICTIONS.md
```

---

## 1. Setup, once

1. Push this whole `CDS-130653-repro/` folder to a git repo your Harness git connector
   can read. All fixture paths in the service YAMLs are relative to that repo root.
2. Create 10 services by pasting `services/*.yaml` into the unified service YAML editor.
   Replace `<YOUR_GIT_CONNECTOR>`, `<YOUR_BRANCH>`, `<YOUR_REPO>`.
3. Create one environment + one k8s infrastructure. Case 8 additionally needs a Docker
   stage runtime (delegate with Docker, or a local runner).
4. For each pipeline, replace `<YOUR_SERVICE_ID>`, `<YOUR_ENV_ID>`, `<YOUR_INFRA_ID>`,
   `<YOUR_NAMESPACE>`, `<YOUR_K8S_CONNECTOR>`. The comment next to `service:` names
   which service YAML that pipeline expects.

### Every pipeline has the same three steps

| step | why |
|------|-----|
| `evidence` | prints `manifests.overrides` / `toTemplate` / `toRender` as env vars. These resolve at **service-resolution** time, so step 1 already sees exactly what the templating gate will see. |
| `Dry Run` | **load-bearing.** The implicit Rendering/Templating steps hang off a step that consumes `runtime.manifestPath`. No such step, no rendering at all. |
| `assert` | reads the rendered manifest and checks the proof values. **Must come after Dry Run.** |

Cases 10, 16 and 19 have no `assert` step on purpose — those stages are *supposed* to
fail, and the Dry Run error text is the result.

Never write a literal Harness expression token inside a `run` script body. Harness
resolves it before `sh` ever sees the file. The `blank()` helper in step 1 matches on
the inner path only, for that reason.

---

## 2. Do I need to rebuild plugin images?

**For 11 of the 16 cases: no.** The gate fix, the four-link chain, the hook path
remap and the new templating fetch are all Java. They are observable with the plugin
images that are published today.

You only need a rebuilt fetch image for the cases that depend on the plugin
*publishing* `HARNESS_FILES_TO_TEMPLATE` / `HARNESS_FILES_TO_RENDER` — cases 9, 11, 12,
13, and the rollout matrix (20/21). Everything else, including the headline case 14,
runs on today's images.

### There is no "push the image to a local directory"

The fetch plugin runs as a **container inside the build pod**. A folder on your laptop
is never visible to that pod. Two options only:

**Option A — registry (what you want for a K8s stage runtime).**

```bash
cd ~/projects/manifestPlugin/kubernetes && sh scripts/build.sh   # cross-compiles to release/linux/amd64/plugin

# NOTE: the docker build context is the manifestPlugin REPO ROOT, not the module dir
cd ~/projects/manifestPlugin
docker build --platform linux/amd64 \
  -f kubernetes/docker/Dockerfile.linux.amd64 \
  -t <your-registry>/kubernetes-manifest:cds130653 .
docker push <your-registry>/kubernetes-manifest:cds130653
```

**Option B — Docker / VM stage runtime.** Build locally, skip the push, and set the
stage's `pull:` to something other than `always` so the local daemon's image cache is
used. This is the fast loop, and it is why case 8 exists.

### Then point ci-manager at the new tag

The image names are **hardcoded** in ci-manager's resources. There is no config
override.

```
332-ci-manager/service/src/main/resources/templates/render/*.yaml       <- fetch/render images
332-ci-manager/service/src/main/resources/templates/templating/*.yaml   <- templating images
```

Fetch/render images my Go changes affect:

| template | image |
|----------|-------|
| k8s-rendering.yaml | `harnessdev/kubernetes-manifest:0.0.1` |
| helm-rendering.yaml | `harnessdev/helm-manifest:0.0.1` |
| kustomize-rendering.yaml | `harnessdev/kustomize-manifest:0.0.1` |
| openshift-rendering.yaml | `harnessdev/openshift-manifest:0.0.1` |
| aws-lambda / aws-sam / google-cloud-run / serverless / spot rendering | `harnessdev/harness-rendering:0.0.1` |

The `*-template` images used by `templates/templating/*.yaml` (`k8s-template`,
`helm-template`, `oc-template`, `kustomize-template`, `serverless-template`) live in a
**different repo** and are untouched by these changes.

Edit the tag in the render yaml, then:

```bash
cd ~/projects/harness-core
make build t=332-ci-manager
make run   t=332-ci-manager     # or restart however you run it locally
```

### Only ci-manager needs a restart

Verified from `BUILD.bazel` reverse dependencies: `332-ci-manager/service` is the only
service that depends on `877-pipeline-ci-cd-commons`, and `880-pipeline-cd-commons`
reaches runtime only through 877. `120-ng-manager`, `125-cd-nextgen` and
`pipeline-service` do **not** depend on either, so they do not need a rebuild.

### Rollout order matters

**Manager first, plugin images second.** An old manager paired with a new plugin image
would read `HARNESS_FILES_TO_TEMPLATE` as if it were a file path — that is case 21.

---

## 3. Case index

`img?` = does this case need a rebuilt fetch image.

### Group A — one happy path per swimlane. Controls, not repros.

| # | pipeline | service | img? | before | after |
|---|----------|---------|------|--------|-------|
| 1 | `case01-k8s-declared` | 01 | no | PASS | PASS |
| 2 | `case02-helm-declared` | 07 | no | PASS | PASS |
| 3 | `case03-openshift-params` | 08 | no | PASS | PASS |
| 4 | `case04-kustomize-patches` | 09 | no | PASS | PASS |
| 5 | `case05-serverless-values` | 10 | no | PASS | PASS |
| 6 | *(no pipeline — see below)* | — | — | — | — |

**Case 6, google-cloud-run / generic — documented, not scripted.**
`google-cloud-run-rendering.yaml` passes only `PLUGIN_MANIFEST_PATH`, no overrides, and
there is no `templates/templating/google-cloud-run.yaml` at all, so templating never
runs for this type either before or after the fix. Writing a pipeline would prove
nothing and it needs GCP infra. The equivalent Go change (`generic/plugin`
`AddManifestFile` on `ManifestPaths`) is currently **unreachable through any render
template** — same for the `serverless` and `aws-sam` manifestPlugin modules, since
those swimlanes render through `harness-rendering` instead. Noted so nobody hunts for a
behaviour change that cannot appear yet.

### Group B — stage-runtime independence

| # | pipeline | service | img? | before | after |
|---|----------|---------|------|--------|-------|
| 7 | `case07-k8s-stage-infra` | 01 | no | PASS (trivially) | PASS + new step registered at Initialize |
| 8 | `case08-docker-runtime` | 01 | no | PASS | PASS |

Case 7 is a **regression guard, not a before-fix repro.** On a K8s stage runtime the
pod's containers and ports are fixed at Initialize time; an unregistered step id throws
`Step [harnessTemplatingFetchFiles] should map to single port`. Before the fix there is
no new step, so nothing can throw. Case 7 only has teeth *after* the fix.

### Group C — what the fetch plugin publishes

| # | pipeline | service | img? | before | after |
|---|----------|---------|------|--------|-------|
| 9 | `case09-k8s-discovered-values` | 02 | optional | PASS | PASS, now via published keys |
| 10 | `case10-k8s-no-values` | 03 | no | FAIL (correct) | FAIL (correct), clearer log |
| 11 | `case11-helm-chart-default-vs-declared` | 07 | optional | PASS by luck | PASS deliberately |
| 12 | `case12-openshift-manifest-leak` | 08 | yes | **leak visible, run may still be green** | clean |
| 13 | `case13-serverless-manifest-leak` | 10 | yes | **leak visible** | clean |

Cases 12 and 13 are real defects that do **not** necessarily turn the pipeline red —
which is exactly why they survived. Read step 1's leak check, not the stage status.

### Group D — hooks. The heart of the ticket.

| # | pipeline | service | img? | before | after |
|---|----------|---------|------|--------|-------|
| 14 | `case14-prehook-creates-values` | 04 | no | **FAIL** | **PASS** |
| 15 | `case15-pre-and-post-hook-order` | 05 | no | FAIL, 3 log tabs | PASS, 4 log tabs in order |
| 16 | `case16-prehook-deletes-values` | 06 | no | FAIL | FAIL — known limitation |

**Case 14 is the one to run first.** It is the whole bug in a single execution and it
needs no image rebuild.

Case 16 fails before *and* after. The k8s fetch plugin errors on a declared-but-missing
values path (`shouldSkipOptionalValuesPath` is false unless the path was declared
optional), `saveTemplatingFetchOutput` swallows that by design, and templating then
runs on the stale list and fails identically. A real fix needs the path marked
optional, which the unified `K8sManifest` bean does not expose. Out of scope — recorded
here so it is not filed as a regression.

### Group E — gate semantics and failure handling

| # | pipeline | service | img? | before | after |
|---|----------|---------|------|--------|-------|
| 19 | `case19-null-gate` | 03 | no | FAIL, literal `null` classified as a value | FAIL, clean skip decision |

**Case 17, "a templating-fetch failure must not fail the deploy" — not reachable from
pipeline YAML.** Both fetches load the *same* render template, so a bad image tag or a
missing file breaks the Rendering fetch too; there is no YAML lever that fails only the
second fetch. It is covered by unit test instead — `saveTemplatingFetchOutput` catches
`Exception` around its whole body, while `handleTemplatingResponse` throws
`InvalidRequestException` on task failure. Verify by reading
`TemplatingStepTest` and by grepping the log for the degrade message on any run where
the fetch container logs an error.

**Case 18, Rendering-fetch failure.** Force it by pointing the image in
`templates/render/k8s-rendering.yaml` at a nonexistent tag and rerunning case 1. Both
fetches then fail; expect the stage to fail at the Rendering step, before templating is
ever decided.

### Group F — rollout matrix. Same pipeline, different pairing.

Not separate YAMLs. Run **case 1 and case 9** against each combination:

| # | manager | plugin image | expected |
|---|---------|--------------|----------|
| 20 | new (fixed) | **old** (published) | PASS. `hasPublishedClassification` is false, so `applyFetchOutput` falls back to `mergeFetchedPathsIntoManifests` — the old union. This is the backward-compat guarantee. |
| 21 | **old** (unpatched) | new (rebuilt) | **BREAKS.** The old manager reads `response.getOutputVars().keySet()` as file paths, so `HARNESS_FILES_TO_TEMPLATE` itself becomes a "path". Do not ship in this order. |

Case 20 is the important one: it is what lets the manager ship first.

---

## 4. Suggested run order

1. **case 1** — proves your setup works. If this fails, fix the harness, not the code.
2. **case 14** — the headline bug. Before-fix FAIL / after-fix PASS is the deliverable.
3. **case 15** — chain order. Four log tabs.
4. **cases 10, 16, 19** — the three that are meant to fail. Confirm they fail for the
   documented reason, not a new one.
5. **cases 7, 8** — runtime independence. Both must pass after the fix.
6. **cases 2–5** — swimlane regression sweep.
7. rebuild the fetch images, then **cases 9, 11, 12, 13**.
8. **case 20** — new manager, old image. Must still pass.
