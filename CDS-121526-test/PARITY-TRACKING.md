# CDS-121526 — NG/Unified parity tracker

One row per distinct behavior across the three sub-tickets. "Tested" reflects what's
actually been confirmed via a pipeline run, not just that a fixture exists.

| # | Function | NG | Unified | Tested |
|---|----------|----|---------|--------|
| 1 | `multi-deployment.on-failure: run-all` keeps draining queue past a failed child | Pre-existing | Implemented | Yes (10a + 10c: child 2 failed, 3 and 4 still ran; 10a sequential with max-concurrency 1) |
| 2 | `multi-deployment.on-failure: skip-queued` stops draining queue past a failure | Pre-existing | Implemented | No |
| 3 | `multi-deployment.when` | Pre-existing | Implemented as a **node-level** condition (per node), not a gate for the whole block; schema description still says "queued deployments proceed" (open question) | Partial (10d: `when: true` did not block; 3 valid deployments ran in parallel) |
| 4 | `multi-deployment.max-concurrency` throttles simultaneous children | Pre-existing | Implemented | Yes (10c: two Deploy steps ran together at 09:36:30; 4th start waited until 09:37:05) |
| 5 | `action: retry` bare-string shorthand | No bare form in NG (retry settings are mandatory) | Not supported on purpose: rejected with a clear error, object form only (CDS-134768 closed as not needed) | **Yes** (unit tests, both deserializers) |
| 6 | `action: retry-step-group` bare-string shorthand | No bare form in NG | Not supported on purpose, object form only | **Yes** (unit tests) |
| 7 | `action: manual-intervention` bare-string shorthand | No bare form in NG | Not supported on purpose, object form only | **Yes** (unit tests) |
| 8 | 7 pre-existing actions (`abort`, `ignore`, `success`, `stage-rollback`, `pipeline-rollback`, `fail`, `proceed-with-default`) still work as shorthand | Supported | No regression expected | No |
| 9 | `service.on-failure` — narrow `errors` list (e.g. `approval-rejection`) does **not** catch generic not-found | Same documented gap | Same by design | **Yes** — run #29: raw NotFoundException on Service node, no strategy message, downstream Skipped |
| 10 | `service.on-failure` — `unknown`/`all` wildcard **does** catch generic not-found, action fires at service scope | Baseline | Wired through V1 service-step plan creator | **Yes** — run #22 (multi-service) and run #30 (single-item): Failed not Aborted, downstream Skipped |
| 11 | `environment.on-failure` — wildcard fires, `pipeline-rollback` | Baseline | Adviser attached at **Infra-node** level (NG parity: infra-level, not environment-level) + deferred-resolution-error mechanism | **Yes** — run #17: Service succeeded, Infrastructure surfaced deferred error, Pipeline Rollback fired |
| 12 | `all-infra: true` multi-env deploy, no on-failure (deploy-to plan-creation regression) | N/A (Unified-only path) | Fixed — no more "Runtime input... not supported" blocker | Inconclusive — run #19 hit unrelated Docker networking flake |
| 13 | Multi-**service** (2+ real items) + `service.on-failure`, per-matrix-child isolation | Baseline | Deferred-resolution + per-node adviser | Partial — run #22: bad-child isolation confirmed; good child inconclusive (Docker flake at Infrastructure). Needs clean re-run |
| 14 | Multi-**environment** (2+ real items via `all-infra`) + `environment.on-failure`, per-matrix-child isolation | Baseline | Same mechanism, environment side | No — fixture written, not yet run |
| 15 | *(internal)* STRATEGY-node eager `all-infra` fetch deferred to Infra node | N/A (Unified plan-creator internal) | Implemented (`resolutionError` / `MATRIX_INFRA_RESOLUTION_ERROR`) | **Yes** — run #17 |
| 16 | *(internal)* Service step's own eager env/infra resolution deferred to Infra node | N/A (Unified-specific; Service runs before Infra, has no adviser of its own) | Implemented this session (`UnifiedServiceStepParameters.resolutionError` + `ServiceStepUtility.isDeferredResolutionError`) | **Yes** — run #17 |
| 17 | `environment.on-failure` with `stage-rollback`: invalid env, rollback steps run | Baseline | Error deferred to Infra node, adviser fires, stage rollback steps execute | **Yes** — pipeline_e6ac #1: Initialize/Service Success, Infrastructure Failed, Rollback step Success (`rollback-ran`) |

## Legend
- **Yes** — directly observed passing in a pipeline run this session.
- **Partial** — some sub-case confirmed, another sub-case blocked/inconclusive (usually the recurring local Docker networking flake, unrelated to this code).
- **Unconfirmed this session** — fixture exists and is presumably correct, but no run was observed in this conversation window; verify against your own run history before relying on it.
- **No** — not exercised yet in this session; matches the README checklist's unchecked state.
