# T15724 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_8f4a`, env
`environment_env_a193`, infra namespace `traffic-shift-demo`, connector
`connector_K8sCluster_a7ec`. Provider: `k8s-native` (Gateway API), not Istio.

Legacy status: SMI/TrafficSplit-based (`@Test(enabled=false)`, SMI clusters
deleted per prior Slack thread) — reframed for this port onto the current
plugin's `k8s-native` provider (HTTPRoute/Gateway API), since SMI is not a
supported provider anymore (only `istio` / `k8s-native`).

## Prerequisites installed this session

- Gateway API CRDs (`gatewayclasses`, `gateways`, `httproutes`, `grpcroutes`,
  `referencegrants`) installed cluster-wide via the standard v1.1.0 install
  manifest. Istio auto-registered `GatewayClass istio`
  (`controller: istio.io/gateway-controller`), confirmed `ACCEPTED: True`.
- `Gateway/trafficshift-gateway` applied directly to the cluster (NOT via any
  Harness Service manifest set — matches the pipeline's own `<needsSetup>`
  comment expecting this as a pre-provisioned prerequisite). See
  `../manifests/gateway.yaml`. Istio auto-provisioned a `LoadBalancer` Service
  + proxy pod; `PROGRAMMED: True`, real GCP LB IP assigned.

## Attempt 1 — FAIL: cluster resource exhaustion (unrelated to the pipeline logic)

`FailedScheduling: Insufficient cpu` — leftover `harnessci-*` step pods from
earlier aborted/completed runs reserved CPU requests. Fixed via explicit
literal `kubectl delete pod ... --grace-period=0 --force` cleanup (real usage
was only 3-6% per `kubectl top nodes` — a scheduling-request problem, not a
real capacity problem).

## Attempt 2 — FAIL: immutable `spec.selector` on `trafficshift-v2`

```
[FATAL] failed to apply manifest [...]. Error: [The Deployment
"trafficshift-v2" is invalid: spec.selector: Invalid value:
{"matchLabels":{"app":"trafficshift","harness.io/track":"stable","version":"v2"}}:
field is immutable (code: 1)]
```

Root cause: the `harness.io/direct-apply: "true"` annotation added to
`../manifests/v1/deployment.yaml` (for the Canary single-workload fix, see
`../canary-istio-checkrouting/EXECUTION_LOG.md`) had a side effect on Rolling
too — with v1 excluded, Rolling now treats `trafficshift-v2` as the *sole*
"Managed Workload" and injects its own `harness.io/track: stable` label into
that workload's selector. The *live* `trafficshift-v2` Deployment (confirmed
via `kubectl get deployment trafficshift-v2 -o jsonpath='{.spec.selector}'`)
had no such label in its existing (immutable) selector — `{app, version}`
only — so the new selector value was rejected outright by the API server.
This never surfaced in the earlier Rolling-only runs (T15721/T15723/T15815)
because both v1 and v2 were "Managed Workloads" back then, and the
single-managed-workload track-labeling convention apparently only kicks in
with exactly one managed workload (shared code path with Canary/BG).

**Fix**: `kubectl delete deployment trafficshift-v2 -n traffic-shift-demo`,
letting the next Rolling apply recreate it fresh with the track-labeled
selector baked in from creation (no immutability conflict on a new object).
One-time cluster fixup, not a manifest/pipeline change — no file edits
required for this specific issue.

## Attempt 3 — FAIL: RBAC forbidden on `httproutes`

```
[FATAL] ... Error from server (Forbidden): ... httproutes.gateway.networking.k8s.io
"trafficshift-route" is forbidden: User
"system:serviceaccount:harness-delegate-ng:random-test" cannot get resource
"httproutes" in API group "gateway.networking.k8s.io" in the namespace
"traffic-shift-demo"
```

Root cause: the connector's kubeconfig authenticates as SA `random-test`
(namespace `harness-delegate-ng`) — a *different* identity than the
delegate's own `traffic-shift-test-delegate` SA (which has a cluster-admin
binding). `random-test` only had the `istio-traffic-admin` ClusterRole
(bound via RoleBinding in `traffic-shift-demo`), and that role's rules were
scoped to `apiGroups: [networking.istio.io]` only (`virtualservices`,
`destinationrules`, `gateways`, `serviceentries`) — it predated the Gateway
API CRD install and was never extended to cover
`gateway.networking.k8s.io`.

**Fix**: patched the existing `istio-traffic-admin` ClusterRole (user ran
this manually — RBAC-modifying commands are blocked by the coding-agent's
own permission classifier):

```
kubectl patch clusterrole istio-traffic-admin --type=json -p='[{"op":"add","path":"/rules/-","value":{"apiGroups":["gateway.networking.k8s.io"],"resources":["gateways","httproutes","grpcroutes","referencegrants"],"verbs":["get","list","watch","create","update","patch","delete"]}}]'
```

Confirmed via `kubectl get clusterrole istio-traffic-admin -o yaml` that the
new rule was added; no new RoleBinding needed since `random-test` was already
bound to this ClusterRole in `traffic-shift-demo`.

## Attempt 4 (final) — PASS

- `Kubernetes Rolling Deploy` — `trafficshift-v2` recreated cleanly, steady
  state reached.
- `Traffic Routing Config (k8s-native, config_type: new, release_number: 12)`
  — `HTTPRoute/trafficshift-route` created via consolidated manifest apply,
  `parentRefs: [trafficshift-gateway]`, `hostnames: [trafficshift]`,
  backends v1=100/v2=0.
- `Traffic Routing Inherit (config_type: update, release_number: 12)` —
  `kubectl patch` normalized backend weights to v1=0/v2=100, applied
  successfully.
- Confirmed via `kubectl get httproute trafficshift-route -o yaml`: live
  weights v1=0/v2=100, `status.conditions`: `Accepted: True`,
  `ResolvedRefs: True`, `controllerName: istio.io/gateway-controller`.

## Status: PASS — T15724 real end-to-end confirmed

Legacy test never ran on real infra (SMI provider, clusters long deleted).
This port passes on the current `k8s-native` (Gateway API) provider, with
three real, independent infra issues surfaced and fixed along the way (CPU
exhaustion, immutable-selector conflict from the Canary annotation's side
effect, and missing RBAC for the new Gateway API resource group).

**Note for later k8s-native tickets**: the RBAC fix (istio-traffic-admin now
covers `gateway.networking.k8s.io`) and the Gateway resource
(`trafficshift-gateway`) are cluster-level prerequisites — already satisfied
for T15726/T15727/T15816/T15818, no need to repeat.

**Next**: `rolling-k8snative-runtime-input` (T15727).
