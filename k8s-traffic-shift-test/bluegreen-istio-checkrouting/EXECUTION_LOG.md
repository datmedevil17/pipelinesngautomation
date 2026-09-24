# T15817 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_675d_bg` (new,
manifests at `../manifests/bluegreen/`), env `environment_env_a193`, infra
namespace `traffic-shift-demo`, connector `connector_K8sCluster_a7ec`.

## Attempt 1 — FAIL: manifest-shape incompatibility (`unhandled value for parsing the color`)

Original v1/v2-fixed-name fixtures incompatible with `k8sBlueGreenDeployStep`'s
own color-swap convention. Root cause + fix: new fixture at
`../manifests/bluegreen/` using `${harnessColor}` templating +
`harness.io/color` label, single Service `trafficshift-bg`.

## Attempt 2 — BG deploy passes, verify FAILs: "no healthy upstream"

With the new fixture, `bgDeploy` (`deploy:` key confirmed, not `template:`)
succeeded. But the primary Service's selector (`harness.io/color=green`) never
matched the actually-deployed pod (`trafficshift-bg-blue`) — confirmed via
`kubectl get secret harness.release.release-11d44d.1`: `color: blue`,
`harness.io/bg-environment: stage`. This run only deployed the **stage**
color; nothing swaps the primary Service automatically. Re-running the exact
same pipeline a second time did NOT alternate colors or promote (still
`color: blue`, `stage`) — ruling out an auto-alternating promote-on-rerun
theory.

## Attempt 3 — enabled `traffic_shift: true` on `bgDeploy`

This is the correct mechanism: it exposes a nested "Traffic Routing
Configuration" block (identical shape to standalone `k8sTrafficRoutingStep`)
that manages an Istio VirtualService pointing traffic at the current
stage/primary color, instead of relying on Service-selector swap.

First sub-attempt failed: `resource_name` left at its default
(`traffic-split-${{service.name}}` → `traffic-split-service_kubernetes_675d_bg`)
is invalid — the Service ID contains underscores, and Istio VirtualService
names must be RFC 1123 (lowercase alphanumeric + `-` only). **Fix**: set
`resource_name: trafficshift-bg-vs` explicitly.

Second sub-attempt: destination host set to literal `stage` (a UI placeholder
guess) — VS applied fine (name fix worked) but curl got `''` (empty, not even
"no healthy upstream") — `stage` is not a real, resolvable host.
**Real fix, confirmed via `kubectl get svc`**: `k8sBlueGreenDeployStep` itself
auto-creates a `<serviceName>-stage`-suffixed Service (`trafficshift-bg-stage`,
selector `harness.io/color=blue`, real endpoint) alongside the primary Service
you define in your own manifests. The destination host must be that **actual
Service name**, not the bare word "stage".

## Attempt 4 (final) — PASS (`pipeline_03d5 #26`)

`Traffic Routing Configuration`: `hosts: [trafficshift-bg]`,
`resource_name: trafficshift-bg-vs`, route destination
`host: trafficshift-bg-stage, weight: 100`. All steps green; verify curled
`trafficshift-bg` and got `v1` on attempt 1 → `PASS: BG deploy serving v1`.

## Status: PASS — T15817 real end-to-end confirmed (run 1, v1)

Legacy status was `@Ignore("corrupted Istio setup")` — never passed in the
legacy suite. This port passes on real infra with the corrected fixture +
`traffic_shift: true` + the auto-created `-stage` Service as the routing
destination. Run 2 (flip to v2, promote) not yet executed — would need:
edit `../manifests/bluegreen/deployment.yaml`'s `-text` arg to `v2`, push,
rerun `bgDeploy` (creates a new stage release), then flip the VS destination
weight/verify `EXPECT_VERSION` accordingly. Same edit-and-rerun convention as
elsewhere in this repo — not yet requested.

Same `traffic_shift: true` + `-stage` Service mechanism should apply to
`bluegreen-k8snative-checkrouting/` (T15816), independent of the Gateway API
CRD gap (now lifted — CRDs installed 2026-09-24).

**Next**: k8s-native provider group (T15724/T15726/T15727/T15816/T15818),
now that Gateway API CRDs are installed on the cluster.
