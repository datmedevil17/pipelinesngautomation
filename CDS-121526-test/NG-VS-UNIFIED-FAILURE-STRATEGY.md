# CDS-121526 — Service/Environment failure strategy: NG vs Unified

Status as of 2026-10-19. Branch `fix/CDS-134768-failure-action-shorthand-parity` (nothing pushed).
Every claim is labelled **[verified]** (read in code or observed in a run), **[inferred]** or **[open]**.

## 1. What NG does today

- **Service**: `ServiceYamlV2.failureStrategies` exists. `ServiceFailureStrategyHelper` builds the adviser for the
  service node and only allows `ABORT`, `PIPELINE_ROLLBACK`, `MARK_AS_FAILURE`, `RETRY`
  (`ALLOWED_ACTIONS_FOR_SERVICE`). **[verified]**
- **Environment/infra**: the adviser is attached at the **Infrastructure node**, not an "environment node".
  `InfrastructurePmsPlanCreator` receives the adviser obtainments. **[verified]**
- **Stage level**: a deployment stage must carry at least one failure strategy, and one of them must be the
  `AllErrors`-only one (`DeploymentStagePMSPlanCreatorV2.validateFailureStrategy`). **[verified]**
- **Bare-string actions**: NG had no bare form for `retry`, `retry-step-group`, `manual-intervention`; they need
  parameters. **[inferred from the schema; the V1 deserializer was changed to match]**
- **Multi-deployment** (`strategy: matrix`): `maxConcurrency` and `shouldProceedIfFailed` already existed. **[verified]**

## 2. What Unified (V1 YAML) follows

Plan node order of a deploy stage: **Initialize → Service → Infrastructure → (steps)**.

| Level | Where the adviser lives | Notes |
|-------|-------------------------|-------|
| `service.on-failure` | Service node (`UnifiedServiceStep`) | NG parity |
| `environment.on-failure` | Infrastructure node (`UnifiedCDInfraStep`) | NG parity: infra-level |
| `multi-deployment.on-failure` | spawner / matrix children | `run-all`, `skip-queued` |
| `multi-deployment.max-concurrency` | spawner | throttles children |
| `multi-deployment.when` | **node level** (decision: stays node level, not a stage-level gate) | |

Bare-string `on-failure` actions allowed: `abort`, `ignore`, `success`, `fail`, `stage-rollback`,
`pipeline-rollback`, `proceed-with-default`. `retry`, `retry-step-group`, `manual-intervention` are object-form only; an
unknown bare string now fails with a clear message (`ctxt.weirdStringException`). **[verified, unit-tested]**

## 3. How it was implemented (commit stack on develop `5e398eaa9838`)

| Commit | What |
|--------|------|
| `a83069c58a1c` | CDS-134760 consolidate service/env failure-strategy plan creators |
| `28f4549c569c` | Matrix env/infra resolution failures are deferred (`MATRIX_INFRA_RESOLUTION_ERROR`, `UnifiedCDInfraStep.throwIfDeferredResolutionError`) so the Infra-node adviser can catch them |
| `e08041a2bb1b` | Multi-deployment `on-failure`, `max-concurrency`, `when` |
| `54188b62efbd` | Kryo registration of `MultiDeploymentConfigV1` (ID 110221); without it the plan could not be created |
| `8aa4abcb1126` | Reject unsupported bare shorthand (replaces the dropped CDS-134768 shorthand commit) |
| `19fdcb782f47` | Service node no longer throws for an unresolvable environment; `ServiceEntityProcessor.isEnvironmentResolvable` probe, unit-tested |
| `6f9141fea96d` | Initialize node skips infra implicit steps for an unresolvable environment (`ModulesImplicitStepsConfigHandler`) |

