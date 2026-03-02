# Stableford Event — PRD

## 1. Overview

Stableford is a points-based scoring format played across multiple groups simultaneously as part of a club event or outing. Instead of stroke totals, players accumulate points on each hole based on their net score relative to par. The player or team with the most points wins.

MVP Phase 1 supports **Modified Stableford** (standard points scale) for individual players across multiple groups, with a live leaderboard that aggregates results across all groups.

---

## 2. Stableford Scoring Rules

### 2.1 Points Scale (Modified Stableford — Standard)

| Net Score vs Par | Points |
|-----------------|--------|
| Eagle or better (−2 or lower) | 5 |
| Birdie (−1) | 3 |
| Par (0) | 2 |
| Bogey (+1) | 1 |
| Double bogey or worse (+2 or higher) | 0 |

Net score = Gross score − handicap strokes on that hole.

### 2.2 Handicap Stroke Allocation

Same as Six Point Scotch:
```
courseHandicap = floor(handicapIndex)
strokesOnHole = 1 if holeStrokeIndex <= courseHandicap, else 0
```

### 2.3 Cumulative Score

Player's Stableford total = sum of hole points (1–18).
Higher total wins.

---

## 3. Event Structure

### 3.1 Event Setup

An **Event** consists of:
- Event name
- Date
- Course + tee box (one per event — all groups play same course/tee)
- List of **Groups** (typically 2–5 players per group, flexible)
- Entry format: individual only for MVP

### 3.2 Group Setup

Each **Group** within an event:
- 2–5 players
- Each player has: name + handicap index
- Players are not split into teams (individual scoring)
- One group scores at a time on one device (no multi-device sync in Phase 1)

### 3.3 Leaderboard

Live leaderboard aggregates across all groups:
- Sorted by total Stableford points descending
- Shows: rank, player name, points total, holes played
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
    var grossByPlayerID: [UUID: Int]
}

struct StablefordHoleResult: Codable {
    var holeNumber: Int
    var par: Int
    var pointsByPlayerID: [UUID: Int]
    var netScoreByPlayerID: [UUID: Int]
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

Stateless — takes inputs, returns outputs.

```swift
struct StablefordEngine {
    func scoreHole(
        holeNumber: Int,
        par: Int,
        strokeIndex: Int,
        grossByPlayer: [(id: UUID, handicapIndex: Double, gross: Int)]
    ) -> [UUID: StablefordHoleOutput]
}

struct StablefordHoleOutput {
    var netScore: Int
    var pointsEarned: Int
    var strokesReceived: Int
}
```

---

## 6. Event Leaderboard

### 6.1 Aggregation

```swift
func leaderboard(event: StablefordEvent, courseHoles: [CourseHoleStub]) -> [StablefordPlayerSummary]
```

- Iterates all groups
- Replays all `StablefordHoleInput` records through engine
- Sums points per player
- Returns sorted by `totalPoints` descending

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
- Ties share the same rank

---

## 7. Scoring Flow (Group View)

```
Event → Select Group → Scoring screen
  → Same hole-by-hole flow as Scotch (hole #, par, stroke dots)
  → Each player: enter gross score
  → "Score Hole" → shows points earned per player for that hole
  → "Next Hole" → advances
  → After hole 18: "Finish Group" → marks group complete
  → Returns to event leaderboard
```

Differences from Scotch scoring screen:
- No teams, no press/roll/reroll
- No prox field
- Points earned shown per player (not per team)
- Running Stableford total shown for each player

---

## 8. Persistence

Events are stored in `AppSessionStore` as `[StablefordEvent]`, serialized to JSON file (same pattern as `RoundSession`). Groups within an event store their `scoredHoles` array; the engine is replayed on restore.

Active group scoring state mirrors the active round pattern:
- `activeEventId: UUID?`
- `activeGroupId: UUID?`

---

## 9. UI Structure

```
EventHomeView
  → "New Event" → EventSetupWizard (name, course, players per group)
  → Active Event card → EventDetailView
      → Leaderboard section (all players, live points)
      → Groups section (list of groups, status: In Progress / Complete)
      → Tap group → GroupScoringView

GroupScoringView
  → Hole-by-hole scoring (similar to RoundScoringView)
  → "Finish Group" on hole 18 complete

EventScorecardView
  → Tabular per-player scorecard with Stableford points per hole
  → Same visual style as RoundScorecardView
```

---

## 10. Swarm Breakdown

| Swarm | Scope |
|-------|-------|
| **3.1** | `StablefordEngine` + models + unit tests |
| **3.2** | `AppSessionStore` event persistence + `EventSetupWizard` UI |
| **3.3** | `GroupScoringView` + `GroupScoringViewModel` |
| **3.4** | `EventLeaderboardView` (live aggregated leaderboard) |
| **3.5** | `EventScorecardView` (per-player tabular scorecard) |

---

## 11. Out of Scope (Phase 1)

- Team Stableford formats
- Better Ball / Scramble formats
- Multi-device real-time sync
- GHIN score posting
- Money / skins within Stableford events
- Historical event archive beyond local device storage
