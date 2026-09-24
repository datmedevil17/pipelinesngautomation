# T15818 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_8f4a`
(reused v1/v2 fixture from T15819), env `environment_env_a193`, infra
namespace `traffic-shift-demo`, connector `connector_K8sCluster_a7ec`.
Provider: `k8s-native` (Gateway API), not Istio.

Legacy status: SMI/TrafficSplit-based, `@Test(enabled=false)` (SMI infra
deleted) AND marked `//failure` in a pre-existing code comment even before
that — the least-proven scenario in the whole matrix. Reframed onto
`k8s-native` (Gateway API HTTPRoute), reusing the Canary fixture already
proven for T15819 (`harness.io/direct-apply` annotation on
`manifests/v1/deployment.yaml` already in place, no new manifest changes
needed).

Same Gateway API caveat as T15816 applied proactively before running: verify
script curls the Gateway's own LB address (`136.109.237.207`) with an
explicit `Host: trafficshift` header, not internal Service DNS (which would
bypass the HTTPRoute entirely). `resource_name` set to
`trafficshift-canary-route` (distinct from T15724's `trafficshift-route`) to
avoid cross-ticket collision on the shared cluster.

## Attempt 1 (only attempt) — PASS

- `Canary Deploy` (`template:` key, `k8sCanaryDeployStep`) — succeeded,
  `trafficshift-v2` managed as the sole canary workload (v1 excluded via the
  direct-apply annotation).
- `Traffic Routing Config (k8s-native, canary split)` — `HTTPRoute/
  trafficshift-canary-route` created: `hostnames: [trafficshift]`,
  `parentRefs: [trafficshift-gateway]`, backends `trafficshift-v1` weight 80
  / `trafficshift-v2` weight 20. Applied cleanly, release secret
  `harness.release.release-f1b14b.13` updated.
- `verify canary split observed on the route` — 50 samples via
  `http://136.109.237.207/` + `Host: trafficshift`, observed v2 in 9/50
  (18%), within expected [5,40]% range → `PASS: canary split within
  expected range`.

## Status: PASS — T15818 real end-to-end confirmed

New evidence, not a restored known-good result — this scenario never passed
in the legacy suite (flaky even pre-SMI-deletion) and had never run on real
infra. Passes here on the current `k8s-native` (Gateway API) provider,
reusing T15819's fixture and T15724's cluster prerequisites (Gateway, RBAC).
Run 2 (further promotion) not yet executed — not requested.

## This was the last of the 11 ported tickets.

Final matrix status:
- **PASS (8)**: T15721, T15723, T15724, T15815, T15816, T15817, T15818, T15819
- **BLOCKED — cross-step expression DSL gap (2)**: T15722, T15726
- **SKIP — duplicate coverage of T15724 (1)**: T15727
