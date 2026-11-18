#!/usr/bin/env bash
# Shared paths and helpers for the wp-pipeline PoC.
# shellcheck disable=SC2034

_PIPELINE_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PIPELINE_ROOT is the directory that contains scripts/, and typically
# origin.git, wp-dev, wp-staging, and wp-prod.
# Override this when the site trees live outside this checkout, for example:
#   export PIPELINE_ROOT="$HOME/wp-pipeline"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "$_PIPELINE_COMMON_DIR/.." && pwd)}"
PIPELINE_BARE="${PIPELINE_BARE:-$PIPELINE_ROOT/origin.git}"
PIPELINE_LOG_DIR="${PIPELINE_LOG_DIR:-$PIPELINE_ROOT/logs}"
PIPELINE_BACKUP_DIR="${PIPELINE_BACKUP_DIR:-$PIPELINE_ROOT/backups}"

pipeline_site_dir() {
  local env="$1"
  case "$env" in
    dev|staging|prod) echo "$PIPELINE_ROOT/wp-$env" ;;
    *) echo "Unknown environment: $env" >&2; return 1 ;;
  esac
}

pipeline_site_url() {
  local env="$1"
  echo "https://wp-${env}.ddev.site"
}

pipeline_require_env() {
  local env="$1"
  case "$env" in
    dev|staging|prod) ;;
    *) echo "Environment must be dev, staging, or prod (got: $env)" >&2; return 1 ;;
  esac
}

pipeline_log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*"
}
