#!/usr/bin/env bash
# Verify the pipeline-demo marker and plugin state.
# Usage: verify.sh [dev|staging|prod|all] [expected-release]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline-common.sh
source "$SCRIPT_DIR/pipeline-common.sh"

TARGET="${1:-all}"
EXPECTED="${2:-}"

verify_one() {
  local env="$1"
  local url dir html code marker ref_file tag_file
  dir="$(pipeline_site_dir "$env")"
  url="$(pipeline_site_url "$env")"

  echo "======== $env ($url) ========"
  code="$(curl -sk -o /tmp/wp-pipeline-verify-$env.html -w '%{http_code}' "$url/")"
  html="$(cat /tmp/wp-pipeline-verify-$env.html)"
  marker="$(printf '%s\n' "$html" | grep -o 'PIPELINE_DEMO[^<]*' | head -n 1 || true)"
  echo "HTTP $code"
  echo "Marker: ${marker:-<none>}"

  if [[ -n "$EXPECTED" ]]; then
    if printf '%s\n' "$marker" | grep -q "PIPELINE_DEMO $EXPECTED"; then
      echo "Expected release $EXPECTED: OK"
    else
      echo "Expected release $EXPECTED: MISSING" >&2
      return 1
    fi
  fi

  (cd "$dir" && ddev wp plugin list --name=pipeline-demo --format=table || true)
  (cd "$dir" && ddev wp option get siteurl || true)
  (cd "$dir" && ddev wp option get pipeline_deployed_ref 2>/dev/null || echo "(not set; expected on dev, which is not a deploy target)")

  ref_file="$dir/wp-content/.pipeline-deployed-ref"
  tag_file="$dir/wp-content/.pipeline-deployed-tag"
  if [[ -f "$ref_file" ]]; then
    echo "Deployed ref file: $(cat "$ref_file")"
  fi
  if [[ -f "$tag_file" ]]; then
    echo "Deployed tag file: $(cat "$tag_file")"
  fi
  echo
}

ec=0
if [[ "$TARGET" == "all" ]]; then
  for env in dev staging prod; do
    verify_one "$env" || ec=1
  done
else
  pipeline_require_env "$TARGET"
  verify_one "$TARGET" || ec=1
fi
exit $ec
