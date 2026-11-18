#!/usr/bin/env bash
# Deploy a tagged release into the production DDEV site.
# Usage: deploy-prod.sh <tag>
# Production receives code only via tagged releases, never a raw branch tip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline-common.sh
source "$SCRIPT_DIR/pipeline-common.sh"

if [[ "${1:-}" == "" ]]; then
  echo "Usage: $0 <tag>" >&2
  echo "Example: $0 v0.1.0" >&2
  exit 2
fi

TAG="$1"

if [[ "$TAG" != v* ]]; then
  echo "Expected a version tag like v0.1.0 (got: $TAG)" >&2
  exit 2
fi

if ! git --git-dir="$PIPELINE_BARE" rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "Tag not found in origin.git: $TAG" >&2
  echo "Create it on main and push it to the bare remote first." >&2
  exit 1
fi

"$SCRIPT_DIR/deploy-env.sh" prod "$TAG"
