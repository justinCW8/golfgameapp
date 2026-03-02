# CLAUDE.md — GolfGameApp

## Build

Open `GolfGameApp/GolfGameApp.xcodeproj` in Xcode and run on the iOS simulator (iPhone 15 or similar). There is no CI pipeline — builds are validated manually in Xcode.

```
open GolfGameApp/GolfGameApp.xcodeproj
```

## Active Branch

All MVP Phase 1 work lives on `mvp-phase-1`. Main is the stable integration target.

## Architecture Overview

Three layers:

1. **Engine** — `SixPointScotchEngine`, `StablefordEngine` — pure game logic, no SwiftUI
2. **ViewModel** — `RoundScoringViewModel` — bridges engine + persistence to views
3. **View** — `RoundScoringView` and sub-views — no business logic

`AppSessionStore` (implements `SessionModel`) is the single source of truth for the active round session. It persists to `UserDefaults` as JSON.

See `docs/architecture.md` for the full layer diagram and key type table.

## Key Files

| Purpose | Path |
|---------|------|
| Main scoring UI | `GolfGameApp/GolfGameApp/Features/Round/RoundScoringView.swift` |
| Scoring ViewModel | `GolfGameApp/GolfGameApp/Features/Round/RoundScoringViewModel.swift` |
| Six Point Scotch engine | `GolfGameApp/GolfGameApp/Engine/SixPointScotchEngine.swift` |
| Engine types (input/output) | `GolfGameApp/GolfGameApp/Engine/SixPointScotchTypes.swift` |
| Session persistence | `GolfGameApp/GolfGameApp/Storage/AppSessionStore.swift` |
| Round session model | `GolfGameApp/GolfGameApp/Models/RoundSession.swift` |

## Game Rules

See `docs/prd/games/six-point-scotch.md` for the full Six Point Scotch rules PRD.

Summary:
- 4 players, 2 teams, 18 holes
- 6 points per hole across 4 buckets: Low Man (2), Low Team (2), Natural Birdie (1), Prox (1)
- Umbrella: sweep all 6 raw → 12 if one team wins everything
- Multiplier: `2^(presses + roll + reroll)`
- Front nine and back nine tracked independently (max 2 presses each)

## Round Lifecycle

See `docs/prd/round-core.md` for full details.

1. Setup wizard → `RoundSession` written to `AppSessionStore`
2. Hole-by-hole scoring in `RoundScoringView`
3. "End Round" → confirmation → `FinalRoundSummaryView` sheet
4. "Done" in sheet → `clearActiveRoundSession()` → back to `RoundHomeView`

## Commit Discipline

From PRD section 7:
- Scope commits to a Swarm (logical feature chunk)
- Build must be clean before committing
- Validate on simulator before committing
- Stage only relevant Swift files — never commit `DerivedData`, `.xcuserstate`, or `UserDefaults` files
- Write descriptive commit messages referencing the Swarm number
