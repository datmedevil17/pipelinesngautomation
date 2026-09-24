# T15819 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_8f4a`, env
`environment_env_a193`, infra namespace `traffic-shift-demo`, connector
`connector_K8sCluster_a7ec`.

## Attempt 1 — FAIL: "more than one workloads found"

`canaryDeploy` (`k8sCanaryDeployStep`) failed at K8s Canary Preparation:

```
[ERROR] More than one workloads found in the Manifests. Canary deploy
supports only one workload. Others should be marked with annotation
harness.io/direct-apply: true
[FATAL] Error: more than one workloads found in the manifests
Explanations:
 - Found 2 workloads in manifest: [[traffic-shift-demo/Deployment/
   trafficshift-v1 traffic-shift-demo/Deployment/trafficshift-v2]].
   Canary deployment supports only one workload
```

Root cause: `k8sCanaryDeployStep` supports exactly one workload (Deployment)
per manifest set. This suite's service manifest set (`manifests/v1/`,
`manifests/v2/`, `service-stable.yaml`) has two (`trafficshift-v1`,
`trafficshift-v2`), by design (Rolling's fixed-name model). The error message
itself gives the exact fix.

**Fix**: added `annotations: {harness.io/direct-apply: "true"}` to
`manifests/v1/deployment.yaml` (the stable/baseline workload) — see that
file's own comment. This excludes v1 from Canary's workload-count check
(applied directly, not replica-managed), leaving `trafficshift-v2` as the
sole Canary-managed workload. `manifests/v2/deployment.yaml` unchanged.
Confirmed via real run this does NOT affect the Rolling-group scenarios
(T15721/T15723/T15815 already passed with both v1/v2 present, no
annotation needed — Rolling has no single-workload restriction).

First retry attempt still failed with the identical error — root cause was
the fix commit existing locally but not yet pushed (delegate pulls manifests
from git, not local disk). `git push` initially hit a rejected ref-lock
error due to a stale remote-tracking ref, but `git fetch` confirmed the
commit had actually landed on `origin/main` regardless (race condition, not
a real failure) — annotation commit `157c3bc` confirmed on remote.

## Attempt 2 (`pipeline_03d5 #19`) — PASS

All steps green:
- `Canary Deploy` (`Kubernetes Canary Preparation` / `Apply Action` /
  `Steady State`) — succeeded, only `trafficshift-v2` managed as the
  canary workload.
- `Traffic Routing Config (Istio, canary split)` (`trConfig`,
  `k8sTrafficRoutingStep`, `deploy:` key, `config_type: new`,
  `release_number: 11`) — VS `trafficshift-vs` applied with
  `trafficshift-v1` weight 80 / `trafficshift-v2` weight 20, `kubectl apply`
  reported `configured`, release secret `harness.release.release-f1b14b.11`
  updated with traffic-shift info.
- `verify canary split observed on the route` — 50 samples, observed v2 in
  15/50 (30%), within expected [5,40]% range → `PASS: canary split within
  expected range`.

## Status: PASS — T15819 real end-to-end confirmed

Legacy status was `@Ignore("corrupted Istio setup")` — never passed in the
legacy suite. This port passes on real infra once the direct-apply
annotation is in place. Second run (different split / promote further) not
yet executed — not requested yet; would just need a fresh `release_number`
and edited weights, same substitution convention as elsewhere in this repo.

**Next**: T15817 (blue-green) retry, using the new `manifests/bluegreen/`
fixture built earlier, per the user's explicit sequencing request.
