# Schema Reference (Practical)

## Primary Models
- `SaturdayRound`:
  - course, players, holes, current hole, completion state
  - `activeGames: [SaturdayGameConfig]`
  - `holeEntries: [SaturdayHoleEntry]`
- `SaturdayGameConfig`:
  - `type: GameType`
  - optional config payload per game:
    - `nassauConfig`
    - `scotchConfig`
    - `stablefordConfig`
    - `skinsConfig`
    - `strokePlayConfig`
- `SaturdayHoleEntry`:
  - `holeNumber`
  - `grossByPlayerID`
  - `scotchFlags`
  - `nassauManualPressBy`
- `ScotchHoleFlags`:
  - `proxFeetByPlayerID`
  - `requestPressBy`
  - `requestRollBy`
  - `requestRerollBy`

## Storage
- `AppSessionStore`:
  - JSON persistence for round/session artifacts.
- `BuddyStore`:
  - `UserDefaults` key: `golf_buddies`
  - roster migration key: `golf_buddies_roster_version`
- `CourseStore`:
  - `UserDefaults` persistence.

## Engines (Pure Rules)
- `SixPointScotchEngine`
- `NassauEngine`
- `StablefordEngine`
- `SkinsEngine`
- `StrokePlayEngine`

## Replay Pattern
- Game state on scoring screens is derived by replaying saved hole entries through engines.
- Keep engine logic deterministic and side-effect free.
