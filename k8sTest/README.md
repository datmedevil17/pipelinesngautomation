# k8sTest — CDS-131003 + CDS-131005 fixture (Kubernetes swimlane)

Service layout:

    k8sTest/                     <- manifest path (store.spec.paths)
      values.yaml                <- DEFAULT, UNDECLARED  (discovered by convention)
      templates/
        deployment.yaml          <- the manifest under test
        values.yaml              <- fetched but NOT applied (known asymmetry)
    k8sValues/
      values-a.yaml              <- DECLARED via manifest.spec.valuesPaths[0]
      values-b.yaml              <- DECLARED via manifest.spec.valuesPaths[1]

## Assert table — rendered `k8sTest/templates/deployment.yaml`

| field                   | PASS                    | FAIL means                                    |
|-------------------------|-------------------------|-----------------------------------------------|
| `metadata.name`         | `cds131005-k8s-default` | `<no value>` -> default file not discovered   |
| `spec.replicas`         | `3`                     | `<no value>` -> default file not discovered   |
| `image`                 | `nginx:1.25`            | `<no value>` -> default file not discovered   |
| `tier`                  | `qa`                    | `default-tier` -> precedence inverted         |
| `containerPort`         | `256`                   | `512`/`1024` -> not last-declared-wins        |
| `owner`                 | the service name        | `<+service.name>` -> not in `toTemplate`      |
| `templates-dir-default` | `<no value>`            | `LEAK-DETECTED` -> CDS-131003 leak present    |

`metadata.name` / `replicas` / `image` are the only real proof of discovery:
those keys exist in NO other values file.

## Overrides assert (CDS-131003)

`serviceOutput.manifests.overrides` must contain EXACTLY the two declared files:

    /harness/m2/k8sValues/values-a.yaml
    /harness/m3/k8sValues/values-b.yaml

It must NOT contain `k8sTest/values.yaml` or `k8sTest/templates/values.yaml`,
even though the fetch plugin reads and outputs both.
