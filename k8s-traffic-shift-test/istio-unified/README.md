# Istio unified traffic-shift suite (local port)

A local port of Automation's `K8sTrafficShiftIstioUnifiedTest`. The pipelines are the suite's
`common/cdpNG/k8s/pipeline/unified/k8s-traffic-shift-istio-*.yaml` with the `$placeholders`
filled in for the local setup, and the `delegate:` selectors dropped.

| placeholder | value |
|---|---|
| env / infra | `environment_env_2a02` / `infrastructure_kubernetes_5a5e` (ns `default`, `local_rancher_cluster`) |
| runtime | ns `default`, connector `local_rancher_cluster` |
| `$infraNamespace` / `$kubeconfig` | `<+infra.namespace>` / `<+infrastructure.PLUGIN_HARNESS_KUBE_CONFIG_PATH>` |
| `$releaseName` | `releasename-3100NN` (NN = test number) |

## One-time setup

1. Push this folder (the check-routing services read `manifests/` from `main`).
2. Create the services in `setup/services/` (project `project_proj_b28b`). Test 10 reuses the existing
   `k8scanary_custom_remote`. The ids are alphanumeric on purpose, because `$svcRef` ends up in
   VirtualService names (`virtual-service-<svc>`).
3. Run `00-bootstrap.yaml`. It checks Istio and labels `default` with `istio-injection=enabled`.
   Tests 04–06 need that label: the traffic generator only follows the VirtualService split
   through its sidecar. It also means the runner step pods in `default` get sidecars.
4. Tests 10–13 need FF `CDS_ISTIO_VS_MERGE_IN_TRAFFIC_ROUTING`.

## Tests

| file | Automation test | service |
|---|---|---|
| 01-config-and-inherit | ConfigAndInheritSteps | tsistioplain |
| 02-…-with-expressions | …WithExpressions | tsistioplain |
| 03-…-runtime-inputs (+ `.input-set.yaml`) | …WithRuntimeInputs | tsistioplain |
| 04-config-and-verify-routing | ConfigAndCheckTheRouting | tsistiorollcheck |
| 05-bluegreen-verify-routing.run-v1 → run-v2 | BG check routing | tsistiobgcheck |
| 06-canary-verify-routing.run-v1 → run-v2 | Canary check routing | tsistiocanarycheck |
| 07-bluegreen-delegate-service | BG delegate service | tsistiobgcheck |
| 08-canary-delegate-service | Canary delegate service | tsistiocanarycheck |
| 09-config-and-inherit-delegate-service | Config/inherit delegate service | tsistioplain |
| 10-canary-merge-existing-vs | Canary merge existing VS | k8scanary_custom_remote |
| 11-bluegreen-merge-existing-vs | BG merge existing VS | tsistiobgmergevs |
| 12-canary-merge-unnamed-named-tcp | Merge unnamed/named/tcp | tsistiomerge{unnamed,named,tcp} |
| 13-canary-no-match-fallback-hosts-preserved | No-match fallback / hosts | tsistiomerge{nomatch,hosts} |

05 and 06 run twice, like the Java test: first `run-v1`, then `run-v2`, in the same pipeline and back
to back. Both runs share the prefix and release, so the v1 run leaves the stable workload behind
and the v2 run checks the 90/10 split (900/100 hits out of 1000).

## Deviations from Automation

- `manifests/` is written from scratch. The pipelinesngaautomation `traffic-routing-dynamic`
  manifests aren't available here, so these are built from the names the pipelines expect.
  The apps are `hashicorp/http-echo`, which answers `v1`/`v2`. The generator is `curlimages/curl`,
  which sends 1000 requests and prints `DONE_COOKING`, `v1: N`, `v2: N`.
- The rolling generator ships with the rolling deploy, before the VS exists. It waits 120s before
  sending traffic.
- I added a `responseText` input to 08, because its canary manifests render
  `${{pipeline.inputs.responseText}}`.
- `org.DockerConnectorForAutomationTest` is replaced with `account.harnessImage` in the bootstrap.
