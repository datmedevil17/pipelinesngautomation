# Group 6 -- delegate/task-level failure (not a missing-file failure)

`RenderingStep.handleK8AsyncFailureResponse` handles TWO different
failure shapes:

1. `StepStatusTaskResponseData` with `stepExecutionStatus: FAILURE` --
   the fetch plugin RAN, and reported a file-not-found. This is what
   groups 1-5's "missing" rows (A2, E2, ...) exercise.
2. `ErrorNotifyResponseData` -- the delegate TASK ITSELF errored out
   before the plugin could produce a normal response at all (git clone
   failed, connector auth failed, bad ref, etc.). None of groups 1-5
   can reach this branch, because their "failure" rows are always a
   clean, valid git fetch that simply doesn't find the declared file.

This group is built specifically to hit branch 2, and confirm the
delegate's own error text comes through the thrown
`ManifestCollectionException` intact (this is the review-round change:
`handleK8AsyncFailureResponse` was reverted from a status-object return
to a void method that throws, per Ivan's "discard these changes"
comments).

## Layout

    manifests/deployment.yaml   used only by the baseline row (F1)
    values/present.yaml         used only by the baseline row (F1)
    pipeline-group6.yaml
    README.md

F2/F3 don't need any repo-side fixture -- the "failure" is entirely in
the SERVICE's connector/branch config, not in file presence/absence.

## Service configuration

Baseline shape (F1). F2/F3 change ONE field each -- see the table below.

    service:
      name: svc-cds126515-group6
      identifier: svc_cds126515_group6
      serviceDefinition:
        type: Kubernetes
        spec:
          manifests:
            - manifest:
                identifier: k8s
                type: K8sManifest
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: account.cdautomationtest
                      gitFetchType: Branch
                      branch: main
                      paths:
                        - CDS-126515-test/group6-delegate-failure/manifests
                  valuesPaths:
                    - CDS-126515-test/group6-delegate-failure/values/present.yaml
                  optionalValuesYaml: false
                  skipResourceVersioning: false

Swap `connectorRef` if your GitHub connector to this repo has a
different id.

## How to run

1. Repo is already pushed -- fetches from git, not your working copy.
2. Create the service above.
3. Paste `pipeline-group6.yaml`, replace the `<YOUR_...>` placeholders.
4. For each row below: change the ONE field noted, run the pipeline,
   and read step 2's failure message from the step log (not just its
   pass/fail badge).

## Test matrix

| # | Change from baseline | Expected step 2 result | Predicted output / where to look |
|---|---|---|---|
| F1 | none (baseline) | PASS | Sanity check only -- confirms the service/connector/branch are all valid before you start breaking things in F2/F3. Step 3 shows the normally-rendered manifest. |
| F2 | `branch: this-branch-does-not-exist-cds126515` | **FAIL** | Step 2's failure message should be a **git/fetch-level error** (something like "reference not found" / "couldn't find remote ref" / "fatal: couldn't find remote ref"), NOT a generic "file not found" or "Step status response is null" message. This is the delegate task itself failing -- `ErrorNotifyResponseData` path. Confirms `handleFailureK8Response`'s `errorMessage` is surfaced verbatim in the thrown `ManifestCollectionException`, not swallowed or replaced with a generic string. |
| F3 | `connectorRef: account.doesNotExistCds126515` | **FAIL**, likely earlier than F2 | This may fail even before a delegate task is dispatched (`ManifestsStep.validateConnectors` throws `InvalidRequestException` with "Connectors with identifier(s) [...] not found" if the connector doesn't resolve at all) -- that's a DIFFERENT code path than `handleK8AsyncFailureResponse`, so treat this row as a secondary sanity check, not primary evidence for the review-round change. If it instead reaches the delegate and fails there (e.g. connector resolves but its credentials are stale/revoked), you're back in the `ErrorNotifyResponseData` path like F2. |

## Reading step 2's failure

The row that actually validates this session's `RenderingStep` change
is **F2**. Before the review-round revert, a K8-infra failure of this
kind was captured into an `AsyncChainExecutableResponse` with
`Status.FAILED` and a `FailureInfo` built from the response -- after
the revert, it's a straight `throw new ManifestCollectionException(...)`
carrying the delegate's `errorMessage`. Both should surface to the user
as a failed step with a readable message; the thing to actually check
is that the message TEXT is the delegate's real reason (branch/ref not
found), not a generic wrapper string like "Step status response is
null" or an empty message.

## If a row disagrees with its expectation

- F2 passing (deploy succeeds despite a nonexistent branch) means the
  fetch step silently no-op'd instead of failing -- serious regression,
  unrelated to `optionalValuesYaml` entirely.
- F2 failing but with an EMPTY or generic message (not naming the bad
  branch/ref) means `handleFailureK8Response` isn't propagating
  `ErrorNotifyResponseData.getErrorMessage()` into the exception
  correctly -- check `RenderingStep.handleFailureK8Response`.
