# Six Point Scotch — Game PRD

## 1. Overview

Six Point Scotch is a 4-player, 2-team match-play golf format played over 18 holes. Each hole has 6 raw points at stake, distributed across four scoring buckets. Points are multiplied by a per-hole multiplier driven by presses, rolls, and re-rolls.

- **Players:** 4 (2 per team)
- **Teams:** Team A vs Team B (fixed for the round)
- **Holes:** 18, tracked as front nine (1–9) and back nine (10–18)
- **Scoring:** Net scores (Gross − handicap strokes per hole)

---

## 2. Points Buckets

Each hole awards up to 6 raw points, split across four independent buckets:

| Bucket | Points | Winner Condition |
|--------|--------|-----------------|
| Low Man | 2 pts | Player with the lowest net score on the hole |
| Low Team | 2 pts | Team whose best (lowest) net score beats the other team's best |
| Natural Birdie | 1 pt | Any player who scores net birdie or better (gross birdie without a handicap stroke) |
| Prox | 1 pt | Player closest to the pin on par-3 holes (manually selected) |

**Tie rules:**
- Low Man tie → points split (1 pt each)
- Low Team tie → points split (1 pt each)
- Natural Birdie → awarded to the achieving player's team; both teams can score it
- Prox tie or no selection → no points awarded

---

## 3. Umbrella Rule

If one team wins all four buckets on a hole (all 6 raw points), the **Umbrella** fires:
- The losing team's points are swept to the winning team
- The winning team collects **12 raw points** before multiplier

---

## 4. Multiplier

The per-hole multiplier is:

```
multiplier = 2^(activePresses + rollFlag + rerollFlag)
```

- `activePresses`: number of presses currently open on this nine (max 2 per nine)
- `rollFlag`: 1 if a roll was called and accepted, else 0
- `rerollFlag`: 1 if a re-roll was called and accepted, else 0

The multiplier applies to the net raw points for the hole. A base hole with no presses/rolls has multiplier = 1.

---

## 5. Per-Nine Ledger

Points are tracked independently on two ledgers:

- **Front Nine:** Holes 1–9 — up to 2 presses allowed
- **Back Nine:** Holes 10–18 — fresh press count, up to 2 presses allowed

Each nine ledger tracks:
- `teamAPoints` (running total for the nine)
- `teamBPoints` (running total for the nine)
- `usedPresses` (0–2)

The final match score is the **sum** of both nine ledgers for each team.

---

## 6. Press Rules

A **press** opens a side bet on the remaining holes of the current nine.

- **Who can call:** The trailing team on the current nine
- **Timing window:** Must be called before the **leader** tees off on that hole
- **Limit:** Max 2 presses per nine (front and back tracked independently)
- **Resolution:** A press resolves at end of nine, independently from the main bet

When a press is active it increments `activePresses` in the multiplier for that hole.

---

## 7. Roll Rules

A **roll** doubles the stakes for the current hole.

- **Who can call:** The trailing team on the current nine
- **Timing window:** After the **leader** tees off, before the **trailer** tees off
- **Effect:** Adds 1 to the exponent in the multiplier (`rollFlag = 1`)
- **Re-roll:** The leading team may counter with a re-roll (same timing window, before trailer tees off), which adds another 1 to the exponent (`rerollFlag = 1`)

Only one roll and one re-roll are allowed per hole.

---

## 8. Match Status Display

Rules from PRD section 3.2:

- If tied → "All square thru N" (mid-round) or "All square — final" (post-round)
- If Team A leading → "\<Team A Names\> +N thru N" (mid-round) or "\<Team A Names\> wins +N" (post-round)
- If Team B leading → "\<Team B Names\> +N thru N" (mid-round) or "\<Team B Names\> wins +N" (post-round)

Additional constraints:
- Never show negative values
- Never show both team totals in the status string
- Differential derives only from engine totals (never from tee order)

---

## 9. MVP Implementation Notes

- Prox is button-selected per hole (not distance-based); any selection awards the point to the selecting player's team
- Natural Birdie uses gross score vs par (not net) — a player who takes a stroke to make net birdie does not earn the natural birdie point
- Roll/Re-roll tracking (`leaderTeedOff`, `trailerTeedOff`) is manual — the scorer taps buttons in the UI
- Engine replays from `scoredHoleInputs` on session restore (no serialized engine state)
- Press limit is enforced per nine by `NineLedger.usedPresses`
- Umbrella: if one team wins 6 raw points, opponent's points are swept (implemented in engine)
