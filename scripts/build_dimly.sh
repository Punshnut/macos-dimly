#!/usr/bin/env bash
# build_dimly.sh - compile Dimly from source into a runnable, ad-hoc signed
# Dimly.app. This is the public, unsigned build path: no Developer ID
# certificate, no notarization, no Sparkle update feed. See
# docs/building.md for the full walkthrough.
#
# Usage: ./scripts/build_dimly.sh
# Override architectures with: ARCHES="arm64" ./scripts/build_dimly.sh

set -euo pipefail

APP_NAME="Dimly"
PRODUCT_NAME="dimly"
ICON_NAME="Dimly"
VERBOSE="${VERBOSE:-0}"
COLOR="${COLOR:-1}"
# Default to universal (arm64 + x86_64). Override with ARCHES="arm64" to target a single arch.
ARCHES=(${ARCHES:-arm64 x86_64})

XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"
export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

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

START_TIME="$(date +%s)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build/release"
APP_BUNDLE="$PROJECT_ROOT/${APP_NAME}.app"
INFO_PLIST_SOURCE="$PROJECT_ROOT/Resources/Info.plist"
ENTITLEMENTS="$PROJECT_ROOT/Dimly.entitlements"
PACKAGE_PATH="$PROJECT_ROOT"

ICON_BUNDLE="$PROJECT_ROOT/Resources/${ICON_NAME}.icon"
ICON_OUT_DIR="$PROJECT_ROOT/.derived/assetcatalog"
APP_RES="$APP_BUNDLE/Contents/Resources"
PLIST="$APP_BUNDLE/Contents/Info.plist"

SANDBOX_HOME="$PROJECT_ROOT/.sandbox-home"
mkdir -p "$SANDBOX_HOME"

if [[ ! -d "$XCODE_APP" ]]; then
  log_error "Xcode not found at $XCODE_APP."
  log_item "Install Xcode from the App Store (the full app, not just the Command Line Tools -"
  log_item "the app icon compiler used below needs it), then re-run this script."
  log_item "If Xcode is installed elsewhere, set XCODE_APP=/path/to/Xcode.app."
  exit 1
fi

XCODE_VERSION_LINE="$(xcodebuild -version | sed -n '1p')"
XCODE_BUILD_LINE="$(xcodebuild -version | sed -n '2p')"
ACTOOL_BIN="$(xcrun --find actool)"
XCODE_SELECT_PATH="$(xcode-select -p || true)"

log_header "${APP_NAME} build (community/self-compiled)"
log_step "Toolchain"
log_item "DEVELOPER_DIR: $DEVELOPER_DIR"
log_item "Xcode: ${XCODE_VERSION_LINE#Xcode } (${XCODE_BUILD_LINE#Build version })"
[[ -n "$XCODE_SELECT_PATH" ]] && log_item "xcode-select: $XCODE_SELECT_PATH"
if [[ "$VERBOSE" == "1" ]]; then
  log_item "actool: $ACTOOL_BIN"
fi

compile_icon_bundle() {
  if [[ ! -d "$ICON_BUNDLE" ]]; then
    log_error "icon: Icon Composer bundle not found at $ICON_BUNDLE"
    exit 1
  fi
  if [[ ! -f "$ICON_BUNDLE/icon.json" ]]; then
    log_error "icon: missing icon.json in $ICON_BUNDLE"
    exit 1
  fi

  rm -rf "$ICON_OUT_DIR"
  mkdir -p "$ICON_OUT_DIR"

  xcrun actool "$ICON_BUNDLE" \
    --compile "$ICON_OUT_DIR" \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist "$ICON_OUT_DIR/partial.plist" \
    --app-icon "$ICON_NAME" --include-all-app-icons \
    --enable-on-demand-resources NO \
    --development-region en \
    --target-device mac \
    --minimum-deployment-target 26.0 \
    --platform macosx \
    >"$ICON_OUT_DIR/actool.log" 2>&1
  actool_status=$?
  grep -E "warning:|error:" "$ICON_OUT_DIR/actool.log" || true
  log_dim "icon: actool exit code: $actool_status"

  if [[ ! -f "$ICON_OUT_DIR/Assets.car" || ! -f "$ICON_OUT_DIR/${ICON_NAME}.icns" ]]; then
    log_error "icon: actool did not produce the expected icon assets"
    sed -n '1,200p' "$ICON_OUT_DIR/actool.log" >&2 || true
    exit 1
  fi
}

