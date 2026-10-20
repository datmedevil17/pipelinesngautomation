# CDS-121526 — [Unified] Service specific Failure Strategy

Epic: CDS-121526. Covers three sub-tickets' worth of schema + plan-creator
work added this cycle:

- **CDS-134767** — `multi-deployment.on-failure` (`run-all` / `skip-queued`),
  `multi-deployment.when`, `multi-deployment.max-concurrency`.
- **CDS-134768** — bare-string shorthand parity for `action` (`retry`,
  `retry-step-group`, `manual-intervention` newly added; `abort`, `ignore`,
  `success`, `stage-rollback`, `pipeline-rollback`, `fail`,
  `proceed-with-default` must keep working as shorthand too).
- **CDS-134760** — service-level and environment-level `on-failure` actually
  wired through the V1/Unified plan creators (previously only step-level
  on-failure took effect).

## Before you run anything

Every YAML in here has `REPLACE_ME_*` placeholders for service/environment/
infra identifiers — swap them for real ones in your test project. **Except**
the two files explicitly marked "intentionally invalid id" below — those are
built to fail on purpose and must be left as-is.

Push this folder to a repo your pipeline can fetch from (git-based pipeline
remote execution), or paste file contents straight into the Harness pipeline
YAML editor — either works, these don't depend on being fetched from a
specific path.

## Why some tests use a bad ID deliberately

A generic entity-not-found error (bad service id, bad env id, bad connector)
is classified by the backend as `APPLICATION_FAILURE` / `UNKNOWN_FAILURE`.
Of the YAML `on-failure.errors` enum values, **only `unknown` or `all`**
match those two — scoping `errors` to e.g. `approval-rejection` or `timeout`
alone will never catch it. Two of the test groups below exploit this on
purpose: one proves the "narrow list doesn't catch it" gap exists, the
other proves `unknown`/`all` does catch it and the configured action fires —
together they're the regression test for CDS-134760's plan-creator wiring.

## Test plan

### `134767-multi-deployment/` — multi-deployment on-failure / when / max-concurrency

- **`pipeline-run-all.yaml`** — 3 services, `max-concurrency: 1` (forces
  sequential execution so ordering is observable), middle service id
  intentionally invalid. `on-failure: run-all`.
  - Expect: service 1 succeeds, service 2 fails, **service 3 still runs**
    (run-all = keep draining the queue even after a failure).
- **`pipeline-skip-queued.yaml`** — same 3-service/`max-concurrency: 1` setup,
  middle service id intentionally invalid, `on-failure: skip-queued`.
  - Expect: service 1 succeeds, service 2 fails, **service 3 is skipped**,
    never starts (skip-queued = stop draining the queue after a failure).
- **`pipeline-when-gate.yaml`** — `multi-deployment.when: <+input>`, run
  once with the runtime input set to `false` and once set to `true`.
  - Expect: `false` → multi-deployment block skipped entirely, no child
    executions created. `true` → runs normally.
- **`pipeline-max-concurrency-throttle.yaml`** — 5 valid services,
  `max-concurrency: 2`.
  - Expect: execution graph/console shows at most 2 service deployments
    `Running` at the same instant, never 3+.

### `134768-action-shorthand/` — bare-string `action:` shorthand parity

- **`pipeline-retry-shorthand.yaml`** — service-level `on-failure` using the
  bare string `action: retry` (not the `{type: Retry, spec: {...}}` object
  form), scoped to `errors: [unknown]`, against an intentionally invalid
  service id.
  - Expect: YAML passes schema validation (shorthand parses), pipeline
    retries the failing node the default retry count, then fails over.
- **`pipeline-retry-step-group-shorthand.yaml`** — same shape, `action:
  retry-step-group`.
  - Expect: on failure, the whole step group containing the failing node
    re-runs, not just the single node.
- **`pipeline-manual-intervention-shorthand.yaml`** — same shape, `action:
  manual-intervention`.
  - Expect: pipeline execution pauses awaiting user input (Abort / Mark as
    Failed / Retry options in the UI) instead of failing straight through.
- **`pipeline-regression-existing-actions.yaml`** — one stage per
  pre-existing action, all as bare-string shorthand: `abort`, `ignore`,
  `success`, `stage-rollback`, `pipeline-rollback`, `fail`,
  `proceed-with-default`, each scoped `errors: [unknown]` against an
  intentionally invalid service id.
  - Expect: no regression — every pre-existing action still parses and
    fires exactly as it did before the shorthand parity change.

### `134760-service-env-onfailure/` — service/environment on-failure plan-creator wiring

- **`pipeline-service-onfailure-narrow-scope.yaml`** — service-level
  `on-failure` scoped to `errors: [approval-rejection, timeout]` only,
  against an intentionally invalid service id.
  - Expect (documents the known gap, not a bug to fix here): the strategy
    does **not** trigger — pipeline fails straight through with the raw
    "Could not find service with id..." error, since the real failure
    classifies as `unknown`/`APPLICATION_FAILURE`, which isn't in scope.
- **`pipeline-service-onfailure-unknown-wildcard.yaml`** — identical setup,
  `errors: [unknown]`, `action: manual-intervention`.
  - Expect: strategy **does** trigger this time — proves CDS-134760 wiring
    actually reaches the service node, not just that the YAML parses.
- **`pipeline-environment-onfailure.yaml`** — environment-level `on-failure`
  (not service-level), `errors: [all]`, `action: pipeline-rollback`,
  against an intentionally invalid environment id.
  - Expect: environment-level strategy triggers a pipeline rollback — proves
    the environment side of CDS-134760 independently of the service side.
- **`pipeline-deploy-to-fixed-allinfra.yaml`** — regression test for the
  earlier `deploy-to: <+input>` plan-creation blocker (two sibling
  environment items each with `deploy-to: <+input>` → "Runtime input
  [<+input>] is not supported as an individual element of the [deploy-to]
  array"). This version has **no `deploy-to` field at all**, relying on
  `all-infra: true` alone.
  - Expect: plan creation succeeds (no "Runtime input... not supported"
    error) and both environment items deploy to all their infra without
    prompting.

## Checklist

- [ ] `134767` run-all keeps draining the queue past a failure
- [ ] `134767` skip-queued stops draining the queue past a failure
- [ ] `134767` `when: false` skips multi-deployment entirely
- [ ] `134767` `max-concurrency` caps simultaneous running children
- [ ] `134768` `retry` shorthand parses + retries
- [ ] `134768` `retry-step-group` shorthand parses + retries the group
- [ ] `134768` `manual-intervention` shorthand parses + pauses
- [ ] `134768` all 7 pre-existing actions still work as shorthand (no regression)
- [ ] `134760` narrow `errors` list does NOT catch a generic entity-not-found failure
- [ ] `134760` `unknown`/`all` DOES catch it and the action fires, at service scope
- [ ] `134760` same wildcard behavior confirmed at environment scope
- [ ] `134760` two environment items with `all-infra: true` and no `deploy-to` create a plan successfully
