# noBaitTest — CDS-131005 P0 run: is default-values discovery really disk-based?

## The question

Every earlier CDS-131005 run used a default `values.yaml` containing
`owner: <+service.name>` — a deliberate "bait". The fetch stage
(`harness-rendering`) only returns a file's **body** when that file contains a
Harness expression, so the bait guaranteed the default file passed through the
fetch stage.

Real customer values files usually contain **no** Harness expression. So every
green run so far leaves one question open:

> Does CDS-131005 find the default values file because it is **on disk**,
> or because the **fetch stage handed it over**?

If it is the latter, the feature silently does nothing for the common case.

## The one variable

These fixtures are **byte-identical** copies of `serverlessTest/`, `k8sTest/`
and `k8sValues/`, with exactly one line changed in each default values file:

    owner: <+service.name>              ->  owner: plain-literal-no-expression

Everything else — manifests, declared values files, `package.json`, the
`templates/values.yaml` leak canary — is `cmp`-identical to the originals.
So any behaviour difference is attributable to the bait and nothing else.

The manifest still carries `<+artifact.image>`, which is required: the manifest
must keep qualifying for the fetch stage. Only the **values** file goes quiet.

## Layout

    noBaitTest/
      serverless/                  <- manifest path (Serverless swimlane)
        serverlessUnified.yaml     <- manifest, via manifest.spec.configOverridePath
        values.yaml                <- DEFAULT, UNDECLARED, no expression
        values-a.yaml              <- DECLARED values[0]
        values-b.yaml              <- DECLARED values[1]
        package.json
      k8s/                         <- manifest path (Kubernetes swimlane, REFERENCE)
        values.yaml                <- DEFAULT, UNDECLARED, no expression
        templates/
          deployment.yaml          <- the manifest under test
          values.yaml              <- fetched but NOT applied (known asymmetry)
      k8sValues/
        values-a.yaml              <- DECLARED valuesPaths[0]
        values-b.yaml              <- DECLARED valuesPaths[1]

## Why a Kubernetes run is included

Kubernetes already ships the convention CDS-131005 adds to Serverless:
`k8s-template` probes `<manifestDir>/values.yml` then `values.yaml`. So the k8s
run is the **control**, not extra coverage. It also makes the outcome readable:

| Serverless | Kubernetes | Conclusion |
|------------|------------|------------|
| PASS | PASS | Discovery is disk-based in both. **CDS-131005 is correct; ship it.** |
| FAIL | PASS | The concept works; the bug is in Serverless plugin wiring only. Debug `serverless-template`. |
| FAIL | FAIL | The default file never reaches disk at all. Discovery cannot be disk-based — CDS-131005 needs redesign to read the fetch output instead. |
| PASS | FAIL | Pre-existing Kubernetes defect, unrelated to this ticket. File separately. |

## Run 1 — Serverless

Service config:

    manifests:
      - manifest:
          identifier: serverlessManifest
          type: ServerlessAwsLambda
          spec:
            store: <your git connector>, path: noBaitTest/serverless
            configOverridePath: noBaitTest/serverless/serverlessUnified.yaml
            values:
              - noBaitTest/serverless/values-a.yaml
              - noBaitTest/serverless/values-b.yaml

Note `values.yaml` is **not** listed. That is the whole point.

### Assert table — rendered `serverlessUnified.yaml`

| field                    | PASS                  | FAIL means                                        |
|--------------------------|-----------------------|---------------------------------------------------|
| `service`                | `cds131005-default`   | `<no value>` -> default file NOT discovered        |
| `provider.region`        | `us-east-1`           | `<no value>` -> default file NOT discovered        |
| `provider.stage`         | `qa`                  | `dev` -> declared did not beat default            |
| `provider.memorySize`    | `256`                 | `512`/`1024` -> not last-declared-wins            |
| `frameworkVersion`       | `3.39.0`              | (fixture sanity)                                  |

`service` and `provider.region` are the only real proof: those keys exist in no
other values file. If the step **fails to render** on an unresolved
`{{ .Values.serviceName }}`, the default file was not read — that is the FAIL
signal this run is designed to catch.

### CDS-131003 assert (should still hold)

`serviceOutput.manifests.overrides` must contain EXACTLY:

    /harness/<repo>/noBaitTest/serverless/values-a.yaml
    /harness/<repo>/noBaitTest/serverless/values-b.yaml

and must NOT contain `noBaitTest/serverless/values.yaml`.
`toTemplate` MAY contain it — that is the prepend, and it is correct.

## Run 2 — Kubernetes (reference)

Service config:

    manifests:
      - manifest:
          identifier: k8sManifest
          type: K8sManifest
          spec:
            store: <your git connector>
            paths:
              - noBaitTest/k8s
            valuesPaths:
              - noBaitTest/k8sValues/values-a.yaml
              - noBaitTest/k8sValues/values-b.yaml

### Assert table — rendered `noBaitTest/k8s/templates/deployment.yaml`

| field                   | PASS                            | FAIL means                                   |
|-------------------------|---------------------------------|----------------------------------------------|
| `metadata.name`         | `cds131005-k8s-default`         | `<no value>` -> default file not discovered  |
| `spec.replicas`         | `3`                             | `<no value>` -> default file not discovered  |
| `image`                 | `nginx:1.25`                    | `<no value>` -> default file not discovered  |
| `labels.owner`          | `plain-literal-no-expression`   | `<no value>` -> default file not discovered  |
| `labels.tier`           | `qa`                            | `default-tier` -> precedence inverted        |
| `containerPort`         | `256`                           | `512`/`1024` -> not last-declared-wins       |
| `templates-dir-default` | `<no value>`                    | `LEAK-DETECTED` -> CDS-131003 leak present   |

`labels.owner` is new signal in this run: because the bait is gone, `owner` is
now an only-in-default key, so it is a fourth independent proof of discovery.

## Before running

These fixtures must be committed and pushed — the pipeline fetches them from
git, not from your working copy.

## assert.sh

Drop a Run step after the templating step. No path needed -- the script finds
the rendered manifest itself, because the workspace layout depends on the
manifest identifier and cannot be known in advance:

    ./noBaitTest/assert.sh serverless
    ./noBaitTest/assert.sh k8s

Pass a path as the 2nd argument to override. If nothing is found it prints the
workspace tree so you can see the real layout.

Exit codes: `0` all asserts passed, `1` at least one assert failed, `2` misuse
(manifest missing / bad mode). It exits non-zero on failure, so the step goes
red without anyone reading the log.

Self-tested against synthetic PASS and FAIL renders before first use — 6/6 exit
codes correct, including the "default file not discovered" case. Every check is
`expected vs actual`; there is deliberately no `grep -q X && FAIL` idiom, which
is what produced a false FAIL in run R18.
