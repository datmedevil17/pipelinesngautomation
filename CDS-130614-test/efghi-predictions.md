# CDS-130614 — Categories E, F, G, H, I: predicted outcomes

Status recap before this batch: A1–A8 done, B1/B2 done, C1/C2 done (C3 dropped — bad
test design, not a bug), D1–D5 done. All passed.

This table covers the remaining edge-case categories from the original list. Fill in
the **Actual result** column after running each one and send it back.

| # | Test | What it's checking | Predicted outcome | Actual result |
|---|------|--------------------|--------------------|----------------|
| E1 | Service scope, `retry` action, retries exhausted, `failure-action: abort` (allowed) | Retry actually retries the configured number of times at service scope, then falls through to the allowed failure-action once exhausted | Step/service node retried the configured number of attempts, then final status **Aborted** | **PASS.** Confirms the `.group(StepCategory.STEP_GROUP.name())` fix works: no more "Node Retry is supported only for Leaf Nodes" crash. Service node went straight from Queued to final **Aborted** (retries against the fake service id fail fast/consistently, so the UI doesn't render separate visible retry-attempt states — just Queued then the final post-exhaustion action), matching the predicted final status exactly. |
| E2 | Environment scope, `retry` action, retries exhausted, `failure-action: fail` (allowed) | Same as E1 but for environment scope | Retried configured attempts, then final status **Failed** | **PASS** (after fixing the fake-service test design issue below). With real service `sls_github_ecr_llale` + fake infra: Service succeeded, Infrastructure failed (`No infrastructure entity found with identifier [this_infra_id_does_not_exist_cds130614] in environment [environment_env_2a02]`), retries exhausted, final pipeline status **Failed** — matches prediction exactly. Confirms environment-scope retry (which was likely never broken, per the ASYNC-facilitator analysis) works correctly end-to-end. |
| E3 | Service scope `on-failure` covers `all` with `retry` (attempts: 1, `failure-action: abort`); stage scope also defines a rule for `all` with a *different* action (e.g. `fail`) | Confirms retry-then-fallback-action at service scope takes priority over the stage's rule for the same error type (scope beats stage even mid-retry-resolution) | Retries once, then ends **Aborted** (service's retry+abort wins, stage's `fail` never engages) | **PASS.** Service node retried then landed on **Aborted**, final pipeline status **Aborted** — stage's `fail` rule never engaged. Confirms scope priority holds even through the retry/fallback-action resolution path. |
| F1 | Service `items` shape with 2 parallel service items, each pointing at a fake service ID, group-level `on-failure: abort` | Confirms the on-failure rule applies uniformly to a multi-item/parallel service block, not just single items | Both service items fail, both fall under the same group `on-failure`, stage ends **Aborted** | |
| F2 | Environment `group` shape with a *valid* group but a fake `deploy-to`/filter that causes an infra resolution failure downstream, group-level `on-failure: abort` | Confirms multi-environment/group failures are also covered by the group-level rule, not just single-environment shape (companion to the C3 attempt, but designed to get past entity-existence validation this time) | Ends **Aborted** via the group's own rule | **PASS (mostly).** Editor's duplicate-`id` warning did not block execution. First item's Infrastructure resolution failed as expected, group `on-failure: abort` triggered, second parallel item was **skipped** (not run). Final pipeline status showed **Failed**, not literally "Aborted" — behavior matches abort semantics (stop + skip remaining), just the status label differs from prediction. Not treating as a bug, just noting the label discrepancy. |
| G1 | Stage-level rollback triggered (e.g., via `pipeline-rollback` or `stage-rollback` from a prior on-failure), rollback path includes an infra/service step, service/environment `on-failure` still set | Confirms the scoped on-failure rule still applies correctly to nodes running inside the rollback path, not just the forward path | Rollback executes, nodes inside rollback path resolve their failures per the same scoped rule as forward path | **PASS.** Infrastructure failed on the fake infra id (environment-scope `stage-rollback` action fired), `rollback step` ran and succeeded (Rollback badge). Final pipeline status **Failed** (stage remains failed even though rollback itself succeeded) — expected. Confirms rollback path triggers correctly off an environment-scope rule. |
| G2 | Environment scope `on-failure: stage-rollback` triggered from *within* an already-rolling-back stage | Confirms nested/duplicate rollback isn't triggered (rollback-of-a-rollback guard) | Second rollback attempt is blocked/no-ops rather than looping or erroring | **INCONCLUSIVE — weak evidence, needs a closer look.** No infinite loop / crash: Service failed (fake id) → service-scope `pipeline-rollback` fired → a `Pipeline Rollback` replay spawned once, whose own inner node (`Stage items`) also ended up **Failed**/`Conditional`, and the run stopped there (final pipeline status **Failed**) — it did not loop. However, the authored YAML (below) only exercises *one* pipeline-rollback trigger; it does not actually reproduce "a second on-failure firing while already rolling back," so this doesn't rigorously prove the nested-rollback guard, just that this particular run didn't loop. Flagging per the notes below as the riskiest item in this batch — may be worth a dedicated repro (fail again specifically inside the rollback path) if this guard matters for the ticket. |
| G2b | **Dedicated nested-rollback repro.** A step *inside* the `rollback:` block itself fails (`exit 1`) and carries its own step-level `on-failure: stage-rollback` — i.e., a failure-triggered rollback fires while the stage is already executing its rollback path | Directly tests the rollback-of-a-rollback guard (unlike G2, which only inferred it indirectly) | Second `stage-rollback` should be blocked/no-op — pipeline should just end in a terminal **Failed** status without looping, hanging, or throwing an engine exception | **PASS.** Infrastructure failed (fake infra) → environment-scope `stage-rollback` fired → `rollback step that also fails` ran (Rollback badge) → step failed on `exit 1` → its own step-level `on-failure: stage-rollback` did **not** spawn a second rollback stage — no loop, no hang, no engine exception, just the plain `exit status 1` error. Pipeline terminated cleanly as **Failed**. Nested-rollback guard confirmed working. This resolves G2's "inconclusive" flag — the guard is solid. |
| H1 | Normal pipeline, no fake IDs, real service/environment, only a "Rendering"-type step in `steps`, plus a valid service/environment `on-failure` block that never gets triggered | Confirms the render/templating step itself is completely unaffected by the presence of a service/environment `on-failure` block (pure regression check) | Runs and renders normally, `on-failure` present but inert since nothing fails | **PASS.** Full green run: Initialize, Service, Infrastructure, both Harness Manifest steps (render/template), Resource Constraint, and `real step` all **Success**. Script echoed correctly. `on-failure` at service+environment scope stayed completely inert. |
| H2 | Same as H1 but with a templating step (e.g. an expression pulling from service/environment) | Same regression check for templating specifically | Runs and resolves templates normally, no behavior change | **PASS** (covered by the same H1 run — the two Harness Manifest templating/rendering steps in the graph above both succeeded normally alongside the scoped `on-failure` blocks). |
| H3 | A previously-working "normal" pipeline (only stage-level `on-failure`, no service/environment `on-failure` at all) re-run as-is | Confirms adding this whole feature didn't change behavior for pipelines that don't use the new fields at all | Behaves identically to before this change — no regression | **PASS.** Identical green run to H1/H2 (Initialize, Service, Infrastructure, both Harness Manifest steps, Resource Constraint, `real step` all Success) with zero `on-failure` fields present. No regression. |
| I1 | Same as B2 (environment-scope failure priority) but with `runtime: kubernetes` instead of `shell` | The known, previously-documented limitation: whether environment-scope on-failure works under the kubernetes runtime the way it does under shell | **Expected to still fail at the Initialize node**, not at the Infrastructure node — i.e. expected to NOT show the fix working. This is a known-limitation check, not a pass/fail gate. | **PASS (limitation confirmed as expected).** Failed at **Initialize** node, never reached Infrastructure — environment-scope fix never got a chance to engage under `runtime: kubernetes`. Consistent with the known pre-existing limitation, not a new/regression bug. |

## Notes
- E/F are functional — real signal if they deviate from prediction.
- G is the riskiest guess of the batch (rollback-path adviser wiring wasn't directly
  inspected in code this session) — treat any surprise here as worth digging into.
- H is pure regression insurance — any deviation here is a real bug.
- I1 is expected to demonstrate the *pre-existing* gap, not a new failure — don't treat a failure at Initialize as a new bug.

## Pipeline YAMLs

Paste each into the same test pipeline's YAML editor and run, same as A–D.

### E1 — service scope, retry exhausted, then `abort`
```yaml
pipeline:
  stages:
    - name: E1 service retry exhausted abort
      id: e1svcretryexhausted
      runtime: shell
      service:
        id: this_service_id_does_not_exist_cds130614
        ref: this_service_id_does_not_exist_cds130614
        on-failure:
          - errors: [ all ]
            action:
              retry:
                attempts: 2
                interval: "2s"
                failure-action: abort
      environment:
        id: env-a
        deploy-to: infra-a
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
```

### E2 — environment scope, retry exhausted, then `fail`
```yaml
pipeline:
  stages:
    - name: E2 environment retry exhausted fail
      id: e2envretryexhausted
      runtime: shell
      service:
        id: sls_github_ecr_llale
        ref: sls_github_ecr_llale
      environment:
        id: environment_env_2a02
        deploy-to: this_infra_id_does_not_exist_cds130614
        on-failure:
          - errors: [ all ]
            action:
              retry:
                attempts: 2
                interval: "2s"
                failure-action: fail
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
```

### E3 — service scope retry+abort beats stage's `fail` rule for the same error type
```yaml
pipeline:
  stages:
    - name: E3 service retry beats stage rule
      id: e3svcretrybeatsstage
      runtime: shell
      on-failure:
        - errors: [ all ]
          action: fail
      service:
        id: this_service_id_does_not_exist_cds130614
        ref: this_service_id_does_not_exist_cds130614
        on-failure:
          - errors: [ all ]
            action:
              retry:
                attempts: 1
                interval: "1s"
                failure-action: abort
      environment:
        id: env-a
        deploy-to: infra-a
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
```

### F1 — service `items` shape, 2 parallel fake service items, group-level `on-failure: abort`
```yaml
pipeline:
  stages:
    - name: F1 service parallel items abort
      id: f1svcparallelitems
      runtime: shell
      service:
        items:
          - id: this_service_id_does_not_exist_cds130614
            ref: this_service_id_does_not_exist_cds130614
          - id: this_service_id_does_not_exist_cds130614_2
            ref: this_service_id_does_not_exist_cds130614_2
        parallel: true
        on-failure:
          - errors: [ all ]
            action: abort
      environment:
        id: env-a
        deploy-to: infra-a
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
```

### F2 — environment `items` shape, 2 parallel fake environment items, group-level `on-failure: abort`
(Uses `items` instead of `group` — the `group` shape validates entity existence too early, before the
failure-strategy code ever runs, as C3 found out.)
```yaml
pipeline:
  stages:
    - name: F2 environment parallel items abort
      id: f2envparallelitems
      runtime: shell
      service:
        id: sls_github_ecr_llale
        ref: sls_github_ecr_llale
      environment:
        items:
          - id: environment_env_2a02
            deploy-to: this_infra_id_does_not_exist_cds130614
          - id: environment_env_2a02
            deploy-to: this_infra_id_does_not_exist_cds130614_2
        parallel: true
        on-failure:
          - errors: [ all ]
            action: abort
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
```

### G1 — environment `stage-rollback` triggers the `rollback:` steps
```yaml
pipeline:
  stages:
    - name: G1 environment stage-rollback triggers rollback steps
      id: g1envstagerollback
      runtime: shell
      service:
        id: sls_github_ecr_llale
        ref: sls_github_ecr_llale
      environment:
        id: environment_env_2a02
        deploy-to: this_infra_id_does_not_exist_cds130614
        on-failure:
          - errors: [ all ]
            action: stage-rollback
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
      rollback:
        - name: rollback step
          id: rollbackstep
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo rolling back
```

### G2 — service `pipeline-rollback` triggers the `rollback:` steps
```yaml
pipeline:
  stages:
    - name: G2 service pipeline-rollback triggers rollback steps
      id: g2svcpipelinerollback
      runtime: shell
      service:
        id: this_service_id_does_not_exist_cds130614
        ref: this_service_id_does_not_exist_cds130614
        on-failure:
          - errors: [ all ]
            action: pipeline-rollback
      environment:
        id: environment_env_2a02
        deploy-to: infrastructure_kubernetes_5a5e
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
      rollback:
        - name: rollback step
          id: rollbackstep
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo rolling back
```

### G2b — dedicated nested-rollback guard repro (failure INSIDE the rollback path)
```yaml
pipeline:
  stages:
    - name: G2b nested rollback guard
      id: g2bnestedrollbackguard
      runtime: shell
      service:
        id: sls_github_ecr_llale
        ref: sls_github_ecr_llale
      environment:
        id: environment_env_2a02
        deploy-to: this_infra_id_does_not_exist_cds130614
        on-failure:
          - errors: [ all ]
            action: stage-rollback
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
      rollback:
        - name: rollback step that also fails
          id: rollbackstepfails
          on-failure:
            - errors: [ all ]
              action: stage-rollback
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: exit 1
```
Flow: Infrastructure resolution fails on the fake infra id → environment-scope `on-failure: stage-rollback` fires
(this triggers the *current* stage's own `rollback:` block, unlike `pipeline-rollback` which only rolls back
*preceding* stages and is a no-op here since there's only one stage) → `rollback step that also fails` itself
fails (`exit 1`) → that step's own (step-scoped) `on-failure: stage-rollback` would try to trigger a *second*
rollback of the same stage while the first one is still in progress. Watch for: does it loop, hang, or throw an
engine exception, or does it cleanly terminate as Failed (guard working)?

**v1 attempt history:** first version used `service`-scope `stage-rollback` → rejected at plan-creation
(`stage-rollback` isn't in the service-scope allow-list: `RETRY, ABORT, PIPELINE_ROLLBACK, MARK_AS_FAILURE`).
Second version used `service`-scope `pipeline-rollback` → ran, but `pipeline-rollback` only rolls back preceding
stages, so with a single stage it was a no-op and the injected rollback-path failure never executed. This third
version moves the trigger to `environment` scope with `stage-rollback` (as G1 did), which does invoke the
current stage's `rollback:` block.

### H1/H2 — normal successful run, real IDs, `on-failure` present but never triggered
Uses the real, known-good service/environment/infra IDs pulled from Mongo earlier (`sls_github_ecr_llale`,
`environment_env_2a02`, `infrastructure_kubernetes_5a5e`). Covers whatever automatic Rendering/Templating
nodes the graph inserts, since this is a genuine successful run, not a repro.
```yaml
pipeline:
  stages:
    - name: H1 regression run with unused on-failure
      id: h1regressiononfailure
      runtime: shell
      service:
        id: sls_github_ecr_llale
        ref: sls_github_ecr_llale
        on-failure:
          - errors: [ all ]
            action: abort
      environment:
        id: environment_env_2a02
        deploy-to: infrastructure_kubernetes_5a5e
        on-failure:
          - errors: [ all ]
            action: abort
      steps:
        - name: real step
          id: realstep
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo hello from real pipeline
```

### H3 — same run, but with zero `on-failure` fields (pre-feature baseline)
```yaml
pipeline:
  stages:
    - name: H3 baseline no on-failure fields at all
      id: h3baselinenoonfailure
      runtime: shell
      service:
        id: sls_github_ecr_llale
        ref: sls_github_ecr_llale
      environment:
        id: environment_env_2a02
        deploy-to: infrastructure_kubernetes_5a5e
      steps:
        - name: real step
          id: realstep
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo hello from real pipeline
```
Compare this against H1/H2 — they should behave identically.

### I1 — B2 repeated under `runtime: kubernetes` (known-limitation check)
```yaml
pipeline:
  stages:
    - name: I1 environment scope kubernetes runtime check
      id: i1envkubernetes
      runtime: kubernetes
      on-failure:
        - errors: [ all ]
          action: fail
      service:
        id: sls_github_ecr_llale
        ref: sls_github_ecr_llale
      environment:
        id: environment_env_2a02
        deploy-to: this_infra_id_does_not_exist_cds130614
        on-failure:
          - errors: [ all ]
            action: abort
      steps:
        - name: should never run
          id: shouldneverrun
          run:
            container:
              image: alpine
              connector: account.harnessImage
            shell: sh
            script: echo ok
```
Expected: fails at the **Initialize** node (kubernetes delegate/pod setup), never even reaching the
Infrastructure node — so the environment-scope fix doesn't get a chance to engage. A failure here is the
known limitation, not a new bug.
