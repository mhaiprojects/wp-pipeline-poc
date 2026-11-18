#!/usr/bin/env bash
# Shared paths, config loader, and helpers for the wp-pipeline PoC.
# shellcheck disable=SC2034

_PIPELINE_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Built-in default for PIPELINE_ROOT: the directory that contains scripts/,
# and typically origin.git, wp-dev, wp-staging, and wp-prod.
# Also used to locate pipeline.ini when PIPELINE_ROOT is not yet set.
# Override PIPELINE_ROOT when the site trees live outside this checkout:
#   export PIPELINE_ROOT="$HOME/wp-pipeline"
_PIPELINE_ROOT_DEFAULT="$(cd "$_PIPELINE_COMMON_DIR/.." && pwd)"
_PIPELINE_ROOT_FOR_CONFIG="${PIPELINE_ROOT:-$_PIPELINE_ROOT_DEFAULT}"

# ---------------------------------------------------------------------------
# Config loader
#
# Looks for ${PIPELINE_CONFIG:-<repo root>/pipeline.ini}.
# If that file is missing and PIPELINE_CONFIG was not set, a .env file in
# the same directory (KEY=VALUE) is accepted as a fallback.
# Precedence: existing environment variables > config file > built-in defaults.
# Values are assigned literally (no eval, no command or variable expansion).
# ---------------------------------------------------------------------------

# Set $1 to $2 only if $1 is unset. An empty-but-set environment variable wins.
pipeline_set_if_unset() {
  local __var="$1"
  local __val="$2"
  if [[ -z "${!__var+x}" ]]; then
    printf -v "$__var" '%s' "$__val"
  fi
}

pipeline_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

pipeline_unquote() {
  local val="$1"
  if [[ ${#val} -ge 2 && "${val:0:1}" == '"' && "${val: -1}" == '"' ]]; then
    val="${val:1:${#val}-2}"
  elif [[ ${#val} -ge 2 && "${val:0:1}" == "'" && "${val: -1}" == "'" ]]; then
    val="${val:1:${#val}-2}"
  fi
  printf '%s' "$val"
}

# Map an INI section + key to a shell variable name. Prints the name, or
# returns 1 if the key is not recognised.
pipeline_ini_varname() {
  local section="$1"
  local key="$2"
  local var=""
  local prefix=""
  case "$section" in
    pipeline)
      case "$key" in
        root) var=PIPELINE_ROOT ;;
        bare) var=PIPELINE_BARE ;;
        log_dir) var=PIPELINE_LOG_DIR ;;
        backup_dir) var=PIPELINE_BACKUP_DIR ;;
        admin_user) var=WP_ADMIN_USER ;;
        admin_password) var=WP_ADMIN_PASS ;;
        admin_email) var=WP_ADMIN_EMAIL ;;
        *) return 1 ;;
      esac
      ;;
    dev|staging|prod)
      prefix="${section^^}"
      case "$key" in
        path) var="${prefix}_PATH" ;;
        url) var="${prefix}_URL" ;;
        db_name) var="${prefix}_DB_NAME" ;;
        db_user) var="${prefix}_DB_USER" ;;
        db_password) var="${prefix}_DB_PASSWORD" ;;
        db_host) var="${prefix}_DB_HOST" ;;
        ssh_host) var="${prefix}_SSH_HOST" ;;
        ssh_user) var="${prefix}_SSH_USER" ;;
        deploy_path) var="${prefix}_DEPLOY_PATH" ;;
        *) return 1 ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
  printf '%s' "$var"
}

# True if $1 is a known config variable we are willing to set from a file.
pipeline_known_var() {
  local var="$1"
  case "$var" in
    PIPELINE_ROOT|PIPELINE_BARE|PIPELINE_LOG_DIR|PIPELINE_BACKUP_DIR) ;;
    WP_ADMIN_USER|WP_ADMIN_PASS|WP_ADMIN_EMAIL) ;;
    DEV_PATH|DEV_URL|DEV_DB_NAME|DEV_DB_USER|DEV_DB_PASSWORD|DEV_DB_HOST|DEV_SSH_HOST|DEV_SSH_USER|DEV_DEPLOY_PATH) ;;
    STAGING_PATH|STAGING_URL|STAGING_DB_NAME|STAGING_DB_USER|STAGING_DB_PASSWORD|STAGING_DB_HOST|STAGING_SSH_HOST|STAGING_SSH_USER|STAGING_DEPLOY_PATH) ;;
    PROD_PATH|PROD_URL|PROD_DB_NAME|PROD_DB_USER|PROD_DB_PASSWORD|PROD_DB_HOST|PROD_SSH_HOST|PROD_SSH_USER|PROD_DEPLOY_PATH) ;;
    *) return 1 ;;
  esac
  return 0
}

