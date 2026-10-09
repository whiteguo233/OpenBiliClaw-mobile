# Instagram consumption: real iOS simulator verification

Scope: production `RecommendView`, providers, API client, image decoder, saved actions and content launcher in a native Flutter integration harness. This does not exercise the full application's saved connection/settings/startup flow.

- Base: `f9aa02b`; independent `test/instagram-consumption` worktree. Existing mobile checkout modifications preserved, not included.
- Backend: Instagram worktree's production API at `127.0.0.1:28925`, isolated data from the October 5 real Instagram + configured-model initialization. No seeded cards or mocked HTTP/platform channels. Android and physical devices not tested.
- Device: booted iPhone 17 Pro simulator, iOS 26.5. Separate `com.openbiliclaw.instagramConsumptionTest` test bundle avoids replacing the existing app.
- `flutter pub get --offline` uses cached build dependencies only; application requests remain real. `flutter test --no-pub integration_test/instagram_consumption_live_test.dart -d <simulator-id>`: PASS, 1 test, 20 seconds after build. Targeted analyzer: no issues.
- Verified real Instagram recommendations, successful device-side image decoding, favorite/watch-later button writes and API readback, then removal. No upstream Instagram save/like/follow actions. Final saved memberships and native-save tasks both zero.
- Content launcher reported OS acceptance. Subsequent simulator screenshot shows Safari loaded the corresponding Instagram Reels landing page. Instagram native-app handoff and actual playback on the phone were NOT verified.
- Evidence: `/tmp/openbiliclaw-ins-consumption-20261005.s6N23r/`, especially `native-live-offline-deps.log`, `native-analyze.log`, `native-destination.png`, `final-audit.json`.

The original live run preceded delivery. The checked-in test now requires explicit opt-in and refuses nonempty saved lists before mutation; these harness safeguards do not constitute another live run. The temporary test bundle-ID edit is not committed, so the production application identity remains unchanged.

## Re-run (opt-in)

Use a disposable simulator or locally override the Runner bundle ID in an isolated checkout to avoid replacing an existing installation. Start an isolated backend with actual Instagram recommendations, empty local saved lists and upstream auto-sync disabled. Never target a daily-use database. The test writes/removes local memberships and records a content click; a failed run may leave test memberships for inspection.

```sh
flutter test --no-pub integration_test/instagram_consumption_live_test.dart \
  -d <simulator-id> --dart-define=INSTAGRAM_LIVE_E2E=true \
  --dart-define=INSTAGRAM_E2E_HOST=127.0.0.1 \
  --dart-define=INSTAGRAM_E2E_PORT=28925
```

Without `INSTAGRAM_LIVE_E2E=true`, the test skips. Android and physical devices remain unverified. No version bump, signing or production deployment is part of this delivery.