**Why the deferral exists.** An adviser only fires for the node it is attached to. The environment adviser is on the
Infra node, but the environment is *also* resolved earlier: on the Service node
(`ServiceEntityProcessor.getMergedServiceYamlAndSaveOutput`: infra-scope validation, env overrides, env outcome) and on
the Initialize node (`ModulesImplicitStepsConfigHandler`). A bad env therefore failed on a node with no adviser. The fix
is a cheap probe (`isEnvironmentResolvable`); when it fails we skip the env-dependent work and let the Infra node throw
the same error through its adviser. **[verified]**

## 4. Test results (local, `CDS-121526-test/remaining-e2e`)

| Fixture | Result |
|---------|--------|
| 02 env retry, invalid env | PASS: Initialize + Service succeed; Infra node fails 3 times (01:49:32, :44, :55, ~11 s apart = `attempts: 2` + first run); stage Failed via `failure-action: fail` |
| 03 env `stage-rollback` | PARTIAL: error now reaches the Infra node; whether rollback fired is **[open]**, the fixture defines no rollback steps |
| 07 multi-env matrix | PASS: valid leg succeeds, invalid leg fails at Infra, `action: fail` marks pipeline Failed |
| 01 / 04 / 05 service on-failure | Passed earlier on `runtime: shell`. FAIL on `runtime: kubernetes` (see 5.2) |
| 09a / 09b, 06, 08x, 10x, 11 | not re-run on this build, or inconclusive (see section 6) |

## 5. Open questions and known gaps

### 5.1 Retry attempts are not shown in the UI **[open]**
In fixture 02 the log shows three attempts, but the execution graph shows a single Infrastructure node with the final
error. The retries can only be confirmed from ci-manager logs. Unknown: how NG renders retry attempts for the same node
(as far as we looked, we did not compare), and whether Unified is expected to show per-attempt nodes. Needs an owner
decision before this is called a bug.

### 5.2 Kubernetes runtime resolves the service in Initialize **[verified]**
With `runtime: kubernetes`, `K8InitializeTaskParamsBuilder` → `ModulesImplicitStepsConfigHandler.getServiceConfig`
resolves the service while building the pod's implicit steps (manifest/artifact fetch, hooks, rendering). The Initialize
node has no `service.on-failure` adviser, so an invalid service fails there and **retry/rollback never fires**.
The handler is only reached on the Kubernetes init path; with `runtime: shell` it is not, which is why 01/04/05 passed
there and fail on Kubernetes.

Decision (2026-10-19): **not fixing**, because the service has to be fetched at Initialize on this runtime. The
considered fix (catch `InvalidRequestException` in the handler and return no implicit steps, so the Service node throws
through its adviser) was reverted. Its downside: a *transient* ng-manager error at Initialize would produce a pod with
no manifest/artifact steps, the Service node would then succeed on retry of the call, and Deploy would run without the
files. Narrowing the catch to "service not found" would remove that, but we have not confirmed that the not-found case
is distinguishable from the exception type rather than its message.

Same shape, env side: a *valid* env with an *invalid infra id* still fails at Initialize (`getInfraConfig`).

### 5.3 Other open items
- Service actions: NG allows only `abort`, `pipeline-rollback`, `mark-as-failure`, `retry` for the service. We have not
  checked whether Unified restricts `service.on-failure` the same way. **[open]**
- 10c (`max-concurrency`): not proven; runner logs have no step text. Need Deploy start times of deployments 1 and 3.
- 10d (`when: true`): all four deployments failed at Service; need deployment 1's Service error and a re-run without
  `when`/`max-concurrency`.
- 06 partial; 11 is a local environment problem (Docker networking), not this code.
- Invalid service + invalid env in one stage: the service error wins (it fails first).

## 6. Before pushing
Unit tests still to add or run: `getMaxConcurrency`, `shouldProceedIfFailed`, `isDeferredResolutionError`,
`throwIfDeferredResolutionError`, `UnifiedFailureStrategyHelperV1Test`, `saveServiceMetadataOutput` upsert, Kryo
registration. `ModulesImplicitStepsConfigHandler` has **no** unit test for the new env guard. Then
`make codeformat fix=true`, `! gcloud auth login`, `make check`.
