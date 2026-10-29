# CDS-130657 – Helm repo override in Unified (generic) service – E2E test plan

Branch: `CDS-130657` (harness-core). Restart ng-manager **and** ci-manager after the build.

## Fixtures (reused in every case)
- Connector `helm_repo_a` – Http Helm repo, **broken** (test connection fails, `index.yaml` -> 404)
- Connector `helm_repo_b` – Http Helm repo, **working** (nexus3 URL)
- Env `environment_env_33fe`, infra `infrastructure_kubernetes_6357` (NativeHelm, ns `default`)
- Service `helm_override_svc` (NativeHelm) -> chart `hello-world` 0.1.0 from `helm_repo_a`

### Service
```yaml
service:
  name: helm-override-svc
  identifier: helm_override_svc
  serviceDefinition:
    type: NativeHelm
    spec:
      manifests:
        - manifest:
            identifier: myChart
            type: HelmChart
            spec:
              store:
                type: Http
                spec:
                  connectorRef: helm_repo_a
              chartName: hello-world
              chartVersion: 0.1.0
              helmVersion: V3
              skipResourceVersioning: false
  gitOpsEnabled: false
```

### Pipeline (same for all cases; only the overrides change)
```yaml
pipeline:
  clone:
    disabled: true
  stages:
    - name: CDS-130657 helm repo override
      id: cds130657
      service: helm_override_svc
      environment:
        id: environment_env_33fe
        deploy-to: infrastructure_kubernetes_6357
      steps:
        - name: Render
          id: helmrender
          template:
            uses: k8sHelmTemplateAction
            with:
              output: /harness/rendered-helm.yaml
              print_manifest: true
      runtime:
        kubernetes:
          namespace: default
          connector: connector_K8sCluster_local
          automount-service-token: true
          pull: always
      timeout: 15m
```

### Override YAML used below (Overrides page `/settings/serviceOverrides` -> YAML editor)
```yaml
overrides:
  manifests:
    - manifest:
        identifier: m1
        type: HelmRepoOverride
        spec:
          connectorRef: helm_repo_b
          type: Http
```
**What proves the override worked:** in the Service step log, `myChart` fetch shows
`[HTTP_NAME] HTTP connector name: helm_repo_b` (not `helm_repo_a`) and no 404.

## Cases

| # | Setup | Expected | Before fix |
|---|-------|----------|------------|
| 1 | **Control**: no override | Service step fails, `HTTP connector name: helm_repo_a`, 404 | same |
| 2 | **Env global** override (`helm_repo_b`), env `environment_env_33fe`, all services | Service step passes, log shows `helm_repo_b` | NPE `"pk" is null` |
| 3 | **Env + service** override (env + `helm_override_svc`) -> `helm_repo_b` | passes, `helm_repo_b` | NPE |
| 4 | **Infra global** override (infra `infrastructure_kubernetes_6357`) -> `helm_repo_b` | passes, `helm_repo_b` | NPE |
| 5 | **Infra + service** override -> `helm_repo_b` | passes, `helm_repo_b` | NPE |
| 6 | **Priority A**: env global -> `helm_repo_a`, infra+service -> `helm_repo_b` | passes, `helm_repo_b` (infra+service is highest priority) | NPE |
| 7 | **Priority B**: env global -> `helm_repo_b`, infra+service -> `helm_repo_a` | fails 404, `HTTP connector name: helm_repo_a` | NPE |
| 8 | **Discriminator**: override -> a connector that is also broken (e.g. `helm_repo_c`, bad URL) | fails, log shows `helm_repo_c` and **its** URL, not `helm_repo_a` | NPE |
| 9 | **Different identifier**: override `identifier: anything_else` (not `myChart`) | still passes with `helm_repo_b` (helm repo override targets all helm charts, matching NG) | NPE |
| 10 | **Regression – other overrides**: add a `Values` manifest override (+ variable override) in addition to the helm repo override | helm repo override still applied, values/variable override still applied | n/a |
| 11 | **Regression – no manifests override**: a different service with a Kubernetes `K8sManifest` and an env override with variables only | pipeline unchanged, passes | passes |
| 12 | **Cross store (optional, needs an OCI helm registry)**: service Http -> override `type: OCI` with OCI connector `helm_oci_b` | action switches to OCI fetch (`PLUGIN_OCI_NAME`/oci plugin in log), `basePath` `/` | NPE |
| 13 | **Incompatible (negative)**: service chart store `S3`, override `type: Http` | override is ignored for that chart (S3 connector unchanged), no crash | NPE |

## How to run
1. Create/verify connectors and service above. 2. Run case 1 first (must fail with A).
3. For each case: set only the override(s) listed, delete them after the run, run the pipeline,
   open the Service step -> `myChart` log and check the `HTTP connector name` line.
4. ng-manager console must not show `NullPointerException` for any case.

## Unit tests added
- `OverrideApplyHelperTest` (ci-manager): http connector replace, Http<->OCI swap, incompatible store, not added as manifest source.
- `TemplateBasedManifestMapperTest` (ng-manager): helm repo override converted without store, null store does not throw.
- **Not compiled/run yet** – no bazel cache on this machine; run via IDE or `bazel test` before the PR.
