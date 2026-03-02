# Architecture — GolfGameApp

## Layer Diagram

```
┌─────────────────────────────────────────┐
│                  Views                  │
│  RoundScoringView  RoundScorecardView   │
│  FinalRoundSummaryView  RoundHomeView   │
└────────────────────┬────────────────────┘
                     │ @ObservedObject / @StateObject
┌────────────────────▼────────────────────┐
│               ViewModels                │
│         RoundScoringViewModel           │
└──────────┬─────────────────┬────────────┘
           │                 │
┌──────────▼───────┐  ┌──────▼──────────────┐
│   Game Engines   │  │   AppSessionStore    │
│ SixPointScotch   │  │  (SessionModel)      │
│    Engine        │  │  single source of    │
│ StablefordEngine │  │  truth for active    │
└──────────────────┘  │  round session       │
                      └─────────────────────┘
```

---

## AppSessionStore

`AppSessionStore` (conforming to `SessionModel`) is the single source of truth for the active round. It:

- Holds `activeRoundSession: RoundSession?`
- Persists to `UserDefaults` (JSON-encoded)
- Exposes `updateActiveRoundState(...)` for partial state writes
- Exposes `clearActiveRoundSession()` to end a round

All ViewModels receive `SessionModel` via dependency injection on init.

---

## Engine Rebuild Pattern

Game engines (`SixPointScotchEngine`) are **stateful but not serialized**. Instead:

1. `RoundSession.scoredHoleInputs` stores every `SixPointScotchHoleInput` as it is scored
2. On session restore, `RoundScoringViewModel.restoreFromSession()` creates a fresh engine and replays all stored inputs in order
3. This rebuilds the engine's nine ledgers, running totals, and multiplier state exactly

This avoids serializing complex engine internals while keeping restore reliable.

---

## Key Types

| Type | File | Description |
|------|------|-------------|
| `SixPointScotchEngine` | `Engine/SixPointScotchEngine.swift` | Stateful hole-by-hole scoring engine |
| `SixPointScotchHoleInput` | `Engine/SixPointScotchTypes.swift` | Input for one scored hole |
| `SixPointScotchHoleOutput` | `Engine/SixPointScotchTypes.swift` | Output with raw/multiplied/running totals |
| `NineLedger` | `Engine/SixPointScotchTypes.swift` | Per-nine running totals + press count |
| `RoundSession` | `Models/RoundSession.swift` | Persisted round state |
| `RoundSetup` | `Models/RoundSetup.swift` | Players, course, pairings |
| `PlayerSnapshot` | `Models/PlayerSnapshot.swift` | Player name + handicap index |
| `CourseHoleStub` | `Models/CourseHoleStub.swift` | Hole par + stroke index |
| `AppSessionStore` | `Storage/AppSessionStore.swift` | Session persistence (UserDefaults) |
| `RoundScoringViewModel` | `Features/Round/RoundScoringViewModel.swift` | Main round scoring VM |
| `RoundScoringView` | `Features/Round/RoundScoringView.swift` | Main scoring UI + sub-views |

---

## ViewModel Responsibilities

`RoundScoringViewModel`:
- Bridges `AppSessionStore` ↔ `SixPointScotchEngine` ↔ SwiftUI views
- Computes all display strings (match status, stroke displays, team names)
- Validates and routes scoring actions to the engine
- Persists state after every mutation
- Restores from session on init (engine replay)

Views contain **no business logic** — they only call ViewModel methods and bind to ViewModel properties.

---

## Persistence Flow

```
User action
    → ViewModel method
        → Engine.scoreHole(input) → output
        → SessionModel.updateActiveRoundState(...)
            → UserDefaults (JSON)
```

On next launch:
```
AppSessionStore.init()
    → UserDefaults.decode → RoundSession
        → RoundScoringViewModel.restoreFromSession()
            → replay scoredHoleInputs → rebuild engine
```