pipeline_load_ini_file() {
  local file="$1"
  local line section="" key value varname
  local lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    line="$(pipeline_trim "$line")"
    [[ -z "$line" || "$line" == \#* || "$line" == \;* ]] && continue
    if [[ "$line" =~ ^\[([A-Za-z][A-Za-z0-9_]*)\]$ ]]; then
      section="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ "$line" =~ ^([A-Za-z][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="$(pipeline_unquote "$(pipeline_trim "${BASH_REMATCH[2]}")")"
      if [[ -z "$section" ]]; then
        echo "pipeline-common: $file:$lineno: key '$key' appears before any [section]; ignored" >&2
        continue
      fi
      if ! varname="$(pipeline_ini_varname "$section" "$key")"; then
        echo "pipeline-common: $file:$lineno: unknown key [$section] $key; ignored" >&2
        continue
      fi
      # Skip empty values so built-in defaults still apply.
      [[ -z "$value" ]] && continue
      pipeline_set_if_unset "$varname" "$value"
      continue
    fi
    echo "pipeline-common: $file:$lineno: skipping unrecognised line" >&2
  done < "$file"
}

pipeline_load_env_file() {
  local file="$1"
  local line key value
  local lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    line="$(pipeline_trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^export[[:space:]]+(.*)$ ]]; then
      line="$(pipeline_trim "${BASH_REMATCH[1]}")"
    fi
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="$(pipeline_unquote "$(pipeline_trim "${BASH_REMATCH[2]}")")"
      if ! pipeline_known_var "$key"; then
        echo "pipeline-common: $file:$lineno: unknown key $key; ignored" >&2
        continue
      fi
      [[ -z "$value" ]] && continue
      pipeline_set_if_unset "$key" "$value"
      continue
    fi
    echo "pipeline-common: $file:$lineno: skipping unrecognised line" >&2
  done < "$file"
}

pipeline_load_config_file() {
  local file="$1"
  local base
  base="$(basename "$file")"
  if [[ "$base" == ".env" || "$base" == *.env ]]; then
    pipeline_load_env_file "$file"
  else
    pipeline_load_ini_file "$file"
  fi
}

if [[ -z "${PIPELINE_CONFIG+x}" ]]; then
  PIPELINE_CONFIG="$_PIPELINE_ROOT_FOR_CONFIG/pipeline.ini"
fi

if [[ -f "$PIPELINE_CONFIG" ]]; then
  pipeline_load_config_file "$PIPELINE_CONFIG"
elif [[ "$PIPELINE_CONFIG" == "$_PIPELINE_ROOT_FOR_CONFIG/pipeline.ini" && -f "$_PIPELINE_ROOT_FOR_CONFIG/.env" ]]; then
  pipeline_load_config_file "$_PIPELINE_ROOT_FOR_CONFIG/.env"
fi

# Built-in defaults. Environment variables and config-file values already
# assigned above are left unchanged (${VAR:-default}).
PIPELINE_ROOT="${PIPELINE_ROOT:-$_PIPELINE_ROOT_DEFAULT}"
PIPELINE_BARE="${PIPELINE_BARE:-$PIPELINE_ROOT/origin.git}"
PIPELINE_LOG_DIR="${PIPELINE_LOG_DIR:-$PIPELINE_ROOT/logs}"
PIPELINE_BACKUP_DIR="${PIPELINE_BACKUP_DIR:-$PIPELINE_ROOT/backups}"

DEV_PATH="${DEV_PATH:-$PIPELINE_ROOT/wp-dev}"
STAGING_PATH="${STAGING_PATH:-$PIPELINE_ROOT/wp-staging}"
PROD_PATH="${PROD_PATH:-$PIPELINE_ROOT/wp-prod}"

DEV_URL="${DEV_URL:-https://wp-dev.ddev.site}"
STAGING_URL="${STAGING_URL:-https://wp-staging.ddev.site}"
PROD_URL="${PROD_URL:-https://wp-prod.ddev.site}"

# Optional placeholders for a non-DDEV or remote setup. The current
# deploy, promote, and verify scripts talk to local DDEV projects and
# do not read these yet.
DEV_DB_NAME="${DEV_DB_NAME:-}"
DEV_DB_USER="${DEV_DB_USER:-}"
DEV_DB_PASSWORD="${DEV_DB_PASSWORD:-}"
DEV_DB_HOST="${DEV_DB_HOST:-}"
DEV_SSH_HOST="${DEV_SSH_HOST:-}"
DEV_SSH_USER="${DEV_SSH_USER:-}"
DEV_DEPLOY_PATH="${DEV_DEPLOY_PATH:-}"

STAGING_DB_NAME="${STAGING_DB_NAME:-}"
STAGING_DB_USER="${STAGING_DB_USER:-}"
STAGING_DB_PASSWORD="${STAGING_DB_PASSWORD:-}"
STAGING_DB_HOST="${STAGING_DB_HOST:-}"
STAGING_SSH_HOST="${STAGING_SSH_HOST:-}"
STAGING_SSH_USER="${STAGING_SSH_USER:-}"
STAGING_DEPLOY_PATH="${STAGING_DEPLOY_PATH:-}"

PROD_DB_NAME="${PROD_DB_NAME:-}"
PROD_DB_USER="${PROD_DB_USER:-}"
PROD_DB_PASSWORD="${PROD_DB_PASSWORD:-}"
PROD_DB_HOST="${PROD_DB_HOST:-}"
PROD_SSH_HOST="${PROD_SSH_HOST:-}"
PROD_SSH_USER="${PROD_SSH_USER:-}"
PROD_DEPLOY_PATH="${PROD_DEPLOY_PATH:-}"

WP_ADMIN_USER="${WP_ADMIN_USER:-}"
WP_ADMIN_PASS="${WP_ADMIN_PASS:-}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:-}"

pipeline_site_dir() {
  local env="$1"
  case "$env" in
    dev) printf '%s\n' "$DEV_PATH" ;;
    staging) printf '%s\n' "$STAGING_PATH" ;;
    prod) printf '%s\n' "$PROD_PATH" ;;
    *) echo "Unknown environment: $env" >&2; return 1 ;;
  esac
}

pipeline_site_url() {
  local env="$1"
  case "$env" in
    dev) printf '%s\n' "$DEV_URL" ;;
    staging) printf '%s\n' "$STAGING_URL" ;;
    prod) printf '%s\n' "$PROD_URL" ;;
    *) echo "Unknown environment: $env" >&2; return 1 ;;
  esac
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
