# CLAUDE.md — GolfGameApp

## Build

Open `GolfGameApp/GolfGameApp.xcodeproj` in Xcode and run on the iOS simulator (iPhone 15 or similar). No CI pipeline — builds are validated manually in Xcode.

```
open GolfGameApp/GolfGameApp.xcodeproj
```

All source lives under `GolfGameApp/GolfGameApp/` (the inner folder). The outer `GolfGameApp/` is the Xcode project wrapper.

## Active Branch

All MVP Phase 1 work lives on `mvp-phase-1`. `main` is the stable integration target.

## Architecture Overview

Three layers — no mixing:

1. **Engine** — `SixPointScotchEngine`, `StablefordEngine` — pure game logic, structs only, no SwiftUI, no side effects
2. **ViewModel** — `RoundScoringViewModel` — bridges engine + persistence to views; `@MainActor ObservableObject`
3. **View** — `RoundScoringView` and sub-views — reads from ViewModel, no business logic

**Persistence:**
- Active round session: JSON file persistence via `AppSessionStore` (located in `SessionModels.swift`). NOT UserDefaults.
- Buddy list: `BuddyStore` in `SessionModels.swift` — UserDefaults, flat list of `Buddy` structs.
- Course list: `CourseStore` in `SessionModels.swift` — UserDefaults, list of `SavedCourse` structs.

**Injection:** `AppSessionStore` (as `SessionModel` protocol) and `BuddyStore` are both `@StateObject` in `GolfGameAppApp.swift`, injected as `.environmentObject()` on `ContentView`.

## Key Files

All paths are relative to the repo root.

| Purpose | File |
|---------|------|
| App entry point | `GolfGameApp/GolfGameApp/GolfGameAppApp.swift` |
| All data models, stores | `GolfGameApp/GolfGameApp/SessionModels.swift` |
| Round setup + course setup UI | `GolfGameApp/GolfGameApp/Features/Round/RoundHomeView.swift` |
| Main scoring UI | `GolfGameApp/GolfGameApp/Features/Round/RoundScoringView.swift` |
| Scoring ViewModel | `GolfGameApp/GolfGameApp/Features/Round/RoundScoringViewModel.swift` |
| Six Point Scotch engine | `GolfGameApp/GolfGameApp/Core/Services/SixPointScotchEngine.swift` |
| Stableford engine | `GolfGameApp/GolfGameApp/Core/Services/StablefordEngine.swift` |
| Course search (GolfCourseAPI.com) | `GolfGameApp/GolfGameApp/Core/Services/CourseSearchService.swift` |
| Scorecard OCR parser | `GolfGameApp/GolfGameApp/Core/Services/ScorecardParser.swift` |
| Vision OCR wrapper | `GolfGameApp/GolfGameApp/Core/Services/ScorecardScanner.swift` |
| PRD master document | `docs/prd/mvp-phase-1.md` |
| Six Point Scotch rules PRD | `docs/prd/games/six-point-scotch.md` |
| Stableford rules PRD | `docs/prd/games/stableford-final.md` |
| Stableford home + setup | `GolfGameApp/GolfGameApp/Features/Events/EventHomeView.swift` |
| Stableford scoring UI | `GolfGameApp/GolfGameApp/Features/Events/EventGroupScoringView.swift` |
| Stableford scoring ViewModel | `GolfGameApp/GolfGameApp/Features/Events/EventGroupScoringViewModel.swift` |

## Data Models (SessionModels.swift)

Key types:

- `RoundSetupSession` — full round configuration: players, pairings, course holes, slope, courseRating, teeBoxName
- `CourseHoleStub` — per-hole data: `holeNumber`, `par`, `strokeIndex`, `yardage`
- `PlayerSnapshot` — player in round: `id`, `name`, `handicapIndex`, `courseHandicap`
- `AppSessionStore` — JSON file persistence, implements `SessionModel` protocol; `SessionModel` is a typealias (not a protocol)
- `BuddyStore` — UserDefaults persistence, `@Published var buddies: [Buddy]`
- `CourseStore` — UserDefaults persistence, `@Published var courses: [SavedCourse]`
- `SavedCourse` — saved course: `name`, `teeColor`, `slope`, `courseRating`, `holes: [CourseHoleStub]`
- `EventSession` — Stableford quick game session (JSON persisted alongside `RoundSession`); uses custom `Codable` with `decodeIfPresent` for `isQuickGame`
- `EventGroup` — `id`, `name`, `playerIDs: [String]`
- `StablefordHoleResult` — `playerID`, `holeNumber`, `gross`, `net`, `points`, `strokes`
- `strokeCountForHandicapIndex(_ handicapIndex: Double, onHoleStrokeIndex si: Int) -> Int` — shared helper used by both Scotch and Stableford engines

## Course Setup Flow

`RoundHomeView.swift` contains `CourseSetupScreen` driven by `ScanViewModel`.

**Two paths to get hole data:**

