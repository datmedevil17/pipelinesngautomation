# CDS-130618 — K8s Apply doesn't resolve relative manifest paths

Parent: CDS-130617 "If a env variable is path, it should always be appended with
absolute path prefix".

## The bug in one line

Backend writes service manifests to `<workspace>/<manifestId>/<path>`; k8s-apply
resolves a user's relative manifest path against nothing at all, so it looks in
the container CWD instead.

Two theories from earlier sessions are **disproven — do not revisit**:

1. ~~"Backend never injects `HARNESS_WORKSPACE` for CD-context V1 steps"~~ — it
   does, on every runtime type. A live run shows
   `- [HARNESS_WORKSPACE] Plugin workspace set by Harness: /harness`.
2. ~~"envconfig prepends `PLUGIN_` so the bare name is invisible"~~ — envconfig
   v1.4.0 falls back to the **unprefixed** tag (`envconfig.go` ~L190:
   `if !ok && info.Alt != ""`). `PLUGIN_WORKSPACE` is dead; no plugin reads it.

The real gap is the missing `<manifestId>` segment.

---

# Phase 1 — Reproduce and see the bug

**No code, no image build.** Uses the released `harnessdev/k8s-apply:0.0.2` via
`k8sApplyAction@1.0.10`.

## Run it

1. Create a pipeline in your account from `pipeline.yaml`.
2. Confirm the service/env/infra/connector ids at the top of the file exist in
   your account (they're the same ones the CDS-126515 / CDS-130614 repros use).
   Swap in any K8s service + env + infra if not.
3. Run it.

## What you'll see

| Step | Status | Why |
|---|---|---|
| `recon` | green | prints CWD + the real `/harness/<manifestId>/…` tree |
| `seedmanifest` | green | plants one ConfigMap at `/harness/cds130618manifest/templates/deployment.yaml` |
| `applyabsolute` | green | **control** — absolute path to that file works |
| `applyrelative` | **RED** | **the bug** — relative path to the *same* file is not found |

No `on-failure: ignore` anywhere, so the status badges are trustworthy this
time. Still read the Logs — the badges tell you *that* it failed, the logs tell
you *why*.

## The three lines to look for in `applyrelative` Logs

Read them in this order; together they are the whole proof.

**1 — the plugin has the workspace. Workspace is not the problem.**
```
- [HARNESS_WORKSPACE] Plugin workspace set by Harness: /harness
- [MANIFEST_PATH] Json array of file or dir paths which contain manifests: [templates/deployment.yaml]
```

**2 — the smoking gun. It searches the bare relative path: no workspace prefix, no manifestId prefix.**
```
Searching for manifest files at path templates/deployment.yaml
```
Compare with the `applyabsolute` step, which prints the full path and succeeds.

**3 — the failure.**
```
there is an issue with finding and reading files at [templates/deployment.yaml]: ... no such file or directory
Please check if provided manifests path [templates/deployment.yaml] is valid and contains the actual files
K8s Apply execution failed
```

The file exists — `seedmanifest` printed it and `applyabsolute` applied it. The
plugin simply never built `<workspace>/<manifestId>/<path>`.

## Why you must override `manifests`

`manifests` defaults to `${{runtime.manifestPath}}`, which resolves to an
**already-absolute** path (the `k8s-template` step's output dir). Absolute paths
short-circuit any resolution, so the default flow never reaches the broken code.
This is exactly why the earlier version of this repro passed green. Only a
**user-supplied relative** path triggers the bug.

## Where the bug is in code

`kubernetes-plugin` @ `75d3f87` — `k8s-apply/plugin/plugin.go:190`:

```go
ManifestInputPath:     pluginArgs.ManifestInputPath.Slice(),   // raw, unresolved
```

Straight into `ManifestHelper.FetchManifestFilePaths`
(`harness-toolkit/service/kubernetes/types/k8s/manifest_helper.go:47`) where
`filepath.Walk` resolves it against CWD.

`Args.ManifestID` already exists with the label *"Identifier of the manifest
that relative manifest paths are resolved against"* — but it is only
`TrimSpace`d, never used. Half-wired.

Contrast `k8s-delete/plugin/util.go:65`, which does it correctly via
`asset.GetExecutionManifestPaths`.

Layout authority: harness-core
`877-pipeline-ci-cd-commons/.../ManifestsStepUtils.java:65-67`:
```java
return normalizeRunnerPath(basePath + "/" + manifestId + "/" + path);
```

---

# Phase 2 — Test the fix

The fix is **local and uncommitted** on two branches, so the released image does
not contain it. Three tiers, cheapest first.

## Tier 1 — unit test (30 seconds, no infra)

```bash
cd ~/projects/kubernetes-plugin/k8s-apply
go test ./plugin/ -run TestManifestInputPathResolvedAgainstManifestDir -v
```

Four cases: relative → `/harness/myManifest/templates/deployment.yaml`;
absolute passthrough; missing manifest id → explicit error; missing workspace →
explicit error. Currently passing.

Note `kubernetes-plugin` is multi-module — `go build ./...` from the repo root
fails (`directory prefix . does not contain main module`). Build/test per module
directory.

## Tier 2 — run the patched binary in a container (2 minutes, no cluster)

Proves the resolved path is correct without needing a registry or a pipeline.

```bash
cd ~/projects/kubernetes-plugin
GOOS=linux GOARCH=amd64 go build -C k8s-apply -o release/linux/amd64/plugin .
docker build -f k8s-apply/docker/Dockerfile.linux.amd64 -t k8s-apply:cds130618 .

# fake workspace mirroring the backend layout
mkdir -p /tmp/ws/cds130618manifest/templates
cat > /tmp/ws/cds130618manifest/templates/deployment.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cds130618-repro
data:
  ticket: CDS-130618
EOF

docker run --rm -v /tmp/ws:/harness \
  -e HARNESS_WORKSPACE=/harness \
  -e PLUGIN_MANIFEST_PATH='["templates/deployment.yaml"]' \
  -e PLUGIN_MANIFEST_ID=cds130618manifest \
  -e PLUGIN_MANIFEST_OUTPUT_PATH=/harness/out \
  -e PLUGIN_KUBECONFIG_PATH=/harness/nonexistent-kubeconfig \
  -e PLUGIN_NAMESPACE=default \
  -e PLUGIN_LOG_LEVEL=debug \
  k8s-apply:cds130618
```

**Pass criterion** — this line, with both prefixes present:
```
Searching for manifest files at path /harness/cds130618manifest/templates/deployment.yaml
The following files will be used:
  - /harness/cds130618manifest/templates/deployment.yaml
```

It will still fail *afterwards* at the kubectl stage (the kubeconfig is fake).
That's expected and irrelevant — path resolution has already been proven, and
that it got as far as kubectl is itself the proof the file was found.

Sanity check the negative: drop `-e PLUGIN_MANIFEST_ID` and you should get
`Cannot resolve relative manifest path "templates/deployment.yaml": manifest id is not set`
instead of a silent wrong-path search.

## Tier 3 — full pipeline (needs a pushed image)

1. Build and push the patched image to a registry the account can pull from:
   ```bash
   docker tag k8s-apply:cds130618 <your-registry>/k8s-apply:cds130618
   docker push <your-registry>/k8s-apply:cds130618
   ```
2. Open `pipeline-fix-verify.yaml`, replace both `<YOUR_PATCHED_IMAGE>`
   placeholders with that tag (and change `connector:` if the registry needs
   auth).
3. Run it. **Expect all steps green.**

It uses raw `run` container steps with explicit `PLUGIN_*` env, so it needs no
template-library change. To test the template wiring end-to-end instead, publish
the `template-library` branch and point `1.0.11/template.yaml`'s image line at
your tag — the file header shows the `k8sApplyAction@1.0.11` variant of that
step.

`pipeline-fix-verify.yaml` also includes an absolute-path regression guard, so a
green run proves both directions.

---

# The fix (uncommitted — "dont commit" is in force)

**`kubernetes-plugin`** (branch work staged on top of `75d3f87`):

- `libs/execution/helper.go` — `ResolveManifestInputPaths(paths, workspace, manifestID)`
  joins `workspace/manifestID/path` for relative paths, passes absolute through,
  and errors explicitly naming which of workspace/manifestId is missing.
- `k8s-apply/plugin/plugin.go` — `mapToApplyArgs` calls it; `ManifestID` lost its
  `default:"primary"`.
- `k8s-apply/plugin/plugin_test.go` — the four-case test above.

**`template-library`** (staged on top of `26da2ef7`):

- `.harness/k8sApplyAction/1.0.11/template.yaml` — adds a `manifest_id` input
  (no default) → `PLUGIN_MANIFEST_ID`, listed under "Service Configuration".
- `config.yaml` — stable/prod1/prod0 bumped 1.0.10 → 1.0.11.

## Open question

`manifest_id` has no default, so a user with relative paths must type it. Worth
checking whether an expression exists that yields the service's single-deploy
manifest id (the backend already computes one in
`CDStepsEnvironmentVarsHelper.retrieveAndSetManifestMetadataForDownload`) so it
can be auto-filled like `kubeconfig` and `namespace` are.

`HARNESS_MANIFEST_DOWNLOAD_PATH` is the same value but is only injected for
manifests fetched via a download task (helm/S3/GCS), not git/file-store — so it
can't be the general solution.
