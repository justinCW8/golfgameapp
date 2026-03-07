# Stableford Event — PRD

Status: Approved for Implementation
Version: 2.0
Scope: Net Stableford scoring engine, event/group tournament format, live leaderboard

---

## 1. Overview

Stableford is a points-based scoring format played across multiple groups simultaneously as part of a club event or outing. Instead of stroke totals, players accumulate points on each hole based on their net score relative to par. The player with the most points wins.

MVP Phase 1 supports **Net Stableford (club standard points scale)** for individual players across multiple groups, with a live leaderboard that aggregates results across all groups.

---

## 2. Stableford Scoring Rules

### 2.1 Points Scale (Club Standard)

| Net Score vs Par         | Points |
|--------------------------|--------|
| Albatross or better (−3 or lower) | 5 |
| Eagle (−2)               | 4      |
| Birdie (−1)              | 3      |
| Par (0)                  | 2      |
| Bogey (+1)               | 1      |
| Double bogey or worse (+2 or higher) | 0 |

Net score = Gross score − handicap strokes on that hole.

### 2.2 Handicap Stroke Allocation

Same formula as Six Point Scotch:
```
courseHandicap = floor(handicapIndex)
strokesOnHole = 1 if holeStrokeIndex <= courseHandicap, else 0
```

No handicap allowance percentage adjustment in Phase 1 — always 100%.

### 2.3 Cumulative Score

Player's Stableford total = sum of hole points (holes 1–18). Higher total wins.

### 2.4 Pickup Policy

When a player can no longer earn points on a hole (their minimum possible net score is already double bogey or worse), the UI should **suggest pickup** and record the hole as a pickup. On pickup, derive gross as the minimum score that yields 0 points (net double bogey):

```
pickup_gross = par + 2 + strokesOnHole
```

Pickup holes show 0 points. This is purely a pace-of-play helper — the player still enters a gross score if they finish; pickup is just a shortcut.

### 2.5 Tie-Break: Countback

When two or more players are tied on total points, break ties by comparing:
1. Points on holes 10–18 (back 9)
2. Points on holes 13–18 (back 6)
3. Points on holes 16–18 (back 3)
4. Points on hole 18 only

If still tied after hole 18 countback, display as shared rank. Engine surfaces the countback result; UI renders it in the leaderboard.

---

## 3. Event Structure

### 3.1 Event Setup

An **Event** consists of:
- Event name
- Date
- Course + tee box (one per event — all groups play same course/tee)
- Slope + course rating (for display; not used in net Stableford calculation)
- List of **Groups** (2–5 players per group, flexible)
- Entry format: individual only for Phase 1

### 3.2 Group Setup

Each **Group** within an event:
- 2–5 players
- Each player has: name + handicap index (→ course handicap computed at engine)
- Players are not split into teams (individual scoring)
- One group scores at a time on one device (no multi-device sync in Phase 1)

### 3.3 Leaderboard

Live leaderboard aggregates across all groups:
- Sorted by total Stableford points descending
- Ties resolved by countback (see §2.5); if still tied, share rank
- Shows: rank, player name, points total, holes played ("F18" / "F14" etc.)
- Updates as each group posts hole scores

---

## 4. Data Models

```swift
struct StablefordEvent: Codable, Identifiable {
    var id: UUID
    var name: String
    var date: Date
    var courseId: String
    var courseName: String
    var teeColor: String
    var slope: Int
    var courseRating: Double
    var groups: [StablefordGroup]
}

struct StablefordGroup: Codable, Identifiable {
    var id: UUID
    var players: [PlayerDraft]
    var scoredHoles: [StablefordHoleInput]
    var isComplete: Bool
}

struct StablefordHoleInput: Codable {
    var holeNumber: Int
    var grossByPlayerID: [UUID: Int]      // omit if pickup
    var isPickupByPlayerID: [UUID: Bool]  // true = player picked up
}

struct StablefordHoleResult: Codable {
    var holeNumber: Int
    var par: Int
    var strokesReceivedByPlayerID: [UUID: Int]
    var netScoreByPlayerID: [UUID: Int]
    var pointsByPlayerID: [UUID: Int]
    var isPickupByPlayerID: [UUID: Bool]
}

struct StablefordPlayerSummary: Identifiable {
    var id: UUID
    var name: String
    var totalPoints: Int
    var holesPlayed: Int
    var pointsByHole: [Int: Int]   // holeNumber → points
}
```

---

## 5. Engine: StablefordEngine

Stateless — takes inputs, returns outputs. No SwiftUI, no side effects.