1. **API search** (primary): `CourseSearchService` queries `api.golfcourseapi.com`. Response per hole: `{"par": 4, "yardage": 378, "handicap": 6}` where `handicap` = stroke index. Slope and rating come from the tee object.

2. **Camera OCR** (fallback): `ScorecardScanner` (Vision framework) → `ScorecardParser` → `ScannedCourseData` with 18 `ScannedHole` entries. Parser looks for Par row, SI/Hcp row, Slope, and Rating. Nil fields shown as orange in review screen.

**Flow:**
```
CourseSetupScreen → (search or scan) → ScannedCourseData
  → review/correct in Form → Confirm
  → ScanViewModel.onConfirm(CourseScanResult)
  → viewModel.holes = result.toHoleStubs()  (CourseHoleStub array)
  → saved to CourseStore for reuse
```

**`ScorecardParser.swift`** also defines `ScannedHole`, `ScannedCourseData`, and `TeeRating`.

## Six Point Scotch Rules (All Confirmed)

4 players, 2 teams (Team A / Team B), 18 holes.

**Buckets per hole (6 raw points total):**
| Bucket | Points | Winner |
|--------|--------|--------|
| Low Man | 2 | Team with lowest individual net score |
| Low Team | 2 | Team with lowest combined net score |
| Natural Birdie | 1 | Team with a player at gross = par - 1 |
| Prox | 1 | Team closest to pin; only eligible if ≥1 player has net ≤ par (GIR) |

**Umbrella:** If one team wins all 4 buckets (6 raw pts), they get 12 instead. Other team gets 0.

**Multiplier:** `2^(activePresses + rollFlag + rerollFlag)` applied to raw points.

**Press rules:**
- Only the trailing team may press (by points in current nine, not score)
- Max 2 presses per nine (front/back tracked independently in `NineLedger`)
- Presses reset at hole 10 (new `NineLedger` for back nine)
- Two presses = ×4 multiplier (2^2) — this is correct, not a bug

**Roll/Re-roll rules:**
- Roll: trailing team only
- Re-roll: leading team only (engine guard checks `leader == rerollTeam`)
- Both flags add to the multiplier exponent

**Prox GIR enforcement** (engine-level):
```swift
let aEligible = teamANet.contains(where: { $0 <= par })
```
If a team has no GIR player, their prox feet are set to nil before comparison.

## Key ViewModel Patterns (RoundScoringViewModel.swift)

### Player Sort by Team
Players displayed in Team A order then Team B order (not round-entry order):
```swift
var playersWithOriginalIndex: [(originalIndex: Int, player: PlayerSnapshot)]
```
Use `originalIndex` for all gross score bindings (not the sorted position).

### Prox Team Assignment
`proxDistancesFromWinner(_ winner: ProxWinner) -> (Double?, Double?)` maps ProxWinner (.player1–.player4) to `(teamAProxFeet, teamBProxFeet)` by looking up the player's ID in `teamPlayerIDs(for: .teamA)`. **Never hardcode player index 0/1 = Team A** — pairings are user-defined and can interleave.

### Press Status Text
`pressStatusText: String` — e.g. "2 presses active · 0 remaining · front 9". Reads from `NineLedger.activePresses` and `usedPresses`.

### Audit Log Format
- `latestAuditLines` returns only the current hole's lines
- Summary line ("5 for 10 for 20") moved to top (position 1, after hole header)
- Buckets below: "Low Man: JP / MB (2)", "Prox: JW / BC (1)"
- `formatAuditLine()` replaces "teamA"/"teamB" with real player name strings
- `reformatMultiplierLine()` builds the "for" chain by doubling raw points `exp` times

## Round Lifecycle

1. `RoundHomeView` — setup wizard (Players → Course → Teams)
2. Wizard writes `RoundSetupSession` to `AppSessionStore`
3. `RoundScoringView` — hole-by-hole scoring, driven by `RoundScoringViewModel`
4. "End Round" → confirmation alert → `FinalRoundSummaryView` sheet
5. "Done" in sheet → `clearActiveRoundSession()` → back to `RoundHomeView`

Killed-and-relaunched app resumes from last scored hole (session persisted as JSON file).

## Known Gotchas

**SourceKit false errors:** "Cannot find type X in scope" for `TeamSide`, `NineLedger`, `HoleResult`, `PlayerSnapshot`, etc. are pre-existing Xcode indexing noise. They do not prevent building. Do not try to fix them.

**`NineLedger.activePresses`** accumulates across all holes in the nine (not just the current hole). Two presses correctly produces ×4.

**GolfCourseAPI.com** `handicap` field = stroke index (not player handicap). `yardage` is a separate field — must be decoded explicitly in `GolfAPIHole`.

## Stableford — Quick Game

### Overview
Stableford is individual scoring: points earned per hole based on net score vs par. No teams, no presses, no prox. Higher total wins.

**Points scale (club standard — confirmed correct):**
| Net vs Par | Points |
|---|---|
| −3 or better (albatross+) | 5 |
| −2 (eagle) | 4 |
| −1 (birdie) | 3 |
| 0 (par) | 2 |
| +1 (bogey) | 1 |
| +2+ (double bogey or worse) | 0 |

