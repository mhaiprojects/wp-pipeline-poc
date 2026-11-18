#!/usr/bin/env bash
# Deploy a git ref from the local bare origin into staging or prod.
# Usage: deploy-env.sh <staging|prod> <ref>
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline-common.sh
source "$SCRIPT_DIR/pipeline-common.sh"

if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
  echo "Usage: $0 <staging|prod> <ref>" >&2
  exit 2
fi

ENV="$1"
REF="$2"

if [[ "$ENV" != "staging" && "$ENV" != "prod" ]]; then
  echo "Refusing to deploy directly into '$ENV'. Use staging or prod." >&2
  exit 2
fi

SITE="$(pipeline_site_dir "$ENV")"
PLUGIN_DEST="$SITE/wp-content/plugins/pipeline-demo"
LOG_FILE="$PIPELINE_LOG_DIR/deploy-${ENV}.log"
mkdir -p "$PIPELINE_LOG_DIR" "$SITE/wp-content/plugins"

exec > >(tee -a "$LOG_FILE") 2>&1

pipeline_log "Deploying ref '$REF' into $ENV ($SITE)"

if [[ ! -d "$PIPELINE_BARE" ]]; then
  echo "Bare repo not found: $PIPELINE_BARE" >&2
  exit 1
fi

if ! git --git-dir="$PIPELINE_BARE" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1; then
  echo "Ref not found in origin.git: $REF" >&2
  exit 1
fi

SHA="$(git --git-dir="$PIPELINE_BARE" rev-parse "$REF^{commit}")"
pipeline_log "Resolved $REF -> $SHA"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# git archive is used instead of checkout --work-tree so the bare repo HEAD
# is never moved, and staging/prod deploys cannot clobber each other.
git --git-dir="$PIPELINE_BARE" archive --format=tar "$REF" | tar -x -C "$TMP"

if [[ ! -d "$TMP/wp-content/plugins/pipeline-demo" ]]; then
  echo "Ref $REF does not contain wp-content/plugins/pipeline-demo" >&2
  exit 1
fi

rsync -a --delete "$TMP/wp-content/plugins/pipeline-demo/" "$PLUGIN_DEST/"

# Record what was deployed (untracked, environment-specific).
echo "$REF" > "$SITE/wp-content/.pipeline-deployed-ref"
echo "$SHA" > "$SITE/wp-content/.pipeline-deployed-sha"
if [[ "$ENV" == "prod" ]]; then
  echo "$REF" > "$SITE/wp-content/.pipeline-deployed-tag"
fi

cd "$SITE"
ddev wp plugin activate pipeline-demo
ddev wp option update pipeline_deployed_ref "$REF"
ddev wp option update pipeline_deployed_sha "$SHA"
ddev wp cache flush
ddev wp plugin list --name=pipeline-demo --format=table

pipeline_log "Deploy to $ENV complete: $REF ($SHA)"
