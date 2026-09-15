# CDS-130660 repro kit

Reproduces: K8s Rolling Deploy manifest-not-found failure when a unified CD
stage runs under Shell runtime + local delegate (docker), vs the same stage
succeeding under Kubernetes runtime.

## Files
- `pipeline.yaml` -- two stages, otherwise identical (same service/env/infra,
  same `k8sRollingDeployStep`), differing only in `runtime:`.

## Before running
1. Swap `service_kubernetes_0b81` / `environment_env_2a02` /
   `infrastructure_kubernetes_5a5e` / `account.cdautomationtest` for a real
   K8s service (with an actual manifest store configured) + env + infra in
   your account, unless you're on the same account these repro kits were
   built against.
2. `delegate: docker` on the Shell stage is a guess at the local delegate's
   selector/tag -- change it to match whatever selector routes to your
   local docker delegate. If you don't need to pin it, delete the `delegate:`
   line and let it auto-select, as long as only one delegate can serve Shell
   runtime in your account.
3. `git push` this file to wherever your pipeline is git-synced, or paste it
   directly into the pipeline YAML editor.

## Expected result
- Stage 1 (`cds130660_k8s`, `runtime: kubernetes`): **PASS**.
- Stage 2 (`cds130660_shell`, `runtime: shell`): **FAIL** at
  `rollingDeployShell`, reproducing:
  ```
  [INFO] Searching for manifest files at path /tmp/harness/<UUID>/manifest_1/...
  [ERROR] K8s Rolling Preparation failed
  [FATAL] Error: there is an issue with finding and reading files at [...]: lstat ...: no such file or directory
  ```

## What to capture for the investigation
From each `recon*` step (runs before the deploy step, always green):
- The `workspace env` block -- specifically `HARNESS_WORKSPACE` and
  `HARNESS_MANIFEST_DOWNLOAD_PATH` (if set) in both stages.
- The directory tree dump -- in the Shell stage, is the manifest actually
  present anywhere under `$HARNESS_WORKSPACE`, just not where the deploy step
  looks? Or is it missing entirely (fetch/render step wrote it somewhere the
  Shell workspace never shares)?

Compare against the Rolling Deploy step's own `[INFO] Searching for manifest
files at path ...` line to see exactly which path it computed and how that
relates to what actually exists on disk.
