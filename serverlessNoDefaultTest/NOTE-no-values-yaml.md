# Deliberately NO `values.yaml` / `values.yml` in this folder

CDS-131005 makes the Serverless plugins probe the manifest directory for
`values.yaml` / `values.yml` and prepend whatever they find as the base values
layer. A file with either name here would silently become an extra layer and
this folder would stop testing the case it exists for: a service that ships no
default values file at all, which is what almost every existing service looks
like.

The declared file is therefore named `values-only.yaml`.

The present-default case lives in `serverlessDefaultTest/`. Keep the two cases
in different repo folders.
