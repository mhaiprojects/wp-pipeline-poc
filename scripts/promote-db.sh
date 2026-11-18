#!/usr/bin/env bash
# Promote a WordPress database from one pipeline environment to another.
# Usage: promote-db.sh <from-env> <to-env>
#   from/to are: dev, staging, or prod
#
# Normally in a real workflow, code flows up (dev -> staging -> prod) and
# databases flow down (prod -> staging -> dev) so developers can debug with
# a sanitized copy of production data. This script can run in either
# direction; the PoC uses it to demonstrate URL search-replace when
# promoting content upward as well.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline-common.sh
source "$SCRIPT_DIR/pipeline-common.sh"

if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
  echo "Usage: $0 <from-env> <to-env>" >&2
  exit 2
fi

FROM="$1"
TO="$2"
pipeline_require_env "$FROM"
pipeline_require_env "$TO"

if [[ "$FROM" == "$TO" ]]; then
  echo "From and to environments must be different." >&2
  exit 2
fi

FROM_DIR="$(pipeline_site_dir "$FROM")"
TO_DIR="$(pipeline_site_dir "$TO")"
FROM_URL="$(pipeline_site_url "$FROM")"
TO_URL="$(pipeline_site_url "$TO")"
TS="$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$PIPELINE_BACKUP_DIR"

EXPORT_FILE="$PIPELINE_BACKUP_DIR/${FROM}-to-${TO}-${TS}.sql.gz"
TARGET_BACKUP="$PIPELINE_BACKUP_DIR/${TO}-before-import-${TS}.sql.gz"
LOG_FILE="$PIPELINE_LOG_DIR/promote-db-${FROM}-to-${TO}.log"
mkdir -p "$PIPELINE_LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

pipeline_log "Promoting database $FROM -> $TO"
pipeline_log "URL replace: $FROM_URL -> $TO_URL"

pipeline_log "Backing up destination $TO to $TARGET_BACKUP"
(cd "$TO_DIR" && ddev export-db --gzip=true --file="$TARGET_BACKUP")

pipeline_log "Exporting $FROM to $EXPORT_FILE"
(cd "$FROM_DIR" && ddev export-db --gzip=true --file="$EXPORT_FILE")

pipeline_log "Importing into $TO"
(cd "$TO_DIR" && ddev import-db --file="$EXPORT_FILE")

pipeline_log "search-replace dry-run (https)"
(cd "$TO_DIR" && ddev wp search-replace "$FROM_URL" "$TO_URL" --all-tables --dry-run)

# Also report http variants if any exist.
FROM_HTTP="${FROM_URL/https:/http:}"
TO_HTTP="${TO_URL/https:/http:}"
pipeline_log "search-replace dry-run (http)"
(cd "$TO_DIR" && ddev wp search-replace "$FROM_HTTP" "$TO_HTTP" --all-tables --dry-run)

pipeline_log "search-replace live (https)"
(cd "$TO_DIR" && ddev wp search-replace "$FROM_URL" "$TO_URL" --all-tables)

pipeline_log "search-replace live (http)"
(cd "$TO_DIR" && ddev wp search-replace "$FROM_HTTP" "$TO_HTTP" --all-tables)

(cd "$TO_DIR" && ddev wp rewrite flush && ddev wp cache flush)

# A database import overwrites options (including pipeline_deployed_*).
# Plugin files and the on-disk ref/tag files are untouched; restore options
# from those files so verify.sh still reports the currently deployed code.
if [[ -d "$TO_DIR/wp-content/plugins/pipeline-demo" ]]; then
  pipeline_log "Re-activating pipeline-demo on $TO after DB import"
  (cd "$TO_DIR" && ddev wp plugin activate pipeline-demo)
fi
if [[ -f "$TO_DIR/wp-content/.pipeline-deployed-ref" ]]; then
  REF_SAVED="$(cat "$TO_DIR/wp-content/.pipeline-deployed-ref")"
  (cd "$TO_DIR" && ddev wp option update pipeline_deployed_ref "$REF_SAVED")
fi
if [[ -f "$TO_DIR/wp-content/.pipeline-deployed-sha" ]]; then
  SHA_SAVED="$(cat "$TO_DIR/wp-content/.pipeline-deployed-sha")"
  (cd "$TO_DIR" && ddev wp option update pipeline_deployed_sha "$SHA_SAVED")
fi

pipeline_log "After promotion, $TO siteurl=$(cd "$TO_DIR" && ddev wp option get siteurl) home=$(cd "$TO_DIR" && ddev wp option get home)"
pipeline_log "Database promotion $FROM -> $TO complete"
