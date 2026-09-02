# CDS-130614-test — Unified (v1) CD has no service/environment failure strategy

## The gap

NG (v0) CD lets you set a failure strategy on the `serviceConfig` or
`infrastructure` block of a stage, and that strategy takes **priority** over
the stage's own failure strategy. Unified (v1) CD only supports `on-failure`
at the **stage** level -- `service:` and `environment:` have no `on-failure`
key, and (before the fix lands) the stage-level strategy isn't even wired
onto the Service/CD-infra plan nodes, so a Service or Environment resolution
failure just fails the stage outright, ignoring every failure strategy in
the pipeline.

## Layout

    CDS-130614-test/
      pipeline-service-scope.yaml           <- v1 repro: service.on-failure
      pipeline-environment-scope.yaml       <- v1 repro: environment.on-failure
      pipeline-ng-v0-parity-reference.yaml  <- NG v0, for comparison only (not part of the repro)
      README.md

## How each repro works

Both v1 pipelines force a deterministic, connector-independent failure:

- `pipeline-service-scope.yaml` points `service.id` at a service id that
  does not exist -> the **Service** plan node fails.
- `pipeline-environment-scope.yaml` points `environment.deploy-to` at an
  infra id that does not exist -> the **CD-infra** plan node fails.

Each sets two failure strategies with deliberately opposite, easy-to-eyeball
outcomes. The scoped action in each file is chosen from that scope's
allow-list in `UnifiedFailureStrategyHelperV1` (service/environment scope
does **not** allow every action -- e.g. `success`/`MarkAsSuccess` is
rejected at both scopes, matching NG's own `ALLOWED_ACTIONS_FOR_SERVICE`/
`ALLOWED_ACTIONS_FOR_INFRA`):

| repro | scope | action | visible result if honored |
|---|---|---|---|
| service-scope | stage-level `on-failure` | `fail` | pipeline/stage shows **Failed** |
| service-scope | `service.on-failure` | `abort` | pipeline/stage shows **Aborted** |
| environment-scope | stage-level `on-failure` | `fail` | pipeline/stage shows **Failed** |
| environment-scope | `environment.on-failure` | `stage-rollback` | a stage rollback execution runs |

If the scoped strategy is honored (and takes priority, per spec), the
service-scope run should end in **Aborted**, and the environment-scope run
should trigger a **stage rollback** instead of ending in Failed. If the
scoped strategy is ignored, both runs simply end in **Failed** (or,
pre-schema-fix, the pipeline is rejected outright at save/validation time).

## Before running

1. Replace every `<YOUR_...>` placeholder (env id, infra id, service id --
   whichever one isn't the deliberately-broken one in that file).
2. These pipelines don't fetch anything from git, so there's no need to
   commit/push this folder first -- just paste the YAML into the pipeline
   studio (YAML tab) or run via API/CLI.

## Expected results

### Before the fix (bug present)

- Saving/validating the pipeline may be **rejected** outright: the v1
  `ServiceV1`/`EnvironmentV1` schema has `additionalProperties: false` and,
  until CDS-130614 ships, no `on-failure` property -- so the extra key is a
  schema violation.
- If your instance already has the schema change but not the plan-creator
  wiring, the pipeline saves fine, but the run still ends in **Failed**:
  the service/environment-scoped action is never applied, and the
  stage-level `fail` action isn't applied to the Service/CD-infra node
  either (today neither is wired to it).

### After the fix (expected)

- Both pipelines save successfully.
- `pipeline-service-scope.yaml` ends in **Aborted** -- the service-scoped
  `abort` wins over the stage-level `fail`.
- `pipeline-environment-scope.yaml` triggers a **stage rollback** -- the
  environment-scoped `stage-rollback` wins over the stage-level `fail`.
- In both cases the scoped strategy takes priority over the stage-level one,
  matching NG (v0) behavior.

## Reference: NG (v0), for comparison

`pipeline-ng-v0-parity-reference.yaml` is the equivalent NG pipeline using
`serviceConfig.failureStrategies` (service scope) with the same
opposite-outcome trick (`Abort` at service scope vs `MarkAsFailure` at stage
scope). Run it side by side to see the behavior Unified (v1) is missing --
it already ends in **Aborted** today, with no changes needed.

## Scope

This kit tests **whether the failure strategy is honored and prioritized
correctly**, using one allow-listed action per scope. It does not exercise
the full allow-list matrix (e.g. that `Retry`/`PipelineRollback` also work
at service scope, or that a disallowed post-retry action throws instead of
silently downgrading, unlike NG's backward-compat behavior). Those are
Java-level validation-path checks, not something you can observe from a
single pipeline run's final status alone.
