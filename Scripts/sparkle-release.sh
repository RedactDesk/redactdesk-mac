#!/usr/bin/env bash
#
# Signs a RedactDesk release artifact (zip or dmg) with the EdDSA key in your
# keychain and prints an <item> block that drops straight into appcast.xml.
#
# Usage:
#   Scripts/sparkle-release.sh path/to/RedactDesk-1.1.0.dmg 1.1.0 "140"
#
# Positional args:
#   $1 - path to the signed/notarized DMG or ZIP
#   $2 - marketing version (CFBundleShortVersionString), e.g. 1.1.0
#   $3 - build number (CFBundleVersion), e.g. 140
#
# Prereq: Scripts/sparkle-generate-keys.sh has already been run and the
# public key is pasted into SUPublicEDKey.

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <artifact.dmg|.zip> <shortVersion> <buildNumber>" >&2
  exit 2
fi

ARTIFACT="$1"
SHORT_VERSION="$2"
BUILD_NUMBER="$3"

if [[ ! -f "${ARTIFACT}" ]]; then
  echo "Artifact not found: ${ARTIFACT}" >&2
  exit 1
fi

DERIVED_ROOT="$HOME/Library/Developer/Xcode/DerivedData"

SIGN_BIN=$(
  find "$DERIVED_ROOT" \
    -type f \
    -name sign_update \
    -path '*Sparkle*' \
    2>/dev/null \
    | head -n 1
)

if [[ -z "${SIGN_BIN}" ]]; then
  echo "Could not find Sparkle's sign_update binary - build the app in Xcode first." >&2
  exit 1
fi

# sign_update emits `sparkle:edSignature="..." length="..."` on stdout.
SIGNATURE_ATTRS=$("${SIGN_BIN}" "${ARTIFACT}")

ARTIFACT_BASENAME=$(basename "${ARTIFACT}")
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

cat <<EOF
<item>
    <title>Version ${SHORT_VERSION}</title>
    <pubDate>${PUB_DATE}</pubDate>
    <sparkle:version>${BUILD_NUMBER}</sparkle:version>
    <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <description><![CDATA[
        <p>Release notes for ${SHORT_VERSION} - fill me in.</p>
    ]]></description>
    <enclosure
        url="https://github.com/RedactDesk/redactdesk-mac/releases/download/v${SHORT_VERSION}/${ARTIFACT_BASENAME}"
        ${SIGNATURE_ATTRS}
        type="application/octet-stream" />
</item>
EOF
