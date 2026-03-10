# AGENTS.md - GolfGameApp

Guidance for autonomous coding agents working in this repo.
Run commands from repository root (`golfgameapp/`) unless noted.

## Repo Layout
- Xcode project: `GolfGameApp/GolfGameApp.xcodeproj`
- Main scheme: `GolfGameApp`
- App code: `GolfGameApp/GolfGameApp/`
- Unit tests: `GolfGameApp/GolfGameAppTests/`
- UI tests: `GolfGameApp/GolfGameAppUITests/`
- Fast nav index: `REPO_MAP.md`

## Build, Lint, and Test Commands

### Open in Xcode
```bash
open GolfGameApp/GolfGameApp.xcodeproj
```

### Show schemes/targets
```bash
xcodebuild -list -project "GolfGameApp/GolfGameApp.xcodeproj"
```

### Build (Debug, simulator)
```bash
xcodebuild build \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Run all tests
```bash
xcodebuild test \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Run a single test file
```bash
xcodebuild test \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'GolfGameAppTests/SkinsEngineTests'
```

### Run a single test group/struct
```bash
xcodebuild test \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'GolfGameAppTests/SkinsEngineTests/SkinsEngineGrossTests'
```

### Run one specific test case
```bash
xcodebuild test \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'GolfGameAppTests/SkinsEngineTests/SkinsEngineGrossTests/outrightWinnerGetsOneSkin()'
```

### Run unit tests only
```bash
xcodebuild test \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing 'GolfGameAppTests'
```

### Secrets key files
- `GolfGameApp/GolfGameApp/Core/Services/Secrets.swift`
- `GolfGameApp/GolfGameApp/Core/Services/Secrets.swift.template`
- Current branch keeps `Secrets.swift` tracked in git.
- If key changes, keep both files synchronized.

### Canonical no-sign build (local CLI)
```bash
xcodebuild build \
  -project "GolfGameApp/GolfGameApp.xcodeproj" \
  -scheme "GolfGameApp" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/golfgameapp-dd \
  CODE_SIGNING_ALLOWED=NO
```

### Canonical no-sign unit tests (local CLI)
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

### Simulator discovery
```bash
xcrun simctl list devices available
```

### Lint/format status
- No `.swiftlint.yml` found (no repo-enforced SwiftLint command).
- No `.swiftformat` found (no repo-enforced SwiftFormat command).
- Use `xcodebuild build` and `xcodebuild test` as the quality gate.

## Cursor / Copilot Rules
- `.cursor/rules/`: not present
- `.cursorrules`: not present
- `.github/copilot-instructions.md`: not present
- If any of these are added, treat them as high-priority constraints.

## Architecture Rules
- Keep the three-layer boundary strict:
  1. Engine = pure scoring logic (no SwiftUI, no side effects)
  2. ViewModel = `@MainActor` orchestration/state
  3. View = rendering and bindings, not business logic
- `AppSessionStore` uses JSON persistence (not UserDefaults).
- `BuddyStore` and `CourseStore` use UserDefaults.
- Stores are injected at app root via `.environmentObject(...)`.
- Saturday mode game state is derived by replaying saved hole entries; preserve deterministic replay behavior.

## Code Style Guide

### Imports
- Import only required modules.
- Follow existing file conventions; common examples are `SwiftUI`, `Combine`, `Foundation`.
- In tests, use `import Testing` + `@testable import GolfGameApp`.

### Formatting
- 4-space indentation, no tabs.
- Keep files organized with `// MARK: - ...` sections.
- Prefer readable helper functions over deep nesting.
- Keep declarations and control flow consistent with nearby code.

### Types and state
- Prefer `struct` for domain models and scoring engines.
- Use `final class` for stores/view models with shared mutable state.
- Prefer `let` by default; use `var` only for required mutation.

### Naming
- Types/protocols/enums: PascalCase.
- Variables/functions/properties/enum cases: camelCase.
- Use explicit golf-domain names (`grossCarryover`, `teamAPlayers`, `currentHole`).

### Access control
- Default to `private` for implementation details.

### Control flow and errors
- Use `guard` for input validation and early exit.
- Validate at boundaries (hole ranges, player counts, duplicate IDs, etc.).
- Model business failures with typed `Error` enums.
- Prefer specific error cases over generic failures.

### SwiftUI conventions
- App-owned objects: `@StateObject`.
- Shared object access in views: `@EnvironmentObject`.
- Two-way view data flow: `@Binding`.

### Testing conventions
- Framework is Swift Testing (`@Test`, `#expect`), not XCTest-first style.
- Group tests by behavior (error paths, gross/net modes, audit logs, etc.).
- Cover happy path and failure path.
- Use small helpers/builders for repeated setup.

## Agent Working Norms
- Use `REPO_MAP.md` first for targeted navigation.
- Do not "fix" SourceKit indexing noise unless it affects real build/test results.
- Do not assume player index implies team; map by player IDs/team assignments.
- Preserve Codable compatibility and persisted model shapes when editing storage models.

## Safety and Commit Hygiene
- Never commit `DerivedData/`, `.xcuserstate`, or local plist artifacts.
- Stage only files related to the requested task.
- Run relevant tests before proposing a commit.
- Keep commit messages concise (this repo often uses `Swarm x.y` prefixes).

## Useful References
- `CLAUDE.md` for architecture details and historical decisions.
- `REPO_MAP.md` for quick code navigation.
- `docs/build_test_launch_readiness.md` for local bootstrap/no-sign validation and UI route map.
- `docs/prd/mvp-phase-1.md` and `docs/prd/games/*.md` for game rules.

## Current Feature Notes (March 2026)
- Course search:
  - Explicit errors surfaced for missing/invalid API key and non-200 responses.
  - Search footer now displays error text instead of silent empty result.
- Round messaging:
  - Round summary and history detail support texting scorecard + settlement.
  - Send flow includes recipient preview confirmation before opening message composer.
- Buddy data:
  - Buddies include optional `phoneNumber`, normalized before persistence.
  - Settings has `Manage Buddies` view for add/edit/delete.
- Round persistence:
  - Only completed rounds move into active history on clear.
  - History supports archive workflow (archive one, archive all, grouped archive view, delete one, delete all archived).
- Scorecard UX:
  - Added SI column and per-player stroke markers.
  - Added bottom player-name header for column reference.
- Debug-only helper:
  - `SaturdayScoringView` has `Dev: Auto-Fill Remaining Holes` to complete rounds quickly for testing.