**Handicap strokes:** `strokesOnHole = 1 if holeStrokeIndex <= floor(handicapIndex), else 0`. No allowance percentage — always 100%.

**Pickup:** `pickupGross = par + 2 + strokesOnHole`. Records 0 points. Pace-of-play shortcut.

### Key Files

| Purpose | File |
|---------|------|
| Stableford engine (stateless) | `GolfGameApp/GolfGameApp/Core/Services/StablefordEngine.swift` |
| Session model + persistence | `GolfGameApp/GolfGameApp/SessionModels.swift` (see `EventSession`) |
| Home screen + setup flow | `GolfGameApp/GolfGameApp/Features/Events/EventHomeView.swift` |
| Hole-by-hole scoring UI | `GolfGameApp/GolfGameApp/Features/Events/EventGroupScoringView.swift` |
| Scoring ViewModel | `GolfGameApp/GolfGameApp/Features/Events/EventGroupScoringViewModel.swift` |
| Stableford PRD | `docs/prd/games/stableford-final.md` |

### Data Models (SessionModels.swift)

- `EventSession` — persisted as JSON alongside `RoundSession`. Key fields: `players`, `groups`, `holes`, `holeResultsByPlayer`, `currentHoleByGroup`, `isQuickGame: Bool`
- `EventGroup` — `id`, `name`, `playerIDs: [String]`
- `StablefordHoleResult` — `playerID`, `holeNumber`, `gross`, `net`, `points`, `strokes`
- `AppSessionStore.startQuickGame(players:holes:courseName:) -> String` — creates `EventSession` with `isQuickGame = true`, one group, returns `groupID`
- `AppSessionStore.clearActiveEventSession()` — ends the game

`isQuickGame` uses custom `Codable` with `decodeIfPresent` defaulting to `false` — backward compatible with sessions saved before the field existed.

### App Structure (Stableford tab)

`EventHomeView` (Stableford tab) uses `NavigationStack` with path-based routing:

```
EventRoute.quickSetup  → QuickGameSetupFlowView
EventRoute.groupScoring(String)  → EventGroupScoringView
```

**Home screen states:**
- No active session → "Quick Game" button
- Active session → course name + player names + "Continue Scoring" + "End Game"

**Setup flow (Quick Game):**
```
QuickGameSetupFlowView
  → EventPlayersScreen (2–4 players, buddy picker, max 4)
  → EventCourseScreen (search / saved courses / OCR scan)
  → "Start Game" button → startQuickGame() → path = [.groupScoring(groupID)]
```

Setup reuses `EventSetupViewModel` (same ViewModel for players + course), `ScanViewModel` (same course search/OCR logic as Round tab), `BuddiesSheet`, `HoleReviewRow`, `ImagePicker`.

### Scoring Flow

`EventGroupScoringView` / `EventGroupScoringViewModel`:
- Hole-by-hole: hole header (hole #, par, SI, yardage), player rows, action buttons
- Per-player row: name, CH (course handicap displayed), stroke dots (filled circles showing handicap strokes on this hole), Pickup capsule button, gross TextField, live net/points preview
- "Score Hole" → saves `StablefordHoleResult` for each player, advances `currentHoleByGroup`
- "Edit Last Hole" → restores previous gross inputs, removes results, decrements hole counter
- Running totals shown below results
- Completed banner after hole 18

**Pickup toggle:** marks player as pickup, disables gross TextField, stores `pickupGross` as gross, forces `points = 0`.

**`canScore`:** true when all players have either a pickup flag or a valid Int gross input.

### Architecture Decisions Made

**Multi-group event format removed from UI** (Swarm session, March 2026). The multi-group flow required multiple devices with no sync — misleading UX. Code removed: `EventSetupFlowView`, `EventBasicsScreen`, `EventGroupAssignmentScreen`, `EventLeaderboardView`, `ActiveEventCard`. Backend sync needed before this can return.

**Countback tie-break** is implemented in `EventGroupScoringViewModel.leaderboardRows(from:)` using segments `[10...18, 13...18, 16...18, 18...18]` — retained in the ViewModel even though the leaderboard UI is removed, in case it's needed for a future scorecard summary view.

### Pending Architecture Decision

Stableford and Six Point Scotch currently run as separate sessions in separate tabs with no shared gross score input. In real golf, players routinely score both games simultaneously from the same gross scores. A unified "Round with multiple active games" model is planned — requires Nassau PRD to be complete before rearchitecting. Do not refactor until all three game specs (Scotch, Stableford, Nassau) are finalised.

## Commit Discipline

- Scope commits to a Swarm (logical feature chunk), e.g. "Swarm 2.11: ..."
- Build must be clean before committing; validate on simulator
- Stage only relevant `.swift` files — never commit `DerivedData`, `.xcuserstate`, or `UserDefaults` plist files
- User asks → then we commit. Do not auto-commit.
- Descriptive messages referencing the Swarm number
