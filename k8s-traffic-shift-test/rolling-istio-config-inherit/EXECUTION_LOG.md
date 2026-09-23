# T15721 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_8f4a`, env
`environment_env_a193`, infra namespace `traffic-shift-demo`, connector
`connector_K8sCluster_a7ec`.

## Result: Traffic Routing Inherit step finished, but did nothing real

```
[WARNING] Release [release-f1b14b] was not found in history. Skipping traffic shift resource update.
[INFO] K8s Traffic Shift execution successfully finished
```

Step reports success, but the VirtualService patch was **skipped** — no
release history existed for `release-f1b14b`, so `config_type: update`
had nothing to inherit from. This means the preceding `config_type: new`
(Traffic Routing Config step) never actually persisted a tracked release
for this run, or `k8sRollingDeployStep` before it didn't establish one.

## Root cause + fix (confirmed 2026-09-24, run 3)

`release_number` in `k8sTrafficRoutingStep`'s `with:` block must equal
the **actual current Harness release number** for that infra (starts
at 1, increments every pipeline run against the same infra/env pair —
matches the `harness.release.<name>.<N>` secret Harness itself creates
in-cluster). We had hardcoded `release_number: 0` in both `trConfig`
and `trInherit`, which never matches any real release, so `trInherit`'s
history lookup always came back empty and silently skipped the patch
even though the pipeline reported success.

Setting `release_number: 2` made `trInherit` find the release, log
`Found 1 traffic shift resources in release`, normalize weights, and
successfully `kubectl patch` the VirtualService to v1=0/v2=100.

**Precise rule** (derived from 3 runs against this infra): `release_number`
for `trInherit` = **(current run's auto-assigned release number N) − 1**.
Release numbers auto-increment per run against the same infra/env pair,
starting at 1. Inherit reads the *previous* release's tracked resource
info, so run 1 (N=1) can never succeed — there is no release 0 — by
design. Run 2 (N=2) needed `release_number: 1` (we'd left it at 0 →
failed). Run 3 (N=3) needed `release_number: 2` (set correctly → passed).
Next pipeline reusing this same infra will be N=4, needing `release_number: 3`.

**Open gap**: no verified expression (e.g. an `infra.releaseNumber`
equivalent) exists yet for auto-resolving this per run — must be
hardcoded/bumped manually each run until confirmed via the step
template picker. Flag this in every other ticket folder that chains
`config_type: new` → `config_type: update` (T15722, T15723, T15815,
T15724/26/27, T15816-19).

## CORRECTION (2026-09-24, T15723 run) — the N-1 rule above was wrong

T15723 (`rolling-istio-runtime-input/`) disproved the N-1 theory. With
release history polluted by intervening runs from other pipelines against
the same infra (T15722's failed attempts, the isolation-test pipeline —
none of which ran a `config_type: new` step to completion), setting
`trInherit`'s `release_number` to `(current run N) - 1` failed with:

```
[WARNING] There was not any information in release history regarding
previous traffic shift execution on which to make an update.
```

because release `N-1` had no traffic-shift tracking data (it was created by
a pipeline run that never reached `trConfig`). Setting **both `trConfig`
AND `trInherit` to the SAME value — the current run's own release
number** — passed: `Found 1 traffic shift resources in release`, patch
applied, cluster state verified via `kubectl get vs`.

**Corrected rule**: `release_number` in both the `config_type: new` and
`config_type: update` steps of a single run must be **identical**, and
equal to that run's own auto-assigned release number (check via
`kubectl get secrets -n <namespace> | grep harness.release` before each
run — take the highest existing number + 1). The earlier "N-1, only on
Inherit" finding from run 3 of this ticket was very likely a coincidence:
that cluster's release history was still an unbroken chain at the time
(every prior release had a completed `config_type: new`), which can
make N-1 *appear* to work by accident if `trConfig`'s field was left
unedited at the same stale value. Treat **same-value-both-steps** as the
authoritative rule going forward.
