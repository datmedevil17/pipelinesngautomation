# T15723 execution log — real cluster (cd-play / k8-traffic-shift-poc)

**2026-09-24** — `pipeline_03d5`, service `service_kubernetes_8f4a`, env
`environment_env_a193`, infra namespace `traffic-shift-demo`, connector
`connector_K8sCluster_a7ec`.

## Result: PASS (run 2, after a release_number fix)

### Attempt 1 — false-positive success

Set `trConfig.release_number: 6` (current run's own number, checked via
`kubectl get secrets -n traffic-shift-demo | grep harness.release`) and
`trInherit.release_number: 5` (N-1, per the rule documented at the time in
`../rolling-istio-config-inherit/EXECUTION_LOG.md`). Result:

```
[WARNING] There was not any information in release history regarding
previous traffic shift execution on which to make an update. Skipping
traffic shift resource update.
[INFO] K8s Traffic Shift execution successfully finished
```

Reports success but did nothing — release `5` had no traffic-shift tracking
data (it was created by an unrelated pipeline run — T15722's failed
attempts / the isolation-test pipeline — that never reached a
`config_type: new` step). This disproved the N-1 rule; see the correction
in `../rolling-istio-config-inherit/EXECUTION_LOG.md`.

### Attempt 2 — real pass

Set **both** `trConfig.release_number` and `trInherit.release_number` to
`6` (the same value — this run's own release number). Result:

```
[INFO] Found 1 traffic shift resources in release
[INFO] Checking routes for resource VirtualService/trafficshift-vs
[INFO] For route [route1] destination [trafficshift-v1] weight will be normalized from [100] to [0].
[INFO] For route [route1] destination [trafficshift-v2] weight will be normalized from [0] to [100].
[INFO] virtualservice.networking.istio.io/trafficshift-vs patched
[INFO] Patch applied successfully for resource traffic-shift-demo/VirtualService/trafficshift-vs
```

Verified against real cluster state:

```
$ kubectl get vs trafficshift-vs -n traffic-shift-demo -o jsonpath='{.spec.http[0].route}'
[{"destination":{"host":"trafficshift-v1"}},{"destination":{"host":"trafficshift-v2"},"weight":100}]
```

`trafficshift-v1`'s weight field is dropped entirely (the plugin's encoding
for a 0-weight destination) and `trafficshift-v2` is `weight: 100` — matches
the intended v1=0/v2=100 shift exactly.

## Status: PASS — T15723 real end-to-end confirmed

Note: this port uses **hand-edited literals per run** as the substitute for
the legacy suite's `<+input>` + input-set mechanism (no equivalent exists in
this DSL — see `../README.md` "Runtime-input note"). Run 2 above should be
treated as "input set A" (v1=100→0 / v2=0→100). To exercise "input set B",
edit `trConfig`'s destination weights/`resource_name`/`hosts` and re-run with
a fresh `release_number` (check `kubectl get secrets` again first).
