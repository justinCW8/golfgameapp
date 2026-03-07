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

1. **Engine** — `SixPointScotchEngine`, `StablefordEngine`, `NassauEngine` — pure game logic, structs only, no SwiftUI, no side effects
2. **ViewModel** — `RoundScoringViewModel` / `SaturdayScoringViewModel` — bridges engine + persistence to views; `@MainActor ObservableObject`
3. **View** — `RoundScoringView` / `SaturdayScoringView` and sub-views — reads from ViewModel, no business logic

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
| Saturday Mode home tab | `GolfGameApp/GolfGameApp/Features/Home/HomeView.swift` |
| Saturday Mode setup flow | `GolfGameApp/GolfGameApp/Features/Home/SaturdayRoundSetupFlow.swift` |
| Saturday Mode scoring ViewModel | `GolfGameApp/GolfGameApp/Features/Home/SaturdayScoringViewModel.swift` |
| Saturday Mode scoring UI | `GolfGameApp/GolfGameApp/Features/Home/SaturdayScoringView.swift` |
| Saturday Mode round summary | `GolfGameApp/GolfGameApp/Features/Home/RoundSummaryView.swift` |
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

~~Stableford and Six Point Scotch currently run as separate sessions in separate tabs with no shared gross score input.~~ **Resolved by Saturday Mode (see below).**

---

## Saturday Mode (Swarm 6, March 2026)

Unified multi-game round: one gross score entry per player fans out to all active engines simultaneously. Replaces the separate-tab per-game approach.

### Key Files

| Purpose | File |
|---------|------|
| Home tab (no round / active round states) | `GolfGameApp/Features/Home/HomeView.swift` |
| 4-screen setup flow + SaturdaySetupViewModel | `GolfGameApp/Features/Home/SaturdayRoundSetupFlow.swift` |
| Scoring ViewModel (engine replay) | `GolfGameApp/Features/Home/SaturdayScoringViewModel.swift` |
| Scoring UI | `GolfGameApp/Features/Home/SaturdayScoringView.swift` |
| Round summary / settlement tabs | `GolfGameApp/Features/Home/RoundSummaryView.swift` |

### New Models (SessionModels.swift)

- `SaturdayRound` — unified session: `players`, `teamAPlayerIDs`, `teamBPlayerIDs`, `holes`, `activeGames: [SaturdayGameType]`, `holeEntries: [SaturdayHoleEntry]`, `courseName`, `isComplete`
- `SaturdayGameConfig` — per-game config wrapping `nassauConfig`, `scotchConfig`, `stablefordConfig`
- `NassauGameConfig`, `ScotchGameConfig`, `StablefordGameConfig`
- `SaturdayHoleEntry` — `holeNumber`, `grossScores: [String: Int]` (playerID → gross), `scotchFlags: ScotchHoleFlags`, `nassauPressBy: TeamSide?`
- `ScotchHoleFlags` — `proxWinnerID: String?`, `pressBy: TeamSide?`, `rollBy: TeamSide?`, `rerollBy: TeamSide?`
- `SaturdayGameType` — enum: `.nassau`, `.sixPointScotch`, `.stableford`

### AppSessionStore Additions

```swift
var activeSaturdayRound: SaturdayRound?
func startSaturdayRound(players:teams:courseName:holes:activeGames:)
func updateSaturdayRound(_ round: SaturdayRound)
func clearSaturdayRound()
```

### SaturdayScoringView Layout (top → bottom, inside ScrollView)

```
holeHeader          — hole #, par, SI, course name; .id("scrollTop") for auto-scroll
currentStandings    — compact per-game score strip (right-aligned, "Last +N" sub-label)
scotchActions       — Press / Roll / Re-roll pill buttons (team initials, only eligible team shown)
scoreEntryGrid      — player rows with gross TextField; prox button inline per player
actionButtons       — "Score Hole" + "Edit Last Hole"
scotchAudit         — collapsible "Last Hole" card (see below)
scorecardButton     — opens PGA-style scorecard sheet
```

