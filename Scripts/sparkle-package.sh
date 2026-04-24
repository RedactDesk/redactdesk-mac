#!/usr/bin/env bash
#
# Packages a RedactDesk build for Sparkle: zips the .app into the
# Sparkle-friendly archive format and runs Sparkle's generate_appcast to
# produce a signed appcast.xml alongside it.
#
# Input:  $RELEASE_BASE/<track>/<version>/RedactDesk.app
# Output: $RELEASE_BASE/<track>/<version>/RedactDesk.zip
#         $RELEASE_BASE/<track>/<version>/appcast.xml  (EdDSA-signed)
#
# Usage:
#   Scripts/sparkle-package.sh <version> [--track 1.0x]
#
# Env overrides:
#   RELEASE_BASE   default: $HOME/Documents/Projects/RedactDesk/RedactOutput

set -euo pipefail

RELEASE_BASE="${RELEASE_BASE:-$HOME/Documents/Projects/RedactDesk/RedactOutput}"
TRACK="1.0x"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <version> [--track <track-folder>]" >&2
    exit 2
fi

VERSION="$1"
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --track) TRACK="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

VERSION_DIR="${RELEASE_BASE}/${TRACK}/${VERSION}"
APP_PATH="${VERSION_DIR}/RedactDesk.app"
ZIP_PATH="${VERSION_DIR}/RedactDesk.zip"
APPCAST_PATH="${VERSION_DIR}/appcast.xml"

[[ -d "$APP_PATH" ]] || { echo "Missing: $APP_PATH" >&2; exit 1; }

# ---------- zip the .app ----------

echo "==> Zipping $(basename "$APP_PATH")"
rm -f "$ZIP_PATH"
# `ditto -c -k --sequesterRsrc --keepParent` is the Apple-recommended zip
# recipe for bundles: preserves resource forks, extended attributes, and the
# code signature so the archive Sparkle serves still passes Gatekeeper.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "    wrote: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# ---------- locate Sparkle's generate_appcast ----------

echo "==> Locating Sparkle generate_appcast"
DERIVED_ROOT="$HOME/Library/Developer/Xcode/DerivedData"
GENAPPCAST=$(
    find "$DERIVED_ROOT" \
        -type f \
        -name generate_appcast \
        -path '*Sparkle*' \
        2>/dev/null \
    | head -n 1
)
if [[ -z "$GENAPPCAST" ]]; then
    cat >&2 <<EOF
Could not find generate_appcast in DerivedData.

Build the Xcode project once so SPM resolves the Sparkle package, then
re-run this script. Searched under: $DERIVED_ROOT
EOF
    exit 1
fi
echo "    using: $GENAPPCAST"

# ---------- sign + generate appcast ----------

# generate_appcast scans the given directory for zip/dmg archives, signs any
# that do not already have a signature in the sibling appcast.xml, and emits
# appcast.xml with the enclosures. The EdDSA private key comes from the
# login keychain (the same one generate_keys stored).
echo "==> Running generate_appcast on $VERSION_DIR"
"$GENAPPCAST" "$VERSION_DIR"

[[ -f "$APPCAST_PATH" ]] || {
    echo "generate_appcast did not produce $APPCAST_PATH" >&2
    exit 1
}

echo
echo "Packaged:"
echo "    zip     : $ZIP_PATH"
echo "    appcast : $APPCAST_PATH"
echo
echo "Next: Scripts/release-publish.sh $VERSION"
