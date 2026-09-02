# Run 2 — no default values file at all (regression guard)

Run 1 (`noBaitTest/`) proved CDS-131005 discovers `values.yaml` from disk.
Run 2 proves the change is a **no-op** when there is nothing to discover — which is
the shape every existing customer has today: declared values files only.

A FAIL here is worse than a FAIL in Run 1. Run 1 failing means a new feature does not
work; Run 2 failing means the change broke deployments that work today.

## What is deliberately absent

```
noDefaultTest/serverless/   values-a.yaml  values-b.yaml  serverlessUnified.yaml  package.json
noDefaultTest/k8s/          templates/deployment.yaml
noDefaultTest/k8sValues/    values-a.yaml  values-b.yaml
```

No `values.yaml`. No `values.yml`. Not in the manifest directory, not in `templates/`.
Guard it:

```sh
find noDefaultTest -name 'values.yaml' -o -name 'values.yml'   # must print nothing
```

## Why the manifests template fewer keys than Run 1

`noBaitTest/` templates `service` and `region` from the default file. With no default
file those keys have no source, so templating them would only exercise go-template's
missing-key behaviour — a different question, and it would produce `<no value>` inside
`service:`, which makes the manifest invalid and fails Package for the wrong reason.

So in this fixture `service`, `region`, `name`, `image` and `replicas` are **literals**,
and only the keys a declared file supplies are templated. That keeps one variable: a
FAIL can only mean the change corrupted the declared values list.

| Key | Source | Expected render |
|---|---|---|
| `service` / `region` | literal in the manifest | `cds131005-nodefault` / `us-east-1` |
| `stage` | `values-a.yaml` only | `qa` |
| `memorySize` | `values-a.yaml` **and** `values-b.yaml` | `256` — last declared wins |
| `name` / `owner` (k8s) | literal | `cds131005-k8s-nodefault` / `plain-literal-no-expression` |
| `tier` (k8s) | `k8sValues/values-a.yaml` | `qa` |
| `containerPort` (k8s) | `values-a.yaml` **and** `values-b.yaml` | `256` |

## Service configuration

Serverless service (`sls_github_ecr_llale`):

```
paths:              noDefaultTest/serverless
configOverridePath: serverlessUnified.yaml          <- bare filename, NOT a path
values:             noDefaultTest/serverless/values-a.yaml
                    noDefaultTest/serverless/values-b.yaml
```

Kubernetes service (`service_kubernetes_91ad`):

```
paths:       noDefaultTest/k8s
valuesPaths: noDefaultTest/k8sValues/values-a.yaml
             noDefaultTest/k8sValues/values-b.yaml
```

## Pipeline

`pipeline-run2.yaml`, two stages, three steps each.

| Step | Position | Asserts |
|---|---|---|
| `CDS-131003 overrides` | first | `overrides` holds exactly the two declared files; **none** of `overrides` / `toRender` / `toTemplate` mentions any default; the manifest directory on disk contains no `values.yaml` or `values.yml` |
| `Package` / `Dry Run` | middle | load-bearing — it consumes `runtime.manifestPath`, so the injected Rendering and Templating steps hang off it |
| `CDS-131005 rendered manifest` | last | the four table rows above, plus no `<no value>`, no `{{`, and (k8s) no `LEAK-DETECTED` |

The middle step must stay in the middle. An assert placed first reads the raw git
clone and every check fails while nothing is actually wrong — that was Run 1's first
attempt.

Read the render-state listing at the top of the last step first. If no copy is
`RENDERED`, the step ran too early and the ticket is not implicated; the step says so
explicitly rather than reporting a bare FAIL.

Exit codes: `0` pass, `1` a real assert failed, `2` the fixture was not cloned.

`<YOUR_K8S_ENV_ID>` and `<YOUR_K8S_INFRA_ID>` in the Kubernetes stage still need
filling in.