Auto-scroll to top on hole advance:
```swift
ScrollViewReader { proxy in
    ScrollView { ... }
    .onChange(of: vm.currentHole) { _ in
        withAnimation { proxy.scrollTo("scrollTop", anchor: .top) }
    }
    .onChange(of: vm.isComplete) { _ in
        withAnimation { proxy.scrollTo("scrollTop", anchor: .top) }
    }
}
```

### scotchAudit Card (collapsible)

**Collapsed header:** "Last Hole · [winner initials] +[pts]  ⌄"
**Expanded shows:**
1. Orange pill badges for any active **Press / Roll / Re-roll** (from `vm.scotchPressBy/rollBy/rerollBy`); hidden if none are active
2. Divider + bucket rows: Low Man, Low Team, Birdie, Prox — each with label, points, and winning team initials
3. Divider + hole total: winning team initials + `+N`; "Push" if tied

The `×N` multiplier chain (×1→×2→×4→×8) was deliberately **removed** — do not add it back.

Helpers on `SaturdayScoringContent`:
- `scotchAuditSummary(_ last:) -> String` — collapsed header text
- `lastHoleBuckets(_ last:) -> [(String, Int, TeamSide)]` — parses `auditLog` for bucket entries
- `teamInitials(_ side: TeamSide) -> String` — first names joined by "/"

### scotchActions Pills

- Shows only the action the **eligible team** may take (trailing team for press/roll, leading team for re-roll)
- Button label = real player first names joined by "/" (never "Team A" / "Team B")
- Tapped when active → tapping again deselects (toggle off)

### scoreEntryGrid / playerRow

- Player name `.subheadline.weight(.medium)`, HCP `.caption2`
- 5pt stroke dots
- **Prox button** inline next to player name — small capsule, only shown on par-3s (GIR required: net ≤ par)
- Score box: `.title2.weight(.bold)`, width 62, `.padding(.horizontal,8).padding(.vertical,7)`
- Row `.padding(.vertical, 8)`
- `teamLabelRow`: `.caption.weight(.semibold)`, `.padding(.vertical, 4)`

### SaturdayScoringViewModel Key Properties

```swift
var currentHole: Int
var isComplete: Bool
var isScotchActive: Bool
var scotchState: SixPointScotchEngineState  // .lastOutput: SixPointScotchHoleOutput?
var currentNineLedger: NineLedger           // .activePresses, .usedPresses, .teamAPoints, .teamBPoints
var projectedScotchMultiplier: Int
var scotchTrailingTeam: TeamSide?
var scotchLeadingTeam: TeamSide?
var scotchPressBy: TeamSide?
var scotchRollBy: TeamSide?
var scotchRerollBy: TeamSide?
var proxWinnerID: String?
```

Engine state is derived by **replaying** all `holeEntries` through the engine from scratch each time a hole is scored.

### SixPointScotchHoleOutput

```swift
var holeNumber: Int
var rawTeamAPoints: Int
var rawTeamBPoints: Int
var multipliedTeamAPoints: Int
var multipliedTeamBPoints: Int
var multiplier: Int
var auditLog: [String]
```

Audit log format per hole:
```
"Hole N"
"Press by teamA · front (1 active)."
"Roll by teamA."
"Re-roll by teamB."
"Low Man: teamA (2)"
"Low Team: teamB (2)"
"Birdie: teamA (1)"
"Prox: teamA (1)"
"Multiplier=2^N=M. Raw A/B=X/Y. Final A/B=A/B."
```

### GameStripPill (in currentStandings)

Compact per-game pill row. Scotch pill shows last-hole winner and points. Press/Roll/Re-roll shown as orange pill badges inside the expanded `scotchAudit` card, not inside the pill itself. Front/Back/Total columns were removed — do not add them back.

---

## Swarm 6 Additions (March 2026)

### Swarm 6.1 — Scorecard Gross + Net Display

`ScorecardSheet` in `SaturdayScoringView.swift` shows a PGA-style scorecard with **two rows per player cell**: gross score (via `PGAScoreCell`) and small net score below.

