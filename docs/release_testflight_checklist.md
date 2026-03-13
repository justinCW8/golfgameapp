# Release / TestFlight Checklist

## Prereqs
- Apple Developer Program active.
- Bundle ID and signing configured in Xcode.
- App record created in App Store Connect.

## Build + Upload
1. Xcode -> select `Any iOS Device`.
2. `Product > Archive`.
3. Organizer -> `Distribute App`.
4. Choose `App Store Connect` -> `Upload`.

## TestFlight
1. App Store Connect -> TestFlight tab.
2. Wait for processing to complete.
3. Internal testing:
  - add internal testers (fastest path).
4. External testing:
  - submit for Beta App Review once, then add testers/public link.

## OTA Install (Tester)
1. Install Apple `TestFlight` app.
2. Open invite link or public link.
3. Install build over the air.

## Common Gotchas
- Missing export compliance metadata blocks distribution.
- Version/build number must be incremented for each upload.
- External tester rollout requires beta review approval first.
