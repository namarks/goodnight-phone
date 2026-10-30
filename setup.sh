#!/usr/bin/env bash
# Generates GoodnightPhone.xcodeproj for your Apple developer team and opens it in Xcode.
# Safe to re-run any time (e.g. after pulling changes); your answers are remembered.
set -euo pipefail
cd "$(dirname "$0")"

# --- XcodeGen ---------------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing XcodeGen (one-time)…"
    brew install xcodegen
  else
    echo "XcodeGen is needed. Install Homebrew from https://brew.sh, then run: brew install xcodegen" >&2
    exit 1
  fi
fi

# --- Your team + bundle ID --------------------------------------------------
ENV_FILE=.goodnightphone.env
# Carry over answers saved before the rename from Lights Out.
if [ ! -f "$ENV_FILE" ] && [ -f .lightsout.env ]; then mv .lightsout.env "$ENV_FILE"; fi
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [ -z "${TEAM_ID:-}" ]; then
  # Best guess: the team on your Apple Development signing certificate.
  DETECTED=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -n1 || true)
  echo "Your Team ID is the 10-character code at developer.apple.com/account → Membership details."
  read -r -p "Team ID${DETECTED:+ [$DETECTED]}: " TEAM_ID
  TEAM_ID=${TEAM_ID:-${DETECTED:-}}
fi
if ! [[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "“$TEAM_ID” doesn't look like a Team ID (10 letters/digits)." >&2
  rm -f "$ENV_FILE"
  exit 1
fi

if [ -z "${BUNDLE_PREFIX:-}" ]; then
  SUGGESTED="com.$(id -un | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
  read -r -p "Bundle ID prefix [$SUGGESTED]: " BUNDLE_PREFIX
  BUNDLE_PREFIX=${BUNDLE_PREFIX:-$SUGGESTED}
fi
if ! [[ "$BUNDLE_PREFIX" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "“$BUNDLE_PREFIX” isn't a valid reverse-DNS prefix (like com.yourname)." >&2
  rm -f "$ENV_FILE"
  exit 1
fi

printf 'TEAM_ID=%q\nBUNDLE_PREFIX=%q\n' "$TEAM_ID" "$BUNDLE_PREFIX" > "$ENV_FILE"

# --- Generate + open ----------------------------------------------------------
mkdir -p Support
TEAM_ID="$TEAM_ID" BUNDLE_PREFIX="$BUNDLE_PREFIX" xcodegen generate --spec project.yml

cat <<EOF

✅ GoodnightPhone.xcodeproj generated
   App ID:    $BUNDLE_PREFIX.goodnightphone
   App Group: group.$BUNDLE_PREFIX.goodnightphone

Next: plug in your iPhone, pick it as the run destination, and press ⌘R.
(First time on a device: Settings → Privacy & Security → Developer Mode → On.)
EOF

open GoodnightPhone.xcodeproj
