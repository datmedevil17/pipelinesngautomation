# CDS-136417 repro

K8s Apply fails: `Secret ... illegal base64 data at input byte 0`.

- Git manifest path: `CDS-136417-repro/manifests`
- Service: K8s, artifact = ACR with Azure connector (Service Principal + client secret key).
- Feature flag `CDS_USE_SWEEPING_OUTPUT_SECRET_FUNCTOR_FOR_IMAGE_PULL_SECRET` = OFF.
- Unified stage, K8s Canary/Rolling/Apply step.

Expected on bug: rendered `harness-consolidated-manifest.yaml` has
`.dockerconfigjson: ${dockerConfigJsonSecretFunc.create(...)}` and the apply fails.
