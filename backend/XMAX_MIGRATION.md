# XMax realtime migration

The desktop realtime screen now uses XMax X2.1 through the official Web SDK
`@xmaxai/web-sdk@1.1.3`. The app still opens its browser-based camera and OBS
pop-out. XMax's Flutter SDK documents iOS and Android support, so this desktop
migration retains the existing browser architecture.

Run the database migration on the Django server:

```sh
python manage.py migrate
```

In **Django admin → Site Settings → XMax Realtime Streaming**, enter the
permanent key in **XMax API Key** and save. New sessions and reconnects read the
saved database value immediately, without a server restart. Existing sessions
keep the key they connected with. There is no hardcoded or environment key
fallback. If the field is blank, streaming is unavailable without charging for
session creation. For realtime-only installations, the legacy Decart key can be
left blank in the admin form.

`XMAX_ENVIRONMENT` remains an optional backend environment setting (`global` by
default, or `china` for a China-region account).

The authenticated token and reconnect endpoints return the admin-configured
permanent key directly to the browser SDK, with `expires_at: null`. There is no
temporary-key creation request, per-key expiry timer or five-minute reconnect
limit. Use `china` for a China-region account. The permanent key is visible in
browser developer tools; this mode is intended for a trusted environment.

App-credit billing remains 2 app credits/second. Browser heartbeat and reconnection
requests pass through the local desktop server, which attaches app authentication.
The browser does not receive the app login token. Keep the desktop app open while
streaming. Camera capture remains video-only; microphone publishing is disabled.
XMax account limits and provider session limits still apply. Reference-image
uploads still use XMax's temporary object-storage credentials and require an
accurate local clock.

Agora `statscollector-1.agora.io` requests are SDK statistics traffic. An
`ERR_BLOCKED_BY_CLIENT` message indicates browser-side blocking, commonly an
extension or privacy filter. Changing XMax keys does not remove that blocking;
try a browser profile with extensions disabled or a site-specific exception.

Realtime model IDs are now `x2.1`; old Lucy realtime IDs return HTTP 400. Deploy the
backend and desktop update together. Reference images upload through XMax storage
before generation starts. Prompt changes preserve the active reference image;
Clear Face removes it. The original watermark-key selection applies only to the
remaining Decart endpoints; XMax realtime uses the configured XMax account.

Queued image/video generation still uses Decart. Those endpoints require a
separate migration against XMax's offline API and supported capabilities. The
Decart dependency and admin keys remain for them. The formerly hardcoded Decart
fallback key was removed from settings; configure `DECART_API_KEY` or the existing
admin SiteSettings keys if you still use those endpoints. Rotate the previously
hardcoded credential.

Validation requires a real XMax account, a funded balance, a camera and a browser
with WebRTC. Check initial generation, reference upload, prompt changes, Clear
Face, OBS pop-out/docking, Stop/restart, reconnection and exhausted credits.
No live provider calls are made by the automated tests.

Official references:
- https://platform.xmax.ai/docs/capabilities/realtime-video/sdk-reference/flutter/video-and-audio
- https://platform.xmax.ai/docs/authentication
- https://github.com/Xmax-AI/XmaxSDK-Web
- https://github.com/Xmax-AI/XmaxSDK-Web/blob/main/materials/browser.md

Automated checks (Python 3.9 with project dependencies):

```sh
cd backend
python -m django test streaming.tests --settings=account.nowpayments_test_settings
```

From the desktop directory:

```sh
node --test test/xmax_stream_test.mjs
flutter analyze --no-pub lib/main.dart lib/services/api_service.dart lib/screens/playground/playground_screen.dart lib/screens/playground/realtime_stream_screen.dart
```

The JavaScript tests use a mocked SDK and browser DOM; they do not verify RTC,
provider authentication, media permissions or the hosted SDK delivery.

## Live studio experience

The desktop setup is a responsive portrait picker and studio preview. The browser
studio starts automatically after launch, requests camera permission, uploads the
selected portrait and passes its reference URL in the initial generation context.
There is no Apply Face step. A portrait-specific default prompt preserves pose,
expression, movement and background. Camera permission or failed network requests
may still require user intervention; Resume stream retries after a failure.

Provider/model IDs are internal. The visible studio, activity labels and session
status use camifyai branding. The browser layout prioritizes the live output,
retains OBS pop-out and fullscreen, and puts prompt editing under Fine-tune your
look. Browser scripts and network requests still contain the actual SDK/provider
identifiers needed to operate the service.
