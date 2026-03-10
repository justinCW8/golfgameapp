# Build/Test/Launch Readiness

This doc captures the local bootstrap and canonical validation commands for this repo.

## 1) Secrets state

`CourseSearchService` reads `Secrets.golfCourseAPIKey`.

Current branch state:
- `GolfGameApp/GolfGameApp/Core/Services/Secrets.swift` is committed and included in build input.
- `.gitignore` no longer excludes `Secrets.swift`.

If rotating keys later, update both:
- `GolfGameApp/GolfGameApp/Core/Services/Secrets.swift`
- `GolfGameApp/GolfGameApp/Core/Services/Secrets.swift.template`

## 2) Canonical no-sign CLI validation

Use an explicit DerivedData path and disable signing for local command-line checks.

### Build

```bash
xcodebuild build \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/golfgameapp-dd \
  CODE_SIGNING_ALLOWED=NO
```

### Unit tests only

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

Notes:
- UI tests are intentionally excluded from this CLI flow.
- If a usable simulator runtime/device is unavailable, run from Xcode UI on your machine.

## 3) Manual Xcode run

Open the project locally and run the app from Xcode:

```bash
open GolfGameApp/GolfGameApp.xcodeproj
```

Then run on an iOS Simulator or connected device and verify top-level navigation.

## 4) Lightweight UI route map

### Tabs
- Home (`HomeView`)
- History (`HistoryHomeView`)
- Settings (`ProfileView`)

### Home flow
- No active round state: primary CTA `Start Round` -> `SaturdayRoundSetupFlow`
- Active round state: `Resume Round` -> `SaturdayScoringView`
- Destructive path: `Start New Round` discards active round and returns to setup

### History flow
- Empty state if no completed rounds
- Active list state: round rows in `HistoryHomeView`
- Active row swipe action: Archive
- Active toolbar action: Archive All
- Archive list: grouped by date with fold/unfold sections
- Archive row swipe action: Delete
- Archive section action: Delete All Archived
- Detail: row tap -> `HistoryRoundDetailView`
- Scorecard: detail action -> `ScorecardSheet`

### Scorecard visibility updates
- Scorecard shows `SI` (hole handicap / stroke index) column.
- Per-player hole strokes are visible under gross score as markers:
  - `•` = 1 stroke
  - `••` = 2 strokes
  - `•xN` = 3+ strokes
- Player names appear at both top and bottom of scorecard to preserve column context.

## 5) Persistence behavior notes

- `AppSessionStore` persists active round state, completed history, and archived history to app support JSON.
- `BuddyStore` persists buddies (including phone numbers) in `UserDefaults`.
- Simulator/device app data generally survives rebuilds.
- Data is cleared by uninstalling app, resetting simulator content, or explicit deletion in app features.

## 6) Dev testing helpers

- In debug builds, `SaturdayScoringView` exposes:
  - `Dev: Auto-Fill Remaining Holes`
- This fills remaining holes with plausible scores and marks round complete for fast settlement/history testing.
