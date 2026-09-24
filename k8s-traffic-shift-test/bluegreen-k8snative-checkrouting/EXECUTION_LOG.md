# T15816 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_675d_bg`
(reused from T15817, manifests at `../manifests/bluegreen/`), env
`environment_env_a193`, infra namespace `traffic-shift-demo`, connector
`connector_K8sCluster_a7ec`. Provider: `k8s-native` (Gateway API), not Istio.

Legacy status: SMI/TrafficSplit-based (`@Test(enabled=false)`, SMI infra
deleted — same blocker as the Rolling SMI scenarios). Reframed onto
`k8s-native` (Gateway API HTTPRoute), reusing the BG fixture already built
and proven for T15817 (`${harnessColor}`-templated Deployment, primary
Service `trafficshift-bg`, auto-created stage Service `trafficshift-bg-stage`).

## Real design fix applied before running (not a failure — caught by inspection)

The Istio version's verify script curls an internal Service DNS name
(`*.svc.cluster.local`). A Gateway API HTTPRoute only intercepts traffic
arriving through its parent Gateway's own listener/IP — it does **not**
intercept plain internal Service DNS lookups the way Istio's mesh-wide
VirtualService does. Copying the Istio verify script as-is would have
silently bypassed the HTTPRoute and curled whatever the literal Service's
own selector resolves to, giving a false-positive PASS unrelated to the
routing config under test.

**Fix**: verify step curls the Gateway's own LB address
(`kubectl get gateway trafficshift-gateway -o jsonpath='{.status.addresses[0].value}'`
→ `136.109.237.207`, confirmed real) with an explicit `Host: trafficshift-bg`
header matching the HTTPRoute's `hostnames` entry — this actually routes
through the HTTPRoute's backendRefs/weights.

Also used a distinct `resource_name: trafficshift-bg-route` (not
`trafficshift-route`, which is already owned by
`rolling-k8snative-config-inherit/`'s T15724 HTTPRoute) to avoid cross-ticket
resource collisions on the shared cluster.

## Attempt 1 (only attempt) — PASS

- `Blue-Green Deploy` (`deploy:` key, `traffic_shift: false` — using the
  standalone `k8sTrafficRoutingStep` below instead of BG's built-in option)
  — succeeded, stage color deployed.
- `Traffic Routing Config (k8s-native, BG cutover)` — `HTTPRoute/
  trafficshift-bg-route` created: `hostnames: [trafficshift-bg]`,
  `parentRefs: [trafficshift-gateway]`, backends
  `trafficshift-bg` weight 0 / `trafficshift-bg-stage` weight 100. Applied
  cleanly, release secret `harness.release.release-11d44d.7` updated.
- `verify BG cutover reaches expected version` — curl via Gateway LB
  (`http://136.109.237.207/` + `Host: trafficshift-bg`) → attempt 1 got
  `v1`, expected `v1` → `PASS: BG cutover routed to v1`.

## Status: PASS — T15816 real end-to-end confirmed

Legacy test never ran on real infra (SMI provider, clusters long deleted).
This port passes on the current `k8s-native` (Gateway API) provider, reusing
the T15817 BG fixture and the T15724 cluster prerequisites (Gateway, RBAC).
Run 2 (flip to v2) not yet executed — same as T15817's run 2, not yet
requested.

**Next**: `canary-k8snative-checkrouting` (T15818) — last remaining ticket.
