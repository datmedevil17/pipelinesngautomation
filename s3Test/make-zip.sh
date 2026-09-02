#!/bin/sh
# Builds the S3 artifact for CDS-131005 Run 7 and prints what to upload.
#
# The zip must be laid out so that, after extraction, values.yaml is a SIBLING of
# serverlessUnified.yaml -- that adjacency is the whole point of the run. Zipping
# from inside serverless/ puts every file at the archive root, which is the layout
# that survives extraction regardless of how the store strips leading directories.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out="$here/s3Test.zip"
rm -f "$out"
cd "$here/serverless"
zip -r "$out" \
  serverlessUnified.yaml \
  values.yaml \
  values-a.yaml \
  values-b.yaml \
  package.json
cd "$here"
echo
echo "built $out"
echo "contents:"
unzip -l "$out"
echo
echo "Upload it, then point the service's manifest at the S3 store:"
echo "  store:  S3 (or Amazon S3)"
echo "  bucket / region / key: wherever you uploaded s3Test.zip"
echo "  paths:              .                      <- archive root, NOT s3Test/serverless"
echo "  configOverridePath: serverlessUnified.yaml"
echo "  values:             values-a.yaml"
echo "                      values-b.yaml"
echo
echo "values.yaml must NOT be declared -- it has to be discovered on disk."
