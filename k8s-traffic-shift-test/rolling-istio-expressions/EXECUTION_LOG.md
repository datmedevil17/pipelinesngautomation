# T15722 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_8f4a`, env
`environment_env_a193`, infra namespace `traffic-shift-demo`, connector
`connector_K8sCluster_a7ec`.

## Result: BLOCKED — confirmed DSL limitation, not a porting mistake

### Attempt 1 — save error
`output:` field on the `setFields` run step was authored as a flat list of
bare strings (`- PROVIDER`, `- RESOURCE_NAME`, ...), copied from an earlier,
never-executed session file. Real fix (confirmed via Studio's own "Add Step"
picker capture on an unrelated step): `output:` is a list of
`{name, alias[, mask]}` objects, e.g.:

```yaml
output:
  - name: PROVIDER
    alias: PROVIDER
```

Fixed in `pipeline.yaml` (and the k8s-native twin, `rolling-k8snative-expressions/pipeline.yaml`).

### Attempt 2 — param validation failure

```
- In regards to param PROVIDER:
   * PROVIDER value '${{steps.setFields.output.outputVariables.PROVIDER}}' does not match pattern '^(istio|k8s-native)$'
[FATAL] Error: Input param validation has failed
```

The INPUT PARAMETERS dump showed `PROVIDER`, `RESOURCE_NAME`, and `HOSTNAMES`
still holding the literal unresolved `${{steps.setFields.output.outputVariables.X}}`
string, and route weight fields as opaque CEL placeholders
(`"cel.VARBRV2WV7SXSSKRWYS1VARB4UH5XHYGJY6OPFC"`) instead of resolved values.
The plain integer `RELEASE_NUMBER: 4` resolved fine in the same log.

### Isolation test (confirmed root cause, run `pipeline_03d5 #8`)

Added a plain `run:` step right after `setFields`, referencing the exact
same expressions in its own `env:` block (see
`pipeline-isolation-test.yaml`). Real log output:

```
PROVIDER=istio
RESOURCE_NAME=trafficshift-vs
V1_WEIGHT_CONFIG=100
```

All three resolved correctly. This isolates the bug precisely:

**`${{steps.<id>.output.outputVariables.X}}` resolves inside a `run:` step's
own `env:` block, but does NOT resolve inside a `deploy:`-type step's
(`k8sTrafficRoutingStep`) `with:` block.** Same expression syntax, same
account, same pipeline, same prior step — only the consuming step's type
differs. This is a confirmed DSL/plugin-input-resolution limitation, not a
YAML authoring mistake.

## Status: BLOCKED

T15722 cannot be ported faithfully as an "expression-driven fields" test
under the current CD Unified DSL — there is no verified mechanism for a
`deploy:` step to consume another step's runtime output as an input.
Note the legacy test itself was `@Test(enabled=false)` and was "never
actually run in the legacy suite either" (see `pipeline.yaml` header
comment) — so this gap has zero regression risk against a previously-passing
case.

Flag the same limitation for `rolling-k8snative-expressions/` (T15726) and
`rolling-k8snative-runtime-input/`/`rolling-istio-runtime-input/` if they
attempt the same cross-step-output pattern — the runtime-input variants
(T15723, T15727) use a *different* mechanism (edit-a-pipeline-variable-and-
rerun, per README) and are NOT known to hit this same wall.

**Next**: move to T15723 (`rolling-istio-runtime-input/`), which is
legacy-PASSING and uses the pipeline-variable mechanism instead of step-output
chaining.