log_step "Building ${APP_NAME} (release)"
ARCH_FLAGS=()
for arch in "${ARCHES[@]}"; do
  ARCH_FLAGS+=(--arch "$arch")
done
HOME="$SANDBOX_HOME" XDG_CACHE_HOME="$SANDBOX_HOME/.cache" \
  swift build --disable-sandbox --configuration release --product "$PRODUCT_NAME" --package-path "$PACKAGE_PATH" "${ARCH_FLAGS[@]}"

RELEASE_BINARY="$BUILD_DIR/$PRODUCT_NAME"
if [[ ! -f "$RELEASE_BINARY" ]]; then
  # Universal builds land under .build/apple/Products/Release/.
  RELEASE_BINARY="$PROJECT_ROOT/.build/apple/Products/Release/$PRODUCT_NAME"
fi

if [[ ! -f "$RELEASE_BINARY" ]]; then
  log_error "Failed to locate release binary (looked under $BUILD_DIR and .build/apple/Products/Release)"
  exit 1
fi

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
  log_error "Info.plist not found at $INFO_PLIST_SOURCE"
  exit 1
fi

read_plist_field() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST_SOURCE"
}

APP_SHORT_VERSION="$(read_plist_field CFBundleShortVersionString)"
APP_BUNDLE_VERSION="$(read_plist_field CFBundleVersion)"

if [[ -z "$APP_SHORT_VERSION" || -z "$APP_BUNDLE_VERSION" ]]; then
  log_error "Failed to read version fields from $INFO_PLIST_SOURCE"
  exit 1
fi

log_step "Assembling ${APP_NAME}.app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

install -m 755 "$RELEASE_BINARY" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$INFO_PLIST_SOURCE" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_SHORT_VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$APP_BUNDLE_VERSION" "$PLIST"

log_step "Marking this as a community build"
# This app is not built or signed by the project maintainer. Stamp it clearly
# so anyone using it can tell, point them at the official project, and turn
# off Sparkle auto-updates - self-builds have no update channel of their own.
plutil -replace DimlyBuildKind -string community "$PLIST"
plutil -replace CFBundleDisplayName -string "${APP_NAME} (Community Build)" "$PLIST"
plutil -replace SUEnableAutomaticChecks -bool false "$PLIST"
plutil -replace SUAutomaticallyUpdate -bool false "$PLIST"
plutil -remove SUFeedURL "$PLIST" 2>/dev/null || true
log_item "DimlyBuildKind: community"
log_item "Sparkle auto-update: disabled"

