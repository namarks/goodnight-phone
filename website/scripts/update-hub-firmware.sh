#!/bin/sh
# Puts the latest bedroom hub firmware where the install page (/hub/install) serves it from.
# Uses the image built by the "Hub firmware" GitHub Action on main (needs the gh CLI, signed in).
# If that isn't available, it compiles locally instead (needs ESPHome: pip install esphome).
# `npm run deploy` runs this first when the image is missing.
set -eu
cd "$(dirname "$0")/.."
out=public/hub/firmware
bin="$out/bedroom-hub.factory.bin"
from_ci() {
  command -v gh >/dev/null 2>&1 || return 1
  run=$(gh run list -R namarks/goodnight-phone --workflow hub-firmware.yml --branch main --status success \
    --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null) || return 1
  [ -n "$run" ] || return 1
  tmp=$(mktemp -d)
  gh run download "$run" -R namarks/goodnight-phone -n bedroom-hub-firmware -D "$tmp" || return 1
  mv "$tmp/bedroom-hub.factory.bin" "$bin"
}
if ! from_ci; then
  echo "No firmware from GitHub; compiling with ESPHome"
  esphome compile ../hardware/esp32-hub.yaml
  cp "$(find ../hardware/.esphome -name firmware.factory.bin | head -1)" "$bin"
fi
ls -l "$bin"
