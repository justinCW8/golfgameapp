# AGENTS.md — GolfGameApp Agent Guidelines

## Build & Test Commands

### Opening the Project
```bash
open GolfGameApp/GolfGameApp.xcodeproj
```

### Running Tests (All)
```bash
xcodebuild test -scheme GolfGameApp -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Running a Single Test
```bash
xcodebuild test -scheme GolfGameApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing GolfGameAppTests/SkinsEngineTests
```

To run a specific test struct:
```bash
xcodebuild test -scheme GolfGameApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing GolfGameAppTests/SkinsEngineTests/SkinsEngineGrossTests
```

### Simulator Selection
The project is configured for iPhone 17. Other options: iPhone 15, iPhone 16. Always verify simulator is available with:
```bash
xcrun simctl list devices available | grep iPhone
```

---

## Architecture

### Three-Layer Architecture
1. **Engine** — Pure game logic (e.g., `SixPointScotchEngine`, `StablefordEngine`, `NassauEngine`, `SkinsEngine`). Structs only, no SwiftUI, no side effects.
2. **ViewModel** — Bridges engine + persistence to views. Use `@MainActor ObservableObject`.
3. **View** — Reads from ViewModel, no business logic.

### Source Layout
- Main app code: `GolfGameApp/GolfGameApp/`
- Tests: `GolfGameApp/GolfGameAppTests/`
- UITests: `GolfGameApp/GolfGameAppUITests/`

### Agent Navigation
Prefer targeted reads (`REPO_MAP.md` + specific paths) before repo-wide scans; use broad search only when location is unknown.

### Key Models Location
All data models and stores are in `SessionModels.swift`:
- `AppSessionStore` — JSON file persistence (NOT UserDefaults)
- `BuddyStore` — UserDefaults persistence for buddies
- `CourseStore` — UserDefaults persistence for saved courses

### Dependency Injection
`AppSessionStore` and `BuddyStore` are `@StateObject` in `GolfGameAppApp.swift`, injected as `.environmentObject()` on `ContentView`.

---

## Code Style Guidelines

### Swift Version
Swift 5.9+ with Swift Testing framework.

### Imports
```swift
import Foundation
import Combine
import SwiftUI
// Only import what's needed
```

### Naming Conventions
- **Types**: PascalCase (`TeamSide`, `SkinsEngine`, `PlayerSnapshot`)
- **Properties/Variables**: camelCase (`activePresses`, `grossCarryover`)
- **Enums**: PascalCase with lowercase cases (`case teamA`, `case .gross`)
- **Constants**: camelCase, prefer grouping in enums or structs

### Error Handling
- Use `enum` for error types with associated values when needed:
```swift
enum SkinsActionError: Error, Equatable {
    case holeOutOfRange
    case notEnoughPlayers
    case duplicatePlayerID
}
```
- Throw errors with guard statements at function entry:
```swift
guard (1...18).contains(input.holeNumber) else {
    throw SkinsActionError.holeOutOfRange
}
```

### Structs vs Classes
- Use `struct` for data models and engines (immutable preferred)
- Use `class` with `@MainActor` for ViewModels and ObservableObjects
- Use `final class` for stores that need reference semantics

### Protocols & Typealiases
- Prefer `protocol` for abstraction where needed
- `SessionModel` in this codebase is a typealias (not a protocol)

### Access Control
- Use `private` for internal implementation details
- Use `internal` (default) for types that need reuse across modules
- Use `@Published` for observable properties in stores

### Documentation Comments
Use `// MARK:` for section organization:
```swift
// MARK: - Errors
// MARK: - Input / Output
// MARK: - Engine
```

### SwiftUI Patterns
- Use `@StateObject` for ViewModel injection at app root
- Use `@EnvironmentObject` for accessing stores in views
- Use `@Binding` for two-way data flow
- Prefer `@Observable` for new SwiftUI view models

### Computed Properties
Place computed properties near related stored properties, not at the end of the type.

---

## Testing Guidelines

### Swift Testing Framework
Use `@Test` and `#expect`:
```swift
@Test func outrightWinnerGetsOneSkin() throws {
    var engine = SkinsEngine()
    let out = try engine.scoreHole(skinsInput(hole: 1, scores: [
        ("A", 3, 0), ("B", 4, 0), ("C", 5, 0)
    ]))
    #expect(out.grossResult.winnerID == "A")
    #expect(out.grossResult.skinsAwarded == 1)
}
```

### Test Structure
- Group tests in `struct` by feature/subsystem
- Use helper functions for common test setup
- Test both success and error paths
- Include audit log tests for engine classes

### Test File Naming
- Unit tests: `<FeatureName>Tests.swift` (e.g., `SkinsEngineTests.swift`)
- Place in `GolfGameAppTests/` directory

---

## Git & Commit Discipline

### Branch Naming
- Feature work: `mvp-phase-2` (current active branch)
- Stable baseline: `mvp-phase-1`
- Integration target: `main`

### Commit Messages
- Scope commits to a Swarm (logical feature chunk), e.g., "Swarm 8.1: Add SkinsEngine"
- Reference Swarm number in message
- Build must be clean before committing
- Run tests before committing

### Files to Never Commit
- `DerivedData/`
- `.xcuserstate`
- `UserDefaults` plist files
- Only stage relevant `.swift` files

---

## Common Patterns

### Engine State Replay
Saturday Mode replays all hole entries through engines from scratch:
```swift
func replayEngines() {
    var scotchEngine = SixPointScotchEngine()
    for entry in round.holeEntries {
        // replay each hole
    }
    scotchState = scotchEngine.state
}
```

### Player Sort by Team
Never hardcode player index 0/1 = Team A. Use pairings lookup:
```swift
let teamAIDs = teamPlayerIDs(for: .teamA)
// Map prox winner to team via player ID lookup
```

### Handicap Calculation
```swift
strokesOnHole = holeStrokeIndex <= floor(handicapIndex) ? 1 : 0
```
No allowance percentage — always 100%.

---

## Known Gotchas

### SourceKit False Errors
"Cannot find type X in scope" for `TeamSide`, `NineLedger`, `HoleResult`, etc. are pre-existing Xcode indexing noise. They do not prevent building. Do not fix.

### GolfCourseAPI.com
- `handicap` field = stroke index (not player handicap)
- `yardage` is a separate field — must be decoded explicitly

---

## PRDs & Documentation

- PRD master: `docs/prd/mvp-phase-1.md`
- Game rules: `docs/prd/games/six-point-scotch.md`, `docs/prd/games/stableford-final.md`
