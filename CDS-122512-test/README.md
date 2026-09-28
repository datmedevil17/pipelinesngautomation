# CDS-122512 test kit -- Unified: Steady state hook support (Helm + K8s)

## The bug

The Unified pipeline model's service schema already accepts
`hooks[].actions: [SteadyStateCheck]` (`ServiceHookAction.STEADY_STATE_CHECK`
exists and parses fine), but nothing ever executes those hooks:

- `UnifiedServiceStep.handleServiceHooksPart` branches on
  `ServiceHookAction.FETCH_FILES` / `.TEMPLATE_MANIFEST` and falls through to
  `Collections.emptyMap()` for `STEADY_STATE_CHECK` -- the hook scripts are
  parsed out of the service YAML and then silently dropped.
- No plan-creation node IDs exist for steady-state pre/post hooks
  (`PlanCreatorNodesConstants` only has `PRE_FETCH_FILES_HOOKS_NODE_ID` /
  `POST_FETCH_FILES_HOOKS_NODE_ID` / `PRE_TEMPLATE_HOOKS_NODE_ID` /
  `POST_TEMPLATE_HOOKS_NODE_ID`).
- No env-var injection exists to hand the hook scripts to the Go plugin
  binaries that actually run the poll (`kubernetes-plugin`'s
  `k8s-steady-check`, and `helm-plugin`'s embedded poll inside
  `helmDeployAction`).

Net effect: you can configure a `PreHook`/`PostHook` with
`actions: [SteadyStateCheck]` in a service YAML today, and the deploy will
just succeed (or fail, for unrelated reasons) as if the hook were never
declared. That's the "BEFORE" behavior every case below documents.

## Layout

```
helm/chart/            minimal chart, used by all Helm service fixtures
k8s/templates/         plain manifest, used by most K8s service fixtures
k8s-slow/templates/    same manifest but with a 60s-delayed readiness probe,
                       used only by the long-running-timing case
services/              13 unified service YAMLs (01-07,13 = k8s, 08-12 = helm)
pipelines/             5 pipeline YAMLs, one file per scenario group
```

Push this whole `CDS-122512-test/` folder to a git repo your Harness git
connector can read -- the service YAMLs' manifest `paths:` are relative to
that repo root (`CDS-122512-test/k8s`, `CDS-122512-test/helm/chart`, etc).

## Setup, once

1. Push this folder to your git repo.
2. Create 13 services from `services/*.yaml`. Replace
   `<YOUR_GIT_CONNECTOR>` / `<YOUR_BRANCH>` / `<YOUR_REPO>` in each.
3. Create one environment + one K8s infrastructure your delegate can reach.
4. In each pipeline under `pipelines/`, replace `<YOUR_SERVICE_ID_NN>` /
   `<YOUR_ENV_ID>` / `<YOUR_INFRA_ID>` / `<YOUR_NAMESPACE>` /
   `<YOUR_K8S_CONNECTOR>` with real IDs.

All hook stamp/counter files are written to `/harness/...`, the shared
workspace emptyDir mounted across every step and plugin container in a K8s
stage runtime pod. That's what makes the `assert` steps able to read what a
hook script (running inside the deploy/steady-check plugin container) wrote.

## Do I need to rebuild plugin images?

**Yes, for every AFTER-fix run.** Unlike the CDS-130653 FetchFiles/
TemplateManifest hooks (pure Java, observable on stock images), SteadyStateCheck
hooks need the fix built into:
- `kubernetes-plugin`'s `k8s-steady-check` binary (K8s cases)
- `helm-plugin`'s deploy binary (Helm cases, since the poll is embedded in
  `helmDeployAction`, not a separate step)

Push the built multi-arch image (see `[[multiarch-plugin-image-builds]]`
memory for the buildx recipe -- native arm64 build, sed the `RUN <tool>
version` verify lines for the amd64 cross-build, `docker buildx imagetools
create` to merge, not `docker manifest create`) to e.g.
`harnessdev/temp:cds122512-k8s-plugin` / `harnessdev/temp:cds122512-helm-plugin`.

Then point ci-manager at the new tags. Like the CDS-130653 kit found, image
names are **hardcoded**, no config override:
```
332-ci-manager/service/src/main/resources/templates/render/*.yaml
332-ci-manager/service/src/main/resources/templates/templating/*.yaml
```
Find the k8s-steady-check / helm deploy step's template yaml under one of
those trees and swap its `image:` to your new tag, then rebuild + restart
`332-ci-manager` only (same reverse-dependency logic as CDS-130653: only
`332-ci-manager/service` depends on `877-pipeline-ci-cd-commons`).

**Rollout order matters** -- manager (Java) first, plugin image second, same
reasoning as CDS-130653: an old manager paired with a hook-aware new plugin
image is undefined; ship the side that reads unknown env vars gracefully
before the side that starts sending them, or just do both together in a test
environment.

