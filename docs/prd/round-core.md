# Round Core — PRD

## 1. Overview

The Round Core covers the full lifecycle of a scored golf round: setup, hole-by-hole scoring, persistence, and end-of-round summary.

---

## 2. Setup Wizard Flow

Round setup is a sequential wizard:

1. **Event selection** — optional; rounds can be standalone or attached to an event
2. **Player selection** — 4 players required for Six Point Scotch
3. **Course & tee box selection** — selects hole pars and stroke indexes
4. **Team assignment** — assign players to Team A and Team B (2 each)

On completion, a `RoundSession` is written to `AppSessionStore` as the active session.

---

## 3. Tee Order Logic

- **Hole 1:** Manual tee toss — scorer selects which team tees first
- **Hole 2+:** Leading team on the current nine tees first
- **Tie:** Original tee order from tee toss persists until a team leads
- **Hole 10:** No new tee toss — tee order continues from Hole 9 logic

Tee order is **display-only** and must never affect match differential or engine scoring.

---

## 4. Stroke Allocation

Handicap strokes per hole are computed as:

```
courseHandicap = floor(handicapIndex)
strokesOnHole = 1 if holeStrokeIndex <= courseHandicap, else 0
```

- `handicapIndex` is stored per player in `PlayerSnapshot`
- `holeStrokeIndex` is the stroke index for that hole (1–18), sourced from `CourseHoleStub`
- Net score = Gross score − strokesOnHole

The UI shows:
- A green "+N" stroke badge next to each player's name when they receive strokes on the current hole
- A live "Gross X → Net Y (+N strokes)" preview during score entry

---

## 5. Persistence Model

Round state is persisted in `AppSessionStore` via `RoundSession`:

| Field | Description |
|-------|-------------|
| `setup` | `RoundSetup` — players, course, tee box, pairings |
| `currentHole` | Int (1–18) |
| `teeTossFirst` | `TeamSide?` — which team teed first on hole 1 |
| `isCurrentHoleScored` | Bool |
| `isRoundEnded` | Bool |
| `scoredHoleInputs` | `[SixPointScotchHoleInput]` — replay source |
| `holeResults` | `[HoleResult]` — gross/net by player per hole |
| `strokesByPlayerByHole` | `[HoleStrokeAllocation]` — stroke counts per hole |

**Engine rebuild on restore:** The engine does not serialize its own state. On session restore, `RoundScoringViewModel` replays all `scoredHoleInputs` through a fresh `SixPointScotchEngine` to reconstruct the running totals and nine ledgers.

---

## 6. End-of-Round Workflow

1. Scorer taps **"End Round"** button
2. Confirmation dialog appears ("This will end the round and clear the current session.")
3. On confirm:
   - `viewModel.endRound()` is called — sets `isRoundEnded = true`, persists state
   - `FinalRoundSummaryView` sheet is presented
4. Summary sheet shows:
   - Winner declaration (`matchStatusDisplay` — final format)
   - Team points totals
   - Holes played count
   - Navigation link to `RoundScorecardView` (hole-by-hole review)
   - Player gross/net totals
5. Scorer taps **"Done"**:
   - `viewModel.endRoundAndClearSession()` — clears `AppSessionStore.activeRoundSession`
   - Dismisses back to `RoundHomeView`

After clearing the session, `RoundHomeView` shows no active round.

---

## 7. Round Restore Behavior

On app relaunch with an active session:
- `RoundScoringViewModel.init` calls `restoreFromSession()`
- Engine replays all stored hole inputs
- UI state (`currentHole`, `hasScoredCurrentHole`, `teeTossFirst`, `isRoundEnded`) restores from session fields
- If `isRoundEnded == true`, scoring controls are read-only and the summary sheet can be re-opened