```swift
struct StablefordEngine {

    // Score a single hole for all players in a group
    func scoreHole(
        holeNumber: Int,
        par: Int,
        strokeIndex: Int,
        players: [(id: UUID, handicapIndex: Double, gross: Int?, isPickup: Bool)]
    ) -> [UUID: StablefordHoleOutput]

    // Compute pickup gross for a player on a hole
    func pickupGross(par: Int, strokeIndex: Int, handicapIndex: Double) -> Int

    // Derive leaderboard from all scored holes
    func leaderboard(
        event: StablefordEvent,
        courseHoles: [CourseHoleStub]
    ) -> [StablefordPlayerSummary]

    // Countback comparison: returns positive if lhs beats rhs
    func countbackCompare(
        lhs: StablefordPlayerSummary,
        rhs: StablefordPlayerSummary
    ) -> ComparisonResult
}

struct StablefordHoleOutput {
    var strokesReceived: Int
    var netScore: Int
    var pointsEarned: Int
    var isPickup: Bool
}
```

### 5.1 Points Calculation (pure)

```
strokesReceived = strokeIndex <= courseHandicap ? 1 : 0
net = gross - strokesReceived
delta = net - par
points = switch delta {
    case ...(-2): 5
    case -1:      3
    case  0:      2
    case  1:      1
    default:      0
}
```

On pickup, `gross` is set to `pickupGross`, `isPickup = true`, `points = 0`.

---

## 6. Event Leaderboard

### 6.1 Aggregation

```swift
func leaderboard(event: StablefordEvent, courseHoles: [CourseHoleStub]) -> [StablefordPlayerSummary]
```

- Iterates all groups
- Replays all `StablefordHoleInput` records through engine
- Sums points per player
- Returns sorted by `totalPoints` descending, ties broken by `countbackCompare`

### 6.2 Display

```
Rank  Player       Points  Thru
 1    J. Waite       32    F18
 2    P. Casey       29    F14
 3    B. Clarke      27    F18
 4    J. Pierce      24    F11
```

- "F18" = finished all 18 holes
- "F14" = through 14 holes (in progress)
- Tied players show same rank; countback result shown as a tiebreaker label (e.g. "32 pts (CB)")

---

## 7. Scoring Flow (Group View)

```
Event → Select Group → GroupScoringView
  → Hole-by-hole (same visual flow as Scotch: hole #, par, stroke dots)
  → Each player: enter gross score
  → Pickup button: auto-fills gross = pickupGross, marks isPickup = true
  → "Score Hole" → shows points earned per player for that hole
  → "Next Hole" → advances
  → After hole 18: "Finish Group" → marks group isComplete = true
  → Returns to event leaderboard
```

Differences from Scotch scoring screen:
- No teams, no press/roll/reroll
- No prox field
- Points earned shown per player (not per team)
- Running Stableford total shown for each player
- Pickup button replaces manual 0-point entry

---

## 8. Persistence

Events are stored in `AppSessionStore` as `[StablefordEvent]`, serialized to JSON file (same pattern as `RoundSession`). Groups within an event store their `scoredHoles` array; the engine is replayed on restore.

Active group scoring state:
- `activeEventId: UUID?`
- `activeGroupId: UUID?`

These are stored in `AppSessionStore` alongside the event list.

---

## 9. UI Structure

```
EventHomeView
  → "New Event" → EventSetupWizard (name, course, groups + players)
  → Active Event card → EventDetailView
      → Leaderboard section (all players, live points, countback labels)
      → Groups section (list of groups, status: In Progress / Complete)
      → Tap group → GroupScoringView

GroupScoringView
  → Hole-by-hole scoring (similar to RoundScoringView)
  → Pickup button per player
  → Points earned summary after each hole
  → "Finish Group" on hole 18 complete

EventScorecardView
  → Tabular per-player scorecard with Stableford points per hole
  → Same visual style as RoundScorecardView
```

---

## 10. Swarm Breakdown

| Swarm | Scope |
|-------|-------|
| **3.1** | `StablefordEngine` + models + unit tests (scoring, pickup, countback) |
| **3.2** | `AppSessionStore` event persistence + `EventSetupWizard` UI |
| **3.3** | `GroupScoringView` + `GroupScoringViewModel` (hole entry, pickup button) |
| **3.4** | `EventLeaderboardView` (live aggregated leaderboard, countback labels) |
| **3.5** | `EventScorecardView` (per-player tabular scorecard) |

---

## 11. Out of Scope (Phase 1)

- Team Stableford formats (best ball, aggregate)
- Modified Stableford with negative points
- Handicap allowance percentage adjustments
- Gross Stableford scoring
- Multi-device real-time sync
- GHIN score posting
- Purse distribution / side games
- Historical event archive beyond local device storage
- Shotgun start support
- Multi-round tournament aggregation
