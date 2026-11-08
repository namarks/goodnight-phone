# Goodnight Phone website

Static site for `goodnightphone.marks-labs.com`: landing page, `/beacon` (which beacon to buy), `/hub/install` (one-click install of the bedroom hub firmware), `/support` and `/privacy`. Plain HTML and one stylesheet in `public/`, no build step. Hosted the same way as the Très Fort site: a standalone Cloudflare Worker that serves static assets only (no script, bindings or secrets), with a custom-domain route that provisions DNS and HTTPS.

## Deploy

From this directory (Node 22+):

```sh
npm install
scripts/update-hub-firmware.sh   # when hardware/esp32-hub.yaml changed (deploy runs it if the image is missing)
npx wrangler deploy --config wrangler.jsonc --dry-run
npm run deploy
```

Then check `/`, `/beacon`, `/hub/install` (the Install button shows in Chrome), `/support`, `/privacy`, an asset, and a missing URL.

## Content rules

- `public/privacy/index.html` is the privacy policy the app and App Store listing link to. Keep it in step with `PRIVACY.md` and with what the app actually does.
- Support email `support@marks-labs.com` is a Cloudflare Email Routing forward, not a mailbox.
- Purchase links on `/beacon` may carry an Amazon Associates tag. Keep `rel="sponsored"` on them and the disclosure line at the bottom of that page (FTC).
- Colors match `App/Assets.xcassets`; the heading font and illustrations come from the app (original art; never copy Goodnight Moon's illustrations, characters or wording). Font license: `public/assets/Fraunces-OFL.txt`.
- App Store listing: https://apps.apple.com/us/app/goodnight-phone/id6828643945
- `/hub/install` uses ESP Web Tools 10.4.0, vendored unmodified in `public/assets/esp-web-tools/` because the CSP only allows our own scripts. Our own button (`public/assets/hub-install.js`) lists only Espressif boards and goes straight to erase-and-install through the dialog's internal `_startInstall`/`_confirmInstall`, so check those when updating ESP Web Tools. The firmware image `public/hub/firmware/bedroom-hub.factory.bin` comes from `scripts/update-hub-firmware.sh`; `manifest.json` next to it tells the button what to flash (ESP32-C6, offset 0).
