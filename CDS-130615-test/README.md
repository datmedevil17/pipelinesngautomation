# CDS-130615 — `InheritFromManifest` is a parity gap in Unified

Parent: CDS-126325. Jira: "InheritFromManifest backward compatibility for
outcome and to run ng service in unified".

## The gap, in one line

NG lets a values/params manifest skip declaring its own connector by
inheriting the primary manifest's store
(`io.harness.cdng.manifest.ManifestStoreType#InheritFromManifest`). Unified
has **no working equivalent** — and it is broken in two independent places,
not one.

## Where it breaks (source-level, not a guess)

**A. "Run NG service in Unified"** — a Unified pipeline stage pointing
`service:` at a classic NG service triggers an on-the-fly conversion
(`TemplateBasedManifestMapper` → `UnifiedConversionRegistry`,
`120-ng-manager`). That registry has two tables:

| table | has `InheritFromManifest`? |
|---|---|
| `STORE_TYPE_MAP` (`UnifiedConversionRegistry.java:203`) | yes |
| `STORE_ACTION_MAP` (`UnifiedConversionRegistry.java:157-169`) | **no** |

`convertManifest()` only reads `STORE_ACTION_MAP`. It returns `null` for an
`InheritFromManifest` values/params manifest, and the caller does
`.filter(Objects::nonNull)` — the manifest is **silently dropped**. Only a
DEBUG log line ("Manifest type {} with store {} not onboarded for
template-based conversion") marks it. No exception, no WARN. The primary k8s
manifest still converts fine, so the service conversion "succeeds" overall —
the override just vanishes. Same bug hits environment/service overrides via
`TemplateBasedOverridesMapper`, which shares the same mapper.

**B. Natively-authored Unified manifest** with `store.uses: inherit` — the
schema side is actually *already wired*:
`io.harness.unified.cd.service.manifests.StoreType.INHERIT` and
`InheritManifestStoreConfig` (`960-ng-core-beans`) are registered
`StoreConfig` subtypes, so this deserializes/validates fine. But there is no
execution consumer. `332-ci-manager`'s `ManifestsStep` resolves a fetch
template by `{manifest-type}-{store-action}` name, and no
`values-inherit-template.yaml` / `params-inherit-template.yaml` exists under
`332-ci-manager/service/src/main/resources/templates/manifests/` — it fails
with `InvalidRequestException("Template not found at path...")`.

Neither path has real resolution logic: `inherit` has no connector of its
own, so something has to look up the *sibling primary manifest*'s store
before any fetch task can be built. NG does this ad hoc, inline, separately
in `K8sHelmCommonStepHelper`, `K8sStepHelper`, `NativeHelmStepHelper` — right
before submitting the delegate task, never by rewriting the persisted
`ManifestOutcome` (it stays `InheritFromManifestStoreConfig{paths}` forever;
every consumer re-resolves it on demand). Unified has no analogous
resolution step at all today.

NG also explicitly **rejects** `InheritFromManifest` when the primary
manifest's store is Harness File Store (`K8sStepHelper.java:797`,
`NativeHelmStepHelper.java:373` — "InheritFromManifest store type is not
supported with Manifest identifier ..."), because there's no connector to
borrow. A correct Unified port needs the same guard.

## Layout

    CDS-130615-test/
      k8s/
        templates/
          deployment.yaml        <- primary manifest under test, fully templated
        (deliberately NO values.yaml here — see CDS-130653-test for why)
      k8sValues/
        values-inherit.yaml      <- the file the InheritFromManifest values manifest points at
      pipeline-cds130615-ngservice.yaml

Every key in `deployment.yaml` (`proof`, `replicaCount`, `image`,
`containerPort`) is supplied **only** by `k8sValues/values-inherit.yaml`, so
there is no other source that could mask the bug.

## Scenario A — run this first (confirmed, silent-drop bug)

1. Commit and push `CDS-130615-test/` — the pipeline fetches from git, not
   your working copy.
2. Create a **classic NG** Kubernetes service (not unified/simplified) with:
   - a primary K8s manifest, store Git/GitHub, paths `CDS-130615-test/k8s`
   - a Values manifest, store **Inherit From Manifest** (the option shown in
     the CDS-130615 screenshot), paths
     `CDS-130615-test/k8sValues/values-inherit.yaml`
3. Open `pipeline-cds130615-ngservice.yaml`, point `service:` at that classic
   service's identifier, fill in environment/infra/connector placeholders.
4. Run it.

### Expected results

Before the fix:

    step 1 (evidence): BUG PRESENT -- inherited values manifest is ABSENT
    step 2 (Dry Run):  still renders raw "{{ .Values.* }}" (or fails validation)
    step 3 (rendered): FAIL on every assert

After the fix:

    step 1 (evidence): inherited values manifest SURVIVED conversion
    step 2 (Dry Run):  PASS
    step 3 (rendered): PASS  proof=INHERIT-WORKED replicas=9 image=nginx:1.26 containerPort=9090

### Optional negative case

On the same classic service, switch the primary manifest's store to Harness
File Store. NG rejects this combination outright. A correct fix should
reject it loudly at **conversion time** in `120-ng-manager` — not drop it
silently, and not let it crash three layers down inside `ManifestsStep` with
"Template not found at path...".

## Scenario B — exploratory (native Unified authoring)

Reuse `pipeline-cds130615-ngservice.yaml`, but point `service:` at a
**Unified/simplified** K8s service instead, configured (via the Unified UI's
own manifest-source picker, since the UI-side "Inherit From Manifest" option
already exists per this ticket) with two source manifests:

- primary: `uses: k8s`, store Git/GitHub, paths `CDS-130615-test/k8s`
- values override: `uses: values`, store **Inherit From Manifest**, paths
  `CDS-130615-test/k8sValues/values-inherit.yaml`

For engineers wiring this by hand instead of via UI, the underlying bean
shape (`960-ng-core-beans/.../unified/cd/service/manifests/`) is:

```
ManifestConfig{ uses: "values", with: ValuesManifest{
  store: StoreConfigWrapper{ uses: "inherit", with: InheritManifestStoreConfig{
    paths: ["CDS-130615-test/k8sValues/values-inherit.yaml"] } } } }
```

**This variant is unverified against the live schema/UI contract** — I did
not confirm the exact end-user YAML/API surface for attaching a per-source
store to a Unified service's manifest list, only the Java bean shape that
ends up persisted. Expect this to reproduce the "Template not found at
path..." failure (`TemplateYamlGenerator.java:297`) rather than the silent
drop from Scenario A, since this path skips the NG-conversion registry
entirely.

## Proposed fix (no code changed yet — see investigation notes)

1. `120-ng-manager`: add `StoreConfigType.InheritFromManifest → StoreType.INHERIT`
   to `UnifiedConversionRegistry.STORE_ACTION_MAP`; carry the manifest's own
   `paths` through in `TemplateBasedManifestMapper`; port NG's Harness-File-Store
   rejection guard so a bad combination fails loudly at conversion time.
2. `332-ci-manager`: add an `isInheritStore(...)` branch in `ManifestsStep`
   (parallel to the existing `isHarnessStore` special-case) that finds the
   sibling primary manifest (k8s/helm-chart/kustomize/openshift-template),
   borrows its store/connector/action, keeps this manifest's own `paths`, and
   routes to the primary's **existing** per-store template — no new
   `*-inherit-template.yaml` files needed, since `inherit` is never itself a
   concrete fetch target.

Open design question not yet resolved: whether the Unified *outcome*
(`serviceOutput.manifests.*`) should keep showing `inherit` as the store type
post-resolution (matching NG, which never rewrites the persisted
`ManifestOutcome`) or show the resolved concrete store — needs a call before
implementing, since it's what "backward compatibility for outcome" in the
ticket title is actually asking about.
