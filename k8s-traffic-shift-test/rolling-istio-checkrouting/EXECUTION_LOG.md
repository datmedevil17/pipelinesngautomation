# T15815 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_8f4a`, env
`environment_env_a193`, infra namespace `traffic-shift-demo`, connector
`connector_K8sCluster_a7ec`.

## Prerequisite fix: added `manifests/service-stable.yaml` to the Service

The `trafficshift` (stable, selector `app: trafficshift` matching both
versions) k8s Service the VS's `hosts:` and the `verifyRouting` step's curl
target depend on did not exist in-cluster (`kubectl get svc` showed only
`trafficshift-v1`/`trafficshift-v2`). Added `manifests/service-stable.yaml`
as an additional manifest **file** source on the Harness Service (repo
`pipelinesngautomation`, same connector as v1/v2).

## Run 1 (input set A: EXPECT_VERSION=v1, weights v1=100/v2=0) — PASS

`release_number: 8` (current run's own number — checked via
`kubectl get secrets | grep harness.release` first, per the corrected rule
in `../rolling-istio-config-inherit/EXECUTION_LOG.md`).

```
[INFO] kubectl apply --filename=... --namespace=traffic-shift-demo
virtualservice.networking.istio.io/trafficshift-vs configured
[INFO] Updated release harness.release.release-f1b14b.8 with traffic shift info
[INFO] K8s Traffic Shift execution successfully finished
```

`verifyRouting` step:

```
attempt 1: got 'v1', expect 'v1'
PASS: traffic routed to v1
```

Real, first-attempt pass — traffic genuinely landed on the v1 backend
(`hashicorp/http-echo` returning the fixed string `v1`), not just "step
succeeded."

Note: unlike the Config→Inherit chain, `config_type: new` here is
**idempotent across reruns** — `kubectl apply` reports `configured` (not
`created`) on repeat runs against the same resource name, so no
`config_type: update`/release-history dependency exists for this scenario.
Only need a fresh, unique `release_number` per run (no matching-value
constraint between steps, since there's only one traffic-routing step here).

## Run 2 (input set B: EXPECT_VERSION=v2, weights v1=0/v2=100) — PASS

First attempt re-ran with unchanged weights (YAML edit didn't actually save
before running — `trConfig`'s `ROUTES` input parameter showed the same
v1=100/v2=0 as run 1). Also hit a real infra blocker on this attempt:
cluster had 12 leftover `harnessci-cdst*` step pods stuck `NotReady`/`Pending`
from every prior run in this suite (T15721 x5, T15722 x2, T15723 x2, T15815
x3) never cleaned up, driving node CPU allocation to 86-95% and blocking new
pod scheduling (`FailedScheduling: Insufficient cpu`). Force-deleted all 12
(`kubectl delete pod --grace-period=0 --force`), CPU dropped to ~5%.
Delegate SA (`traffic-shift-test-delegate`) already has a cluster-admin
ClusterRoleBinding, so this was not an RBAC gap -- just accumulated leaked
pods; worth periodically cleaning up `traffic-shift-demo` between runs.

With weights actually flipped (v1=0/v2=100) and a fresh `release_number`,
verify step:

```
attempt 1: got 'v2', expect 'v2'
PASS: traffic routed to v2
```

## Status: PASS — T15815 real end-to-end confirmed, both input sets