- `PGAScoreCell` — eagle/birdie/bogey circle/square notation relative to par
- Net = gross − `strokeCountForHandicapIndex(handicapIndex, onHoleStrokeIndex:)`
- Out/In/Tot columns show gross total + net total stacked
- `ScorecardSheet` and `PGAScoreCell` are **internal** (not `private`) so `HistoryRoundDetailView` can reuse them

### Swarm 6.2 — Nassau Display Strings Use Real Team Initials

`NassauMatchStatus.displayString` hardcodes "A" and "B". All views use a `nassauDisplayString(_ status:)` helper instead that substitutes real player first-name initials (e.g. "JP/BC 1UP" instead of "A 1UP"). Added to both `SaturdayScoringContent` and `GameStripPill`. `RoundSummaryView` uses `teamInitials(_ players: [PlayerSnapshot]) -> String`.

### Swarm 6.3 — Nassau Engine Fix: `trailingTeam()` Inverted

`NassauEngine.trailingTeam(in:)` had inverted logic. Fixed:

```swift
private func trailingTeam(in ledger: NassauSegmentLedger) -> TeamSide? {
    if ledger.aUp > 0 { return .teamB }  // A leads -> B trails
    if ledger.aUp < 0 { return .teamA }  // B leads -> A trails
    return nil
}
```

Only the **trailing team** may manually press — `manualPressRequiresTrailingTeam` thrown if leading team attempts. Also fixed `onChange(of:perform:)` deprecation to zero-argument closure form.

### Swarm 6.4 — Match-Decided Banner + Team Initials in Summary + History Tab

**Match-decided banner:** When `vm.nassauState.overallStatus.isClosed == true`, a green banner appears in `SaturdayScoringView` with a "Settle Up Now" `NavigationLink` to `RoundSummaryView`.

**RoundSummaryView:** "Team A" / "Team B" replaced with `teamInitials(round.teamAPlayers)` / `teamInitials(round.teamBPlayers)` throughout `NassauSummaryView` and `ScotchSummaryView`.

**History tab persistence:** `AppSessionStore.clearSaturdayRound()` archives the completed round to `completedRounds: [SaturdayRound]` before clearing. `AppSessionSnapshot` includes `completedRounds`. `SaturdayRound` now conforms to `Identifiable`.

```swift
@Published var completedRounds: [SaturdayRound] = []
func persistCompletedRounds()   // call after swipe-to-delete
```

**History UI** (`Features/History/HistoryHomeView.swift`):
- `HistoryHomeView` — empty state or list of completed rounds; swipe-to-delete
- `HistoryRoundRow` — course name, date, player names, game badges, holes played
- `HistoryRoundDetailView` — header + settlement tabs (reuses `NassauSummaryView` / `ScotchSummaryView` / `StablefordSummaryView`) + `ScorecardSheet`
- `NassauSummaryView`, `ScotchSummaryView`, `StablefordSummaryView` changed from `private` to `internal` for reuse

**History tab key file:** `GolfGameApp/GolfGameApp/Features/History/HistoryHomeView.swift`

### Swarm 6.5 — Manual Press Tests Fixed

Three unit tests (`manualPressThrowsWhenAtLimit`, `manualPressAppearsInPressStatuses`, `settlementCountsPressesInTotalBets`) pre-dated the `trailingTeam()` fix and used `press: .teamB` in scenarios where B is leading. Updated to `press: .teamA` (A is trailing when B leads).

---

## Commit Discipline

- Scope commits to a Swarm (logical feature chunk), e.g. "Swarm 2.11: ..."
- Build must be clean before committing; validate on simulator
- Run tests: `xcodebuild test -scheme GolfGameApp -destination 'platform=iOS Simulator,name=iPhone 17'`
- Stage only relevant `.swift` files — never commit `DerivedData`, `.xcuserstate`, or `UserDefaults` plist files
- User asks → then we commit. Do not auto-commit.
- Descriptive messages referencing the Swarm number
