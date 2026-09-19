#!/usr/bin/env bash
# build_dmg.sh - package an already-built Dimly.app (see build_dimly.sh) into
# a drag-to-install DMG. Optional convenience step; not required to run the app.

set -euo pipefail

APP_NAME="Dimly"
DMG_NAME="Dimly"
DMG_VOLUME_NAME="Dimly Installer (Community Build)"
README_SOURCE="README.md"
DOCS_SOURCE="docs"
APPLICATIONS_ALIAS_NAME="Applications"
INSTALL_NOTES_FILENAME="Install Instructions.txt"
VERBOSE="${VERBOSE:-0}"
COLOR="${COLOR:-1}"

if [[ -t 1 && -z "${NO_COLOR:-}" && "$COLOR" != "0" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
fi

log_header() { echo "${C_BOLD}$*${C_RESET}"; }
log_step() { echo "${C_BLUE}›${C_RESET} $*"; }
log_item() { echo "  - $*"; }
log_dim() { echo "${C_DIM}$*${C_RESET}"; }
log_warn() { echo "${C_YELLOW}⚠${C_RESET} $*"; }
log_error() { echo "${C_RED}✖${C_RESET} $*" >&2; }
log_success() { echo "${C_GREEN}✔${C_RESET} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE_PATH="$PROJECT_ROOT/${APP_NAME}.app"
DMG_PATH="$PROJECT_ROOT/${DMG_NAME}.dmg"

if ! command -v hdiutil >/dev/null 2>&1; then
  log_error "hdiutil is required to build the DMG."
  exit 1
fi

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  log_error "Expected app bundle at $APP_BUNDLE_PATH"
  log_item "Run ./scripts/build_dimly.sh first."
  exit 1
fi

log_header "${APP_NAME} DMG (community build)"
log_warn "Using existing ${APP_NAME}.app at ${APP_BUNDLE_PATH}; it will not be rebuilt."

if [[ ! -f "$PROJECT_ROOT/$README_SOURCE" ]]; then
  log_error "README not found at $PROJECT_ROOT/$README_SOURCE"
  exit 1
fi

if [[ ! -d "$PROJECT_ROOT/$DOCS_SOURCE" ]]; then
  log_error "Docs folder not found at $PROJECT_ROOT/$DOCS_SOURCE"
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dimly-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

log_step "Preparing DMG staging directory"
if [[ "$VERBOSE" == "1" ]]; then
  log_item "$STAGING_DIR"
fi
cp -R "$APP_BUNDLE_PATH" "$STAGING_DIR/${APP_NAME}.app"
cp "$PROJECT_ROOT/$README_SOURCE" "$STAGING_DIR/README.md"
cp -R "$PROJECT_ROOT/$DOCS_SOURCE" "$STAGING_DIR/docs"
cat <<EON >"$STAGING_DIR/$INSTALL_NOTES_FILENAME"
This is a community build - compiled locally, not built or signed by
Jan Feuerbacher. It won't auto-update. Grab official releases at
https://github.com/Punshnut/macos-dimly/releases

1. Drag ${APP_NAME}.app to the ${APPLICATIONS_ALIAS_NAME} shortcut to install.
2. Launch it from your Applications folder.
3. If macOS blocks the first launch, open System Settings → Privacy & Security and click “Open Anyway.”
EON

log_step "Creating Applications shortcut"
ln -s /Applications "$STAGING_DIR/$APPLICATIONS_ALIAS_NAME"

log_step "Creating ${DMG_NAME}.dmg"
rm -f "$DMG_PATH"
hdiutil create \
  -fs HFS+ \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

log_success "DMG created"
log_item "Path: $DMG_PATH"
