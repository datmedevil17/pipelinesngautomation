#!/bin/sh
# CDS-131005 Run 1 asserts -- default values file with NO Harness expression.
#
#   ./assert.sh serverless <rendered serverlessUnified.yaml>
#   ./assert.sh k8s        <rendered deployment.yaml>
#
# Run this as a Run step AFTER the templating step, pointing at the rendered
# manifest. Exits non-zero if any assert fails, so the step goes red on its own.
#
# Assert style note: every check is "expected vs actual" via chk(). No bare
# `grep -q X && FAIL` -- that idiom is what produced a false FAIL in run R18.

# POSIX sh only -- no pipefail, no [[ ]] -- so this runs under busybox/alpine sh too.
set -u

mode="${1:?usage: assert.sh <serverless|k8s> [rendered-manifest]}"
manifest="${2:-}"

# The manifest path is the one thing you cannot know in advance -- the workspace
# layout depends on the manifest identifier. So if no path is given, find it.
if [ -z "$manifest" ]; then
  case "$mode" in
    serverless) want=serverlessUnified.yaml ;;
    k8s)        want=deployment.yaml ;;
    *)          echo "FATAL: mode must be 'serverless' or 'k8s', got: $mode"; exit 2 ;;
  esac

  root="${HARNESS_WORKSPACE:-/harness}"
  echo "No path given -- searching for $want under $root ..."
  manifest=$(find "$root" -type f -name "$want" -path '*noBaitTest*' 2>/dev/null | head -1)

  if [ -z "$manifest" ]; then
    echo "FATAL: could not find $want under $root."
    echo "The workspace looks like this -- pass the right path as the 2nd argument:"
    find "$root" -maxdepth 4 -name '*.yaml' 2>/dev/null | head -40 | sed 's/^/    /'
    exit 2
  fi
  echo "found: $manifest"
fi

if [ ! -f "$manifest" ]; then
  echo "FATAL: rendered manifest not found: $manifest"
  exit 2
fi

fail=0

# chk <label> <want> <got>
chk() {
  if [ "$3" = "$2" ]; then
    printf '  PASS  %-24s %s\n' "$1" "$3"
  else
    printf '  FAIL  %-24s got=[%s] want=[%s]\n' "$1" "$3" "$2"
    fail=1
  fi
}

# val <key> -- first value for a key at any indentation. The optional leading "- "
# matters: deployment.yaml writes the port as a list item ("- containerPort: 256").
val() { sed -n "s/^[[:space:]]*-\{0,1\}[[:space:]]*$1:[[:space:]]*//p" "$manifest" | head -1 | tr -d "'\"" ; }

echo "=============================================================="
echo " CDS-131005 Run 1 -- $mode"
echo " manifest: $manifest"
echo "=============================================================="
echo
echo "----- rendered manifest -----"
cat "$manifest"
echo
echo "----- asserts -----"

case "$mode" in
serverless)
  # Only-in-default keys: these exist in NO other values file, so they are the
  # only real proof that the undeclared values.yaml was discovered and applied.
  chk "service (default-only)"    "cds131005-default" "$(val service)"
  chk "region (default-only)"     "us-east-1"         "$(val region)"
  # Precedence: declared must beat default, last declared must win.
  chk "stage (declared beats)"    "qa"                "$(val stage)"
  chk "memorySize (last wins)"    "256"               "$(val memorySize)"
  chk "frameworkVersion (sanity)" "3.39.0"            "$(val frameworkVersion)"
  ;;
k8s)
  chk "name (default-only)"       "cds131005-k8s-default" "$(val name)"
  chk "replicas (default-only)"   "3"                     "$(val replicas)"
  chk "image (default-only)"      "nginx:1.25"            "$(val image)"
  chk "owner (default-only)"      "plain-literal-no-expression" "$(val owner)"
  chk "tier (declared beats)"     "qa"                    "$(val tier)"
  chk "containerPort (last wins)" "256"                   "$(val containerPort)"
  # CDS-131003 leak canary: templates/values.yaml must NOT be applied, so this
  # key stays unset and go-template renders it as the literal "<no value>".
  chk "templates-dir-default"     "<no value>"            "$(val templates-dir-default)"
  ;;
*)
  echo "FATAL: mode must be 'serverless' or 'k8s', got: $mode"
  exit 2
  ;;
esac

echo
echo "----- unresolved-render guard -----"
# An undiscovered default file shows up as "<no value>" or a surviving "{{ }}".
# templates-dir-default is the ONE key legitimately allowed to be "<no value>".
stray_novalue=$(grep -n '<no value>' "$manifest" | grep -v 'templates-dir-default' || true)
stray_tmpl=$(grep -n '{{' "$manifest" || true)

if [ -n "$stray_novalue" ]; then
  echo "  FAIL  unexpected <no value>:"; echo "$stray_novalue" | sed 's/^/          /'; fail=1
else
  echo "  PASS  no unexpected <no value>"
fi

if [ -n "$stray_tmpl" ]; then
  echo "  FAIL  unrendered go-template left:"; echo "$stray_tmpl" | sed 's/^/          /'; fail=1
else
  echo "  PASS  no unrendered go-template"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "RESULT: PASS -- default values file was discovered WITHOUT a Harness expression."
  echo "        Discovery is disk-based. CDS-131005 holds for the real customer case."
else
  echo "RESULT: FAIL -- see the lines above."
  echo "        If the default-only keys are empty, the undeclared values.yaml was"
  echo "        never applied => discovery depended on the fetch-stage bait."
fi
exit "$fail"
