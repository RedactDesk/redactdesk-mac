#!/usr/bin/env bash
#
# Generates the EdDSA key pair Sparkle uses to sign updates, using the
# `generate_keys` binary that ships with the Sparkle SPM checkout.
#
# Run this ONCE per product. The private key is stored in the macOS keychain
# (Sparkle handles this automatically); the public key is printed to stdout
# and needs to be pasted into the INFOPLIST_KEY_SUPublicEDKey build setting
# so that shipping builds know which signature to trust.
#
# Re-running this script when a key already exists is a no-op - generate_keys
# detects the keychain entry and prints the existing public key. If you ever
# need to rotate, delete the "https://sparkle-project.org" keychain item
# first, then re-run.

set -euo pipefail

# Resolve the repo-relative Xcode DerivedData location where SPM drops Sparkle.
# We search the full DerivedData tree rather than hard-coding a path since the
# folder name embeds a hash that changes per machine.
DERIVED_ROOT="$HOME/Library/Developer/Xcode/DerivedData"

GENERATE_BIN=$(
  find "$DERIVED_ROOT" \
    -type f \
    -name generate_keys \
    -path '*Sparkle*' \
    2>/dev/null \
    | head -n 1
)

if [[ -z "${GENERATE_BIN}" ]]; then
  cat >&2 <<EOF
Could not find the Sparkle generate_keys binary in DerivedData.

Build the app once in Xcode (Product > Build) so SPM resolves the Sparkle
package, then re-run this script.
EOF
  exit 1
fi

echo "Using generate_keys at: ${GENERATE_BIN}"
echo

"${GENERATE_BIN}"

cat <<EOF

Next steps
----------
1. Copy the public key printed above (the one starting after
   "Public EdDSA key:").
2. Paste it into the Xcode target's build setting SUPublicEDKey
   (it is already declared as INFOPLIST_KEY_SUPublicEDKey in project.pbxproj,
   currently empty). Both Debug and Release configs need the same key.
3. Commit the pbxproj change. The private key stays in your keychain;
   never check it in.
EOF
