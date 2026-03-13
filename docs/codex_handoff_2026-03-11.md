# Codex Handoff (March 11, 2026)

## Branch and PR
- Working branch: `codex/prep-filed-tests`
- PR: `https://github.com/justinCW8/golfgameapp/pull/3`

## Key Product Decisions Locked In
- Six Point Scotch tie handling:
  - Low Man: unique low net only; tie = no points.
  - Low Team: unique lower team net total only; tie = no points.
  - Birdie: natural birdie only; both teams birdie = push (no points).
  - Prox: one winner only; tie = no points; natural GIR eligibility required.
- Prox and Low Man winner display in audit:
  - Show one player first name when there is a single winner.
- Top scoring section:
  - Converted to colored game chips with larger typography.
- Rules visibility:
  - Rules info icon on active game chips in scoring view.
  - Rules button added in each game section of Game Settings (setup flow).
- Stableford rules copy:
  - Includes Standard and Modified point tables.
- Skins rules copy:
  - Explicit definitions for Gross, Net, and Both.

## Buddy Roster Migration
- `BuddyStore` now enforces a roster migration (`currentRosterVersion = 2`) and replaces old buddies with:
  - Chad R 4.9
  - Justin W 9.5
  - Dulla 11.3
  - Jamie P 11.4
  - K-Von 14.1
  - Shan 16.2
  - BC 16.4
  - Ginly 22.4

## Distribution Plan
- Recommended install path: TestFlight.
- Archive and upload from Xcode -> App Store Connect -> TestFlight testers.

## Notes for Next Session
- Local Xcode user UI state file is intentionally not committed:
  - `GolfGameApp/GolfGameApp.xcodeproj/project.xcworkspace/xcuserdata/juswaite.xcuserdatad/UserInterfaceState.xcuserstate`
