# CDS-130654 E2E kit: lastPublished / lastSuccessfulDeployed / rollbackArtifact in Unified

Project: `organization_org_a818` / `project_proj_b28b`. Env/infra `environment_env_2a02` / `infrastructure_kubernetes_5a5e`,
runtime `local_rancher_cluster` (ns `default`). Image: `library/nginx` via `test_127344_docker`. "v1" = 1.26.0, "v2" = 1.27.0.
Manifests: `manifests/templates` + one values file per service (read from `main` via `connector_Github_4137_classic`).

Every pipeline echoes the resolved `<+artifacts.primary.tag>` first. PASS = a real tag is printed, not the literal expression.

| # | Pipeline | Steps | Expected |
|---|---|---|---|
| A1 | cds130654_a1_lastpublished_docker | run once | tag = latest nginx tag (check Docker Hub), not `<+lastPublished.tag>` |
| A3 | cds130654_a3_lastpublished_version | PENDING: service `cds130654_a3_version_family` needs a GAR / GitHub Packages connector | `version` = latest version |
| A5 | cds130654_a5_sidecar_lastpublished | run once | primary = 1.26.0, sidecar sc1 = latest busybox tag |
| A6 | cds130654_a6_allowed_values | run, give tag input `<+lastPublished.tag>` | tag = 1.27.0 (latest among allowed 1.26.0,1.27.0) |
| B1 | cds130654_b1_lsd_basic | run1 as is (1.26.0) -> set service tag `<+lastSuccessfulDeployed.tag>` -> run2 | run2 tag = 1.26.0 |
| B3 | cds130654_b3_lsd_skip_failed | run1 (1.26.0, pass) -> tag 1.27.0, run2 (fails on purpose) -> tag `<+lastSuccessfulDeployed.tag>`, run3 | run3 tag = 1.26.0 |
| B4 | cds130654_b4_lsd_no_history | run once (fresh service) | fails: "Cannot find a previous successful deployed artifact..." |
| B5 | cds130654_b5_lsd_source_changed | run1 (nginx 1.26.0) -> imagePath `library/redis` + tag `<+lastSuccessfulDeployed.tag>` -> run2 | run2 fails with source-changed error |
| C1 | cds130654_c1_rollback_artifact | run1 (1.26.0) -> tag 1.27.0 -> run2 | run2 `rollbackArtifact.tag` = 1.26.0 (run1: empty/absent) |
| D1 | cds130654_d1_multistage | run twice | stage A rollbackArtifact = 1.26.0, stage B = 1.27.0. `rollback.primary.tag` in stage B showing 1.26.0 = Q7 bug |
| E1 | cds130654_e1_fixed_tag | run once | tag = 1.26.0 unchanged (regression) |
| E4 | cds130654_e4_serverless_lastpub | run once | ECR `todolist` tag = latest, not the literal |
| F1 | cds130654_f1_v0_parity (v0 NG) | run with service = any of the above, same steps | v1 output must match v0 |

Before the fix: A1/A5/A6/B*/C1/E4 are expected to print the literal expression or fail; that is the baseline capture.