## Case index

| # | pipeline | stage id | service | before | after |
|---|----------|----------|---------|--------|-------|
| 1 | pipeline-cds122512-k8s | happyPath | 01 | PASS, no stamps | PASS, both stamps, pre<=post |
| 2 | pipeline-cds122512-k8s | prehookFails | 02 | PASS (bug) | FAIL at deploy, no post-after-prefail stamp |
| 3 | pipeline-cds122512-k8s | posthookFails | 03 | PASS (bug) | preok stamp exists, deploy step FAILED |
| 4 | pipeline-cds122512-k8s | multiHookOrder | 04 | PASS, no stamps | hook1+hook2 stamps exist, hook3 does not |
| 5 | pipeline-cds122512-k8s | noHooksRegression | 05 | PASS | PASS (unchanged) |
| 6 | pipeline-cds122512-k8s | longRunningTiming | 07 | no stamps | both stamps, post-pre >= ~45s |
| 7 | pipeline-cds122512-k8s-rollback | hooksPlusRollback | 06 | 0/0 lines both counters | 1/1 lines both counters, unchanged after rollback |
| 8 | pipeline-cds122512-helm | happyPath | 08 | PASS, no stamps | PASS, both stamps, pre<=post |
| 9 | pipeline-cds122512-helm | prehookFails | 09 | PASS (bug) | FAIL at deploy, no post-after-prefail stamp |
| 10 | pipeline-cds122512-helm | posthookFails | 10 | PASS (bug) | preok stamp exists, deploy step FAILED |
| 11 | pipeline-cds122512-helm | multiHookOrder | 11 | PASS, no stamps | hook1+hook2 stamps exist, hook3 does not |
| 12 | pipeline-cds122512-helm | noHooksRegression | 12 | PASS | PASS (unchanged) |
| 13 | pipeline-cds122512-mixed-hooks-regression | mixedHookPhases | 13 | fetch+template stamps only | all 4 stamps (fetch, template, steady-pre, steady-post) |
| 14 | pipeline-cds122512-image-digest-check | imageCheckK8s / imageCheckHelm | 01 / 08 | n/a (documentation aid) | confirms new plugin image actually pulled |

That's the 14 scenarios from the earlier bullet list: 6 K8s core behaviors,
1 K8s rollback-isolation, 5 Helm mirrors, 1 mixed-phase regression, 1
image-provenance check.

## Suggested run order

1. **Case 1** (k8s happyPath) and **case 8** (helm happyPath) first -- if
   these don't show stamp files after the fix, nothing else will either.
2. **Case 13** (mixed phases) right after -- highest risk of a dispatch
   regression breaking the already-shipped FetchFiles/TemplateManifest hooks.
3. **Cases 2, 3, 9, 10** -- failure semantics (pre-stops-chain, post-fails-step).
4. **Cases 4, 11** -- multi-hook ordering + stop-on-first-failure.
5. **Case 6** -- timing, needs the k8s-slow fixture and takes longer to run
   (60s+ readiness delay).
6. **Case 7** -- rollback isolation, run last since it needs an established
   release from case 1's happy-path deploy in the same service/env/infra.
7. **Case 14** -- image provenance, run any time as a sanity check; it's a
   best-effort RBAC-dependent check, not a hard pass/fail gate.

## Notes / deviations from the CDS-130653/CDS-130615 reference conventions

- These pipelines use **real deploy steps** (`k8sRollingDeployStep`,
  `helmBasicDeployStep`, `k8sRollingRollbackStep`), not `k8sDryRunStep`.
  SteadyStateCheck hooks only fire around the actual steady-state poll, which
  a dry run never performs -- so unlike the FetchFiles/TemplateManifest kits,
  there's no dry-run-based fixture here.
- Verification is stamp/counter files under `/harness`, written by the hook
  scripts themselves, read by a trailing `assert` step -- same pattern as
  CDS-130653's stamp files, adapted since there's no rendered-manifest text
  to grep for a SteadyStateCheck hook (there's nothing in the manifest that
  a steady-state hook would change).
- Cases 3 and 10 (PostHook fails) intentionally have no trailing `assert`
  step: a FAILED deploy step may skip subsequent steps depending on the
  stage's failure strategy, so verification there is "check the `deploy`
  step's own status is FAILED" plus inspecting `/harness/*.stamp` via a
  separate ad-hoc run if you need the raw file.
- Case 14 (image digest check) is flagged as best-effort in its own file
  comment -- it needs in-namespace `get pods` RBAC for the step's service
  account, which isn't guaranteed. Falling back to reading the deploy step's
  own log header (which prints the image it pulled) is the documented
  alternative, matching how the CDS-130653 kit handles its own infeasible
  cases (6, 17) by documenting rather than forcing a script.
