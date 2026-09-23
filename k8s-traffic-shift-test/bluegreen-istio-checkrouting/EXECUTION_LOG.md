# T15817 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_8f4a`, env
`environment_env_a193`, infra namespace `traffic-shift-demo`, connector
`connector_K8sCluster_a7ec`.

## Result: BLOCKED — confirmed manifest-shape incompatibility with `k8sBlueGreenDeployStep`

`bgDeploy` (`k8sBlueGreenDeployStep`) failed at the preparation stage, before
any apply:

```
[INFO] Searching for manifest files at path /harness/m2/k8s-traffic-shift-test/manifests/v1
[INFO]  - .../manifests/v1/deployment.yaml
[INFO]  - .../manifests/v1/service.yaml
[INFO] Searching for manifest files at path /harness/m2/k8s-traffic-shift-test/manifests/v2
[INFO]  - .../manifests/v2/deployment.yaml
[INFO]  - .../manifests/v2/service.yaml
[INFO] Searching for manifest files at path /harness/m2/k8s-traffic-shift-test/manifests/service-stable.yaml
[WARNING] There was an issue with saving annotation to the release secret [harness.io/infra]=[]
[ERROR] K8s BlueGreen Preparation execution failed
[FATAL] Error: are you sure this release was used only for blue-green deployment? unhandled value for parsing the color
```

## Root cause (confirmed via real error, not guessed)

`k8sBlueGreenDeployStep` expects Harness's own built-in blue/green
color-swap convention: a single `Deployment` + a `Service` pair where
Harness itself manages a "primary"/"stage" (blue/green) color label/
annotation and swaps it on cutover. It parses the manifest set looking for
that color marker and fails outright if it isn't present in the expected
shape.

This suite's fixtures (`manifests/v1/`, `manifests/v2/`,
`manifests/service-stable.yaml`) are the Rolling group's fixed-name model —
two independently-named Deployment+Service pairs (`trafficshift-v1`,
`trafficshift-v2`) plus a stable frontend Service, with version-switching
done entirely by the separate `k8sTrafficRoutingStep` (Istio VS weights),
not by Harness's BG mechanism. That model is fundamentally incompatible with
`k8sBlueGreenDeployStep`'s own color-swap expectations -- not a config
mistake, a structural mismatch between fixture designs.

## Status: BLOCKED

Legacy status for this ticket was already `@Ignore("corrupted Istio setup")`
-- never passed in the legacy suite either, so this carries zero regression
risk. A faithful BG port would require a *separate* fixture set built for
Harness's own primary/stage color convention (single Deployment/Service,
no fixed v1/v2 naming) -- out of scope to build speculatively without a
verified real example of what that manifest shape needs to look like for
this plugin version. Flag the same risk for `bluegreen-k8snative-checkrouting/`
(T15816) if/when the Gateway API blocker is ever lifted -- it likely hits
the identical `k8sBlueGreenDeployStep` incompatibility, independent of the
Gateway API CRD gap.

**Next**: move to T15819 (`canary-istio-checkrouting/`) -- uses
`k8sCanaryDeployStep`, which may or may not share this same color-convention
requirement; verify via real run rather than assuming either way.
