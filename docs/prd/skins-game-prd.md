# Skins Game Module -- Product Requirements Document (PRD)

**Status:** Draft -- MVP Ready\
**Owner:** Games Engine\
**Scope:** Individual and Team Skins inside mobile golf app\
**Dependencies:** Player model, Handicap engine, Course data model,
Score entry module

------------------------------------------------------------------------

# 1. Overview

The Skins game is a hole-by-hole competitive format where a player (or
team) wins a "skin" by having the lowest outright score on a hole.

If the hole is tied, the skin carries over to the next hole
(configurable).

This module must support:

-   Individual Skins
-   Team Skins (2v2 MVP optional)
-   Gross Skins
-   Net Skins
-   Gross + Net dual mode
-   Carryover on/off
-   Monetary or points-based skins

------------------------------------------------------------------------

# 2. Game Rules

## 2.1 Core Rule

For each hole: - Identify the lowest score. - If only one player/team
has the lowest score → they win the skin(s). - If tied → skin carries
over (if enabled). - Each hole starts with 1 base skin.

------------------------------------------------------------------------

## 2.2 Carryover Logic

If carryover_enabled = true:

-   tied hole → carryover_count += 1
-   next hole value = 1 + carryover_count
-   once won → carryover resets to 0

If carryover_enabled = false:

-   tied hole → skin is void
-   no carryover

------------------------------------------------------------------------

## 2.3 Gross vs Net

### Gross Skins

Uses raw score.

### Net Skins

net_score = gross_score - handicap_strokes_on_hole

Handicap strokes allocated: - Based on Course Handicap - Stroke Index
ranking - Standard USGA allocation logic

------------------------------------------------------------------------

## 2.4 Dual Mode (Gross + Net)

If scoring_mode = both:

Two parallel skin tracks are calculated: - Gross Skins - Net Skins

Each maintains separate carryover counters.

------------------------------------------------------------------------

# 3. UX Flow (Mobile)

## 3.1 Launch Flow

Launch Screen\
→ Select Game Type\
→ Skins

------------------------------------------------------------------------

## 3.2 Setup Flow

### Step 1 -- Format

-   Individual or Team
-   Gross / Net / Both
-   Carryover On / Off
-   Skin Value
    -   Fixed dollar value
    -   Points mode
    -   Custom amount

------------------------------------------------------------------------

### Step 2 -- Players

-   Select players
-   Import handicaps
-   Select tees
-   Auto-calculate course handicap
-   Confirm strokes per hole

------------------------------------------------------------------------

### Step 3 -- Teams (if enabled)

Options: - Auto pair high/low handicap - Manual selection - Randomize

------------------------------------------------------------------------

### Step 4 -- Confirm Game

Summary screen:

-   Format
-   Carryover setting
-   Skin value
-   Players
-   Teams (if applicable)

→ Start Round

------------------------------------------------------------------------

# 4. In-Round Experience

## 4.1 Hole Scoring Screen

For each hole display:

-   Hole number
-   Par
-   Stroke index
-   Carryover count
-   Skin value

After scores entered:

System evaluates: - Lowest gross or net - If tie → show "Skin Carries
Over" - If winner → highlight winner

------------------------------------------------------------------------

## 4.2 Live Standings

Display running totals:

  Player   Skins Won   \$ Value
  -------- ----------- ----------

If dual mode: Show Gross and Net columns separately.

------------------------------------------------------------------------

# 5. Game Engine Logic

## 5.1 Individual Gross Skins

for each hole: scores = get_scores(hole) lowest = min(scores) winners =
players_with_score(lowest) if len(winners) == 1: skins_awarded = 1 +
carryover award_to(winner) carryover = 0 else: if carryover_enabled:
carryover += 1 else: carryover = 0

------------------------------------------------------------------------

## 5.2 Net Skins Evaluation

net_score = gross_score - handicap_strokes_for_hole

Same winner logic applied to net values.

------------------------------------------------------------------------

## 5.3 Team Skins (MVP Optional)

Best Ball default: team_score = min(player_scores_on_team)

Then evaluate team vs team.

------------------------------------------------------------------------

# 6. Settlement Logic

At round completion:

total_value = skins_won \* skin_value

If multiplayer money mode:

Compute net transfers: - Determine who owes who - Simplify to minimum
transactions

Example:

Ryan owes Justin \$20\
Currie owes Ryan \$10

------------------------------------------------------------------------

# 7. Data Model

## 7.1 Game Object

{ game_id, game_type: "skins", format: "individual" \| "team",
scoring_mode: "gross" \| "net" \| "both", carryover_enabled: boolean,
skin_value: number, players: \[\], teams: \[\], status: "active" \|
"completed" }

------------------------------------------------------------------------

## 7.2 Hole Object

{ hole_number, par, stroke_index, scores: \[ { player_id, gross_score,
net_score } \], winner_id, skins_awarded, carryover_count }

------------------------------------------------------------------------

# 8. Edge Cases

  -----------------------------------------------------------------------
  Scenario                              Behavior
  ------------------------------------- ---------------------------------
  All players tie entire round          Final hole resolves carryover OR
                                        split (configurable)

  Player picks up                       Assign max score (ineligible)

  DQ player                             Remove from skins eligibility

  Shortened round                       End and settle current carryover

  Hole not completed by all             Delay evaluation
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 9. Admin Configuration (Future Phase)

-   Default carryover setting
-   Maximum carryover cap
-   Birdie-only skins
-   Handicap limits
-   Gross-only tournament mode

------------------------------------------------------------------------

# 10. MVP Scope

Included: - Individual skins - Carryover on/off - Gross + Net support -
Auto handicap allocation - Auto payout calculation - Clean mobile UX

Not included (Phase 2): - Press skins - Birdie-only skins - Multi-day
skins - Venmo integration - Tournament broadcast mode

------------------------------------------------------------------------

# 11. Strategic Role in Platform

Skins: - High engagement - Extremely common in private club play -
Simple but competitive - Easy to combine with Nassau and Stableford -
Drives recurring app usage

It is a foundational social game module.
