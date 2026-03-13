# Testing Matrix

## Fast Rule Validation (Six Point Scotch)
- File: `GolfGameApp/GolfGameAppTests/SixPointScotchAdditionalTests.swift`
- Focus:
  - low-man tie behavior
  - low-team tie behavior
  - prox tie behavior
  - birdie push behavior
  - multiplier / umbrella / press flows

## Core Build/Test Commands
- Build:
```bash
xcodebuild build \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/golfgameapp-dd \
  CODE_SIGNING_ALLOWED=NO
```

- Unit tests:
```bash
xcodebuild test \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/golfgameapp-testdd \
  -only-testing 'GolfGameAppTests' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

## Manual Regression Checklist
- Setup -> Game Settings:
  - each game section has `Rules` button
  - Stableford rules include standard/modified tables
  - Skins rules explain gross/net/both
- Scoring screen:
  - top game chips render with game colors
  - chip info icon opens per-game rules
  - Scotch audit shows single player for Low Man and Prox when unique

## Risk Areas
- Team mapping correctness (player ID -> team side).
- Replay drift between persisted entries and engine outputs.
- Rules copy divergence between setup and scoring sheets.
