# T15727 execution log — real cluster (cd-play / k8-traffic-shift-poc)

## Status: SKIPPED (not independently executed)

Same steps, same k8s-native provider, same values as `rolling-k8snative-
config-inherit/` (T15724, confirmed PASS — see that folder's
EXECUTION_LOG.md). Legacy T15727 only differs from T15724 by testing that
the Config/Inherit values come from **runtime input** (input sets) rather
than being fixed in the pipeline — a DSL feature this suite's Unified
pipeline YAML has no equivalent for (documented in `../README.md`). Running
this ticket would just re-exercise the identical Rolling + k8s-native
Config/Inherit path already proven real end-to-end under T15724, against the
same `trafficshift-route` HTTPRoute, with no new evidence gained.

Decision: skip real execution, record as a duplicate-coverage case rather
than a blocked or failed one.

**Next**: `bluegreen-k8snative-checkrouting` (T15816) or
`canary-k8snative-checkrouting` (T15818) — both not yet attempted.
