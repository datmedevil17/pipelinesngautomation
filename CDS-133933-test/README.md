# CDS-133933 local repro kit

Bug: standalone `K8sTrafficRouting` step (`spec.type: config`, Istio provider)
ignores `isMergeExistingVS()` and never merges into a manifest's existing
`VirtualService`. Root cause is in `harness-core`:

- `930-delegate-tasks/src/main/java/io/harness/delegate/k8s/K8sTrafficRoutingRequestHandler.java`,
  `prepareForTrafficRouting()` — unconditionally calls `createTrafficRoutingResources(...)`,
  never checks `K8sTrafficRoutingRequest.isMergeExistingVS()`, never calls
  `IstioTrafficRoutingResourceCreator.mergeWithExistingManifest(...)`.
- Secondary bug once merge is wired up: `IstioTrafficRoutingResourceCreator.mergeWithExistingManifest`
  overwrites `spec.gateways` instead of union-merging with the manifest's existing gateways.

## Why this kit is classic NG YAML, not the Unified `uses:/with:` DSL

`~/projects/test-test/k8s-traffic-shift-test/` (the folder named in the repro
request) is CD **Unified** — its `k8sTrafficRoutingStep` runs through an
independent Go plugin (`kubernetes-plugin` repo,
`k8s-traffic-shift/plugin/trafficshift/`), confirmed by zero references to
`k8sTrafficRoutingStep`/`K8S_TRAFFIC_ROUTING` anywhere in `120-ng-manager` or
`332-ci-manager`. Running those pipelines would not touch
`K8sTrafficRoutingRequestHandler` at all, so it can't reproduce this bug.

This kit borrows that folder's fixture conventions (manifest naming,
`harness.io/direct-apply: "true"`, resource name `trafficshift-vs`) but is
written as a **classic NG pipeline** (`service` + `environment` +
`K8sRollingDeploy` + standalone `K8sTrafficRouting` step), matching the style
already proven to exercise the Java handler in the Automation module's
`k8sTrafficRoutingIstio_ConfigAndInherit.yaml` / `k8sCanaryTRIstioMergeVSSvc.yaml`.

## Files

- `manifests/deployment.yaml`, `manifests/service.yaml` — plain app workload.
- `manifests/virtualservice.yaml` — the pre-existing manifest VS. Has
  `gateways: [customer-gateway]`, `http[0].timeout: 30s`,
  `http[0].retries.attempts: 3` — exactly the fields that must survive a merge.
- `ng-service.yaml` — classic NG `service` entity, `CustomRemote` store with an
  inline heredoc extraction script, so no git push is needed to stage the
  three manifests above. Fill in `<YOUR_ORG>` / `<YOUR_PROJECT>`.
- `pipeline-no-hosts.yaml` — Repro A.
- `pipeline-with-hosts.yaml` — Repro B.

## Setup

1. Enable the account-level feature flag `CDS_ISTIO_VS_MERGE_IN_TRAFFIC_ROUTING`
   on your test account (this is the only thing that sets
   `K8sTrafficRoutingRequest.mergeExistingVS` — it is not a YAML field, see
   `125-cd-nextgen/src/main/java/io/harness/cdng/k8s/asyncsteps/K8sTrafficRoutingStep.java:143-144`).
2. Create a project/org, a Kubernetes connector + infra pointing at a cluster
   with Istio installed, and a `Gateway` named `customer-gateway` in the
   target namespace (any Gateway object satisfies the reference; Istio
   doesn't validate it eagerly).
3. Create the service from `ng-service.yaml`, filling in the placeholders.
4. Create both pipelines, filling in `<YOUR_ENV_ID>` / `<YOUR_INFRA_ID>`.

## Run order and expected evidence

**Repro A — `pipeline-no-hosts.yaml`:**
Run it. On unpatched code the `K8sTrafficRouting` step fails with
`Hosts field is invalid or empty`, because `createTrafficRoutingResources`
requires `hosts` to build a brand-new VS and never falls back to reusing the
manifest's `hosts: [trafficshift.example.com]` via a merge.

**Repro B — `pipeline-with-hosts.yaml`:**
Run it. The step succeeds. Check the dumped VS from the `dumpVS` step output
(or run `kubectl get virtualservice/trafficshift-vs -n <namespace> -o yaml`
yourself). On unpatched code:
- `spec.gateways` is **missing** (manifest's `customer-gateway` is gone).
- `spec.http[0].timeout` and `spec.http[0].retries` are **missing**.

After the fix lands, re-run both:
- Repro A should succeed (hosts come from the manifest's existing VS via merge).
- Repro B should succeed AND the dumped VS should still show
  `gateways: [customer-gateway]`, `http[0].timeout: 30s`,
  `http[0].retries.attempts: 3`, merged alongside the step's `route1` destination.
