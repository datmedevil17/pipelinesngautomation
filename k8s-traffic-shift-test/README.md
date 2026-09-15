# k8s-traffic-shift-test -- CD Unified port of the K8s Traffic Routing suite

Ports the 11 legacy `K8s_TrafficRouting_steps_tests` (CDNG Automation) test
cases to CD Unified `uses:/with:` pipelines. Source: QA test-plan sheet
(Sprint 240, owner ivan.balan) + Slack thread `C0A56BZ44V6/p1788155737475119`.

## Read this before writing any SMI-labeled pipeline

The legacy suite treats **SMI** as a real provider (`TrafficSplit` CRD,
`split.smi-spec.io`). **The current `kubernetes-plugin` (the Go plugin behind
CD Unified's traffic-routing steps) has no SMI provider at all.** Its
`provider` input only accepts two values:

| value | resource it creates |
|---|---|
| `istio` | a single Istio `VirtualService` (never a `DestinationRule`) |
| `k8s-native` | a Gateway API `HTTPRoute` (`gateway.networking.k8s.io`) -- **not** an SMI `TrafficSplit` |

So every legacy "SMI" case below (T15724, T15726, T15727, T15816, T15818) is
reframed here as a **`k8s-native` / Gateway API** case, not a literal SMI
port -- SMI cannot be tested against this plugin because it doesn't exist in
it. This is a correction to the test plan, not a porting choice.

## Prerequisites (currently unmet -- this is the real blocker, per Slack)

- A K8s cluster with **Istio installed** (`istiod` running) for the `istio`
  scenarios, with the target namespace labeled `istio-injection=enabled` so
  sidecars get injected into `trafficshift-v1`/`trafficshift-v2` pods.
- For the `k8s-native` scenarios: a cluster with a **Gateway API** CRD set
  installed (`HTTPRoute` etc.) and a Gateway resource already provisioned in
  the namespace.
- Neither exists yet for this effort (Slack: infra missing/corrupted,
  status "Dev Testing Pending" as of 2026-09-12). All scenarios below are
  written and ready to run the moment infra lands; none can pass today.
- Shared fixtures: `manifests/v1/`, `manifests/v2/` (Deployment + Service
  each), `service.yaml` (fetches both). Every scenario reuses these -- only
  the pipeline differs.

## Runtime-input note (T15723, T15727)

The legacy suite drives these two via `<+input>` placeholders + an input
set. No equivalent (`<+input>`, input set, or pipeline-level `inputs:`)
exists anywhere in the CD Unified DSL in this repo -- confirmed by grepping
`test-test`, `template-library`, `harness-toolkit`, `runner`,
`runUnifiedUi`, `pipelinesngaautomation`. Those two folders instead use a
pipeline **variable you edit and re-run**, the same substitution this repo
already uses elsewhere (see `CDS-126515-test`'s "edit the service, re-run"
pattern). Flagging this as an open DSL-capability gap, not claiming parity.

## The 11 cases

| Folder | Legacy ticket | Strategy | Provider | Legacy status |
|---|---|---|---|---|
| `rolling-istio-config-inherit/` | T15721 | Rolling | Istio | PASSING |
| `rolling-istio-expressions/` | T15722 | Rolling | Istio | disabled (community group) |
| `rolling-istio-runtime-input/` | T15723 | Rolling | Istio | PASSING |
| `rolling-istio-checkrouting/` | T15815 | Rolling | Istio | PASSING |
| `rolling-k8snative-config-inherit/` | T15724 (reframed from SMI) | Rolling | k8s-native | disabled, SMI infra deleted |
| `rolling-k8snative-expressions/` | T15726 (reframed from SMI) | Rolling | k8s-native | disabled, same SMI blocker |
| `rolling-k8snative-runtime-input/` | T15727 (reframed from SMI) | Rolling | k8s-native | disabled, same SMI blocker |
| `bluegreen-istio-checkrouting/` | T15817 | Blue-Green | Istio | @Ignore("corrupted Istio setup") |
| `bluegreen-k8snative-checkrouting/` | T15816 (reframed from SMI) | Blue-Green | k8s-native | disabled, SMI infra deleted |
| `canary-istio-checkrouting/` | T15819 | Canary | Istio | @Ignore("corrupted Istio setup") |
| `canary-k8snative-checkrouting/` | T15818 (reframed from SMI) | Canary | k8s-native | disabled, flaky even pre-SMI-deletion ("//failure" comment) |

## Order to run in

1. `rolling-istio-config-inherit/` -- simplest baseline (Config+Inherit,
   no traffic verification). Prove the chain works first.
2. `rolling-istio-expressions/`, `rolling-istio-runtime-input/` -- same
   chain, different field-sourcing.
3. `rolling-istio-checkrouting/` -- adds the live routing-verification step
   and the two-run v1/v2 procedure every later group reuses.
4. `rolling-k8snative-*` (3 folders) -- same three variants, `k8s-native`
   provider, confirms the step pair isn't Istio-specific.
5. `bluegreen-istio-checkrouting/`, `bluegreen-k8snative-checkrouting/` --
   all-or-nothing cutover instead of Rolling's no-op split.
6. `canary-istio-checkrouting/`, `canary-k8snative-checkrouting/` --
   percentage-based partial split. Run last; T15818's k8s-native variant is
   the least-proven case in the whole matrix even in the legacy suite.

Every pipeline uses placeholders `<YOUR_GIT_CONNECTOR>`, `<YOUR_K8S_CONNECTOR>`,
`<YOUR_ISTIO_NAMESPACE>` / `<YOUR_GATEWAY_NAMESPACE>`, `<YOUR_SERVICE_ID>`,
`<YOUR_ENV_ID>`, `<YOUR_INFRA_ID>` -- fill these in per your account before
running, per this repo's normal convention.
