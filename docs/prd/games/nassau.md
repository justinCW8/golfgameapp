# Nassau Game Module PRD

Version: 1.0\
Status: Draft -- Engineering Ready\
Last Updated: 2026-03-03

------------------------------------------------------------------------

# 1. Executive Summary

The Nassau is one of the most widely played betting formats in private
club golf. It consists of three independent match-play bets:

-   Front 9
-   Back 9
-   Overall 18

However, real-world Nassau games vary significantly by club and group,
particularly around: - Press logic - Handicap allowances - Carryovers -
Team formats

This PRD defines a configurable, production-grade Nassau engine suitable
for: - Private club deployments - Member money games - Tournament side
games - White-label SaaS environments

The system must support flexible configuration while maintaining
clarity, transparency, and dispute-free settlement.

------------------------------------------------------------------------

# 2. Core Game Structure

## 2.1 Standard Nassau

Three concurrent bets: - Front 9 (Holes 1--9) - Back 9 (Holes 10--18) -
Overall (Holes 1--18)

Each bet is independently won, lost, or pushed.

## 2.2 Match Play Scoring

Per hole: - Win hole → +1 - Lose hole → -1 - Tie hole → 0

A segment is closed when a side is: \> Up more holes than remaining.

Example: 2 up with 1 to play → segment closed (2&1)

------------------------------------------------------------------------

# 3. Supported Formats

## 3.1 Singles (1v1)

Gross or net match play.

## 3.2 Fourball (2v2 Best Ball)

Most common club format. Lowest net or gross score per team counts.

## 3.3 2v2 Aggregate

Combined team score per hole.

## 3.4 Scramble Nassau

One team ball.

## 3.5 Optional: Multi-player Round Robin

Each player vs each (advanced configuration).

------------------------------------------------------------------------

# 4. Handicap Engine

## 4.1 Modes

-   Gross (no strokes)
-   Net 100%
-   Net 90%
-   Custom % allowance

## 4.2 Stroke Allocation

-   Based on course handicap
-   Allocated by hole handicap index
-   Difference method (low man baseline)
-   Configurable allowance percentages

System must: - Display stroke pops per hole - Calculate net hole winner
automatically - Support team allowance rules

------------------------------------------------------------------------

# 5. Press Engine

Press logic is critical and must be robust.

## 5.1 Automatic Press

Trigger when a side goes: - 1 down - 2 down (default) - 3 down -
Disabled

New bet starts from next hole.

## 5.2 Manual Press

-   Losing side only (configurable)
-   Either side (configurable)
-   Must occur before next tee shot
-   Stake same or multiplier

## 5.3 Limits

-   Unlimited presses
-   1 per segment
-   2 per segment
-   Custom limit

Presses must be: - Nested under parent segment - Independently tracked -
Independently settled

------------------------------------------------------------------------

# 6. Carryover Rules

Configurable behavior for tied segments:

Options: - Push (no carry) - Carry Front into Back - Carry into
Overall - Custom club rule

------------------------------------------------------------------------

# 7. Settlement Logic

At round completion:

System computes: - Front result - Back result - Overall result - Each
press result

Settlement must: - Calculate per-team net - Split evenly in team
format - Show full breakdown ledger

Optional integrations (future): - Venmo - Club account billing

------------------------------------------------------------------------

# 8. UX Requirements

## 8.1 Setup Flow

1.  Select Nassau
2.  Choose format
3.  Set stakes
4.  Configure handicap
5.  Configure press rules
6.  Confirm max exposure
7.  Start round

## 8.2 In-Round

Live scoreboard must show:

-   Front status
-   Back status
-   Overall status
-   Nested press bets

Auto-press must trigger without user friction.

Manual press requires confirmation modal.

## 8.3 End of Round

Settlement screen must show: - Each segment result - Each press result -
Final per-player net

No raw match math should be required from users.

------------------------------------------------------------------------

# 9. Data Model (High-Level)

Game - id - format - stake_config - handicap_config - press_config

Segment - id - type (front/back/overall) - starting_hole - ending_hole -
status

Press - id - parent_segment_id - starting_hole - stake - status

HoleResult - hole_number - gross_scores - net_scores - winner

Settlement - player_id - amount_won - amount_lost - net

------------------------------------------------------------------------

# 10. Risk Controls

Because Nassau involves monetary stakes:

-   Stake confirmation required
-   Max exposure preview before round
-   Optional "Points Only" mode
-   Admin override for club environments

------------------------------------------------------------------------

# 11. Edge Cases

Must support:

-   Conceded holes
-   Conceded matches
-   Weather-shortened rounds
-   9-hole Nassau only
-   Player withdrawal mid-round

------------------------------------------------------------------------

# 12. Acceptance Criteria

-   Match play scoring correct
-   Handicap strokes correctly applied
-   Press triggers function accurately
-   Settlement ledger accurate to the dollar
-   Works for 1v1 and 2v2 formats
-   Clear and dispute-free UI

------------------------------------------------------------------------

# 13. Future Extensions

-   Nassau + Skins combo
-   Tournament-integrated Nassau
-   Season-long Nassau tracking
-   AI press recommendations
-   Cross-club leaderboards

------------------------------------------------------------------------

# Strategic Positioning

Most scoring systems handle basic match play. Very few handle nested
presses cleanly.

If implemented correctly, this Nassau module becomes a major
differentiator in private club environments and a core monetizable
feature within a golf SaaS platform.
