# GolfGameApp — MVP Phase 1 Product Requirements Document

## 1. Overview

MVP Phase 1 delivers a fully playable, locally persisted 4-player golf game system with:

- Six Point Scotch match play engine
- Stableford event leaderboard (multi-group)
- Per-player handicap stroke allocation
- Round persistence and restoration
- Match status tracking
- Clean scoring UX
- End round workflow

This phase is local-first (no backend sync).

---

## 2. Goals of MVP Phase 1

### Primary Goal
Deliver a stable, rules-accurate, playable Six Point Scotch round with full handicap correctness and match tracking.

### Secondary Goal
Support Stableford event scoring across multiple groups.

---

## 3. In Scope

### 3.1 Six Point Scotch

- 4 players
- 2 fixed teams
- 18 holes
- Handicap stroke allocation per hole
- Net scoring
- Press / Roll / Re-roll mechanics
- Multiplier application
- Running match differential display
- Per-hole audit log
- Stroke indicators per hole
- Prox winner selection (button-based)
- Start Round button
- Next Hole button
- End Round (with confirmation)
- Round persistence & restoration

---

### 3.2 Match Status Display

Display rules:

- If tied → "All Square"
- If Team A leading → "<Team A Names> +N"
- If Team B leading → "<Team B Names> +N"

Rules:

- Never show negative values
- Never show both team totals
- Never use tee order to derive match status
- Match differential derives ONLY from engine totals

---

### 3.3 Handicap & Stroke Allocation

- Handicap Index stored per player
- Course handicap = floor(HI)
- Stroke allocation per hole based on Stroke Index
- Net = Gross - strokes
- UI shows:
    - Player getting stroke on hole (indicator)
    - Net preview during score entry

---

### 3.3b Press / Roll / Re-roll Rules

#### Press
- **Who:** Only the trailing (losing) team may call a press
- **When:** Before the leading team tees off on that hole
- **Effect:** Doubles the point value for that hole (multiplier ×2 per active press)
- **Limit:** Maximum 2 presses per nine holes
- **Reset:** Press count resets at hole 10 (separate front/back nine ledger)
- **Carries:** Active presses carry into scoring for that hole only

#### Roll
- **Who:** Only the trailing (losing) team may call a roll
- **When:** After the leading team tees off, but before the trailing team tees off
- **Effect:** Doubles the point value for that hole (stacks with press multiplier)
- **Constraint:** Roll window closes once trailing team tees off

#### Re-roll
- **Who:** Only the leading (winning) team may call a re-roll
- **When:** After BOTH teams have teed off (roll must already be active)
- **Effect:** Doubles again (stacks with roll and press)
- **Constraint:** Re-roll window closes once hole is scored
- **Requires:** An active roll on that hole

#### Multiplier Formula
```
multiplier = 2 ^ (activePresses + rollFlag + rerollFlag)
```
Examples:
- 1 press → ×2
- 1 press + roll → ×4
- 1 press + roll + reroll → ×8
- 2 presses + roll + reroll → ×16

#### Timing Summary
| Action  | Who            | Window                                      |
|---------|----------------|---------------------------------------------|
| Press   | Trailing team  | Before leading team tees off                |
| Roll    | Trailing team  | After leader tees off, before trailer tees off |
| Re-roll | Leading team   | After BOTH teams tee off, before scoring    |

---

### 3.4 Tee Order Logic

- Manual selection on first hole
- After Hole 1:
    - Leading team tees first
    - If tied → original tee order persists
- No second tee toss on Hole 10
- Tee order must NOT affect match differential

---

### 3.5 Round Persistence

Must persist:

- Round setup
- Current hole
- Scored hole inputs
- Hole results
- Stroke allocations
- Engine state (rebuildable)
- Round ended flag

On app relaunch:
- Engine rebuilds from stored hole inputs
- UI restores correctly

---

### 3.6 Stableford Event (Swarm 3)

- Multi-group event
- Stableford engine
- Individual leaderboard
- Aggregated scoring across groups
- Local-only storage

---

## 4. Out of Scope (Phase 1)

- Backend sync
- Real course database
- GHIN integration
- Tee sheet integration
- Payments
- Multi-club support
- Push notifications
- Authentication
- Social sharing
- Historical stats tracking
- Cross-device sync

---

## 5. Technical Architecture

### Engine Layer
- SixPointScotchEngine
- StablefordEngine

### ViewModel Layer
- RoundScoringViewModel
- EventGroupScoringViewModel

### Persistence
- SessionModel (local)
- Rebuild engine from stored hole inputs

### UI
- SwiftUI
- Centralized matchStatusText
- No business logic inside views

---

## 6. Success Criteria

MVP is complete when:

- Full 18-hole Scotch round can be played without crash
- Handicap strokes are accurate
- Press / Roll / Re-roll validated correctly
- Match status is consistent and correct
- Round can be ended early
- Round restores after app restart
- Event leaderboard aggregates correctly
- Clean simulator build passes
- Tests pass

---

## 7. Commit Discipline

All feature changes must:

- Be scoped to a Swarm
- Build cleanly
- Be simulator validated
- Stage only relevant Swift files
- Avoid committing userstate / DerivedData
- Include descriptive commit messages

---

## 8. Definition of Phase 1 Complete

Phase 1 is complete when:

- Six Point Scotch is rules-accurate
- Stableford event works
- UX is clean and intuitive
- PRDs are written and committed
- Repo is clean and synced to GitHub