log_step "Copying localized resources"
shopt -s nullglob
localizations=()
for localization_dir in "$PROJECT_ROOT/Resources"/*.lproj; do
  if [[ -d "$localization_dir" ]]; then
    localizations+=("$localization_dir")
    cp -R "$localization_dir" "$APP_BUNDLE/Contents/Resources/"
  fi
done
shopt -u nullglob
log_item "Locales: ${#localizations[@]}"

if [[ -d "$PROJECT_ROOT/Resources/ExampleLUTs" ]]; then
  log_step "Copying bundled example LUTs"
  cp -R "$PROJECT_ROOT/Resources/ExampleLUTs" "$APP_BUNDLE/Contents/Resources/"
fi

if [[ -d "$PROJECT_ROOT/Resources/ExampleTextures" ]]; then
  log_step "Copying bundled example textures"
  cp -R "$PROJECT_ROOT/Resources/ExampleTextures" "$APP_BUNDLE/Contents/Resources/"
fi

resource_bundle_count=0
bundle_search_dirs=()
if [[ -d "$BUILD_DIR" ]]; then
  bundle_search_dirs+=("$BUILD_DIR")
fi
if [[ -d "$PROJECT_ROOT/.build/apple/Products/Release" ]]; then
  bundle_search_dirs+=("$PROJECT_ROOT/.build/apple/Products/Release")
fi
for bundle_dir in "${bundle_search_dirs[@]}"; do
  while IFS= read -r -d '' bundle; do
    if (( resource_bundle_count == 0 )); then
      log_step "Copying resource bundles"
    fi
    ((resource_bundle_count++))
    cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
  done < <(find -L "$bundle_dir" -maxdepth 1 -type d -name 'Dimly_*.bundle' -print0)
done
if (( resource_bundle_count > 0 )); then
  log_item "Bundles: $resource_bundle_count"
fi

log_step "Installing app icon (compiling Icon Composer bundle)"
compile_icon_bundle
mkdir -p "$APP_RES"
cp -f "$ICON_OUT_DIR/Assets.car" "$APP_RES/Assets.car"
cp -f "$ICON_OUT_DIR/${ICON_NAME}.icns" "$APP_RES/${ICON_NAME}.icns"
# CFBundleIconName drives the asset-catalog icon on macOS Tahoe+; CFBundleIconFile
# is the pre-Tahoe .icns fallback.
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $ICON_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICON_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons" "$PLIST" 2>/dev/null || true

log_step "Embedding Sparkle updater components (if present)"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
declare -a SPARKLE_FRAMEWORK_CANDIDATES=(
  "$PROJECT_ROOT/.build/artifacts/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
  "$PROJECT_ROOT/.build/artifacts/Sparkle/Sparkle.xcframework/macos-arm64/Sparkle.framework"
  "$PROJECT_ROOT/.build/artifacts/Sparkle/Sparkle.xcframework/macos-x86_64/Sparkle.framework"
)

SPARKLE_FRAMEWORK_SRC=""
for candidate in "${SPARKLE_FRAMEWORK_CANDIDATES[@]}"; do
  if [[ -d "$candidate" ]]; then
    SPARKLE_FRAMEWORK_SRC="$candidate"
    break
  fi
done

if [[ -z "$SPARKLE_FRAMEWORK_SRC" ]]; then
  SPARKLE_FRAMEWORK_SRC="$(find "$PROJECT_ROOT/.build" -maxdepth 6 -type d -name 'Sparkle.framework' -print -quit)"
fi

if [[ -n "$SPARKLE_FRAMEWORK_SRC" && -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
  rm -rf "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  cp -R "$SPARKLE_FRAMEWORK_SRC" "$APP_BUNDLE/Contents/Frameworks/"
  log_item "Sparkle framework embedded (needed for the Settings > About screen to load, even though checks are disabled)"
else
  log_warn "Sparkle.framework not found in .build; make sure the Sparkle SPM package is resolved."
fi

log_step "Ad-hoc signing (no Developer ID certificate involved)"
if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi
log_item "Signed with an ad-hoc identity (\"-\") - this proves nothing about who built it,"
log_item "it just lets Gatekeeper run the app locally without a paid Developer ID."

ELAPSED="$(( $(date +%s) - START_TIME ))"
log_success "${APP_NAME}.app created"
log_item "Path: $APP_BUNDLE"
log_item "Version: $APP_SHORT_VERSION ($APP_BUNDLE_VERSION) - community build"
log_item "Elapsed: ${ELAPSED}s"
echo
log_step "Next steps"
log_item "Move ${APP_NAME}.app to /Applications and launch it."
log_item "If macOS says it can't verify the developer, open System Settings > Privacy &"
log_item "Security and click \"Open Anyway\" next to ${APP_NAME}, then confirm once more."
