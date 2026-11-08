# Goodnight Phone website

Static site for `goodnightphone.marks-labs.com`: landing page, `/beacon` (which beacon to buy), `/support` and `/privacy`. Plain HTML and one stylesheet in `public/`, no build step. Hosted the same way as the Très Fort site: a standalone Cloudflare Worker that serves static assets only (no script, bindings or secrets), with a custom-domain route that provisions DNS and HTTPS.

## Deploy

From this directory (Node 22+):

```sh
npm ci
npx wrangler deploy --config wrangler.jsonc --dry-run
npm run deploy
```

Then check `/`, `/beacon`, `/support`, `/privacy`, an asset, and a missing URL.

## Content rules

- `public/privacy/index.html` is the privacy policy the app and App Store listing link to. Keep it in step with `PRIVACY.md` and with what the app actually does.
- Support email `support@marks-labs.com` is a Cloudflare Email Routing forward, not a mailbox.
- Purchase links on `/beacon` may carry an Amazon Associates tag. Keep `rel="sponsored"` on them and the disclosure line at the bottom of that page (FTC).
- Colors match `App/Assets.xcassets`; the heading font and illustrations come from the app (original art; never copy Goodnight Moon's illustrations, characters or wording). Font license: `public/assets/Fraunces-OFL.txt`.
- The App Store button on the home page needs the real App Store URL in place of `__APP_STORE_URL__`.
