#!/bin/bash
# Calls the exact REST endpoint the S3 artifact "file paths" dropdown calls in
# the UI (GET /ng/api/buckets/s3/getFilePaths), then asserts every returned
# entry has a non-null buildDetails.number.
#
# Usage:
#   ./getfilepaths.sh <account-id> <org-id> <project-id> <connector-ref> <bucket> <region> <token>
#
# <token> is the raw JWT (no "Bearer " prefix) copied from the browser's
# `token` cookie while logged into that account. It expires -- generate a
# fresh one right before running, never commit one.

set -eu

ACCOUNT_ID="$1"
ORG_ID="$2"
PROJECT_ID="$3"
CONNECTOR_REF="$4"
BUCKET="$5"
REGION="$6"
TOKEN="$7"

RESP=$(curl -s --url "https://qa.harness.io/gateway/ng/api/buckets/s3/getFilePaths?routingId=${ACCOUNT_ID}&accountIdentifier=${ACCOUNT_ID}&orgIdentifier=${ORG_ID}&projectIdentifier=${PROJECT_ID}&connectorRef=${CONNECTOR_REF}&region=${REGION}&bucketName=${BUCKET}" \
  -H 'accept: */*' \
  -H 'content-type: application/json' \
  -H "harness-account: ${ACCOUNT_ID}" \
  -b "token=${TOKEN}")

echo "$RESP" | python3 -c "
import json, sys
d = json.load(sys.stdin)
status = d.get('status')
data = d.get('data') or []
print(f'status={status} entries={len(data)}')
if status != 'SUCCESS':
    print('FAIL: status was not SUCCESS')
    sys.exit(1)
if not data:
    print('FAIL: no entries returned -- check bucket/connector/region')
    sys.exit(1)
nulls = [e for e in data if e.get('buildDetails', {}).get('number') is None]
if nulls:
    print(f'FAIL (CDS-132701 bug reproduced): {len(nulls)}/{len(data)} entries have buildDetails.number == null')
    print(json.dumps(data[0], indent=2))
    sys.exit(1)
print(f'PASS: all {len(data)} entries have a populated buildDetails.number')
print(json.dumps(data[0], indent=2))
"
