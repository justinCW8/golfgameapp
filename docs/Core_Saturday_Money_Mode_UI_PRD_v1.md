# Core Saturday Money Mode --- UI PRD

Version: 1.0\
Status: Phase 1 (Money Game Mode)\
Last Updated: 2026-03-03

------------------------------------------------------------------------

# 1. Product Positioning

This product is optimized for:

> Four players standing on the first tee\
> Starting games in under 60 seconds\
> Keeping score with zero math disputes

This is NOT tournament software.\
This is a fast, clean, Saturday money-game engine.

Design priorities: - Minimal screens - Auto decisions where possible -
Single score entry surface - Multi-game support - Teams only when
required

------------------------------------------------------------------------

# 2. Navigation Structure

Bottom Navigation (Phase 1 Minimal):

-   Home
-   History
-   Profile

No club admin. No leaderboards. No configuration menus outside round
setup.

------------------------------------------------------------------------

# 3. Launch Screen

## State A --- No Active Round

Primary CTA: **Start Round**

Optional: Recent Players preview

## State B --- Active Round

Primary CTA: Resume Round

Secondary: Start New Round

------------------------------------------------------------------------

# 4. Round Creation Flow

Maximum 4 screens.

------------------------------------------------------------------------

## Screen 1 --- Players

Purpose: Define participants and handicaps.

Per Player: - Name - Course handicap (editable inline) - Guest indicator

Behavior: - Show recent players first - Quick add support - Manual
handicap entry allowed

CTA → Continue

------------------------------------------------------------------------

## Screen 2 --- Select Games

Multi-select cards:

-   Nassau
-   Six Point Scotch
-   Stableford

System logic:

IF selected games require teams → show Team Screen\
IF not → skip to Game Settings

------------------------------------------------------------------------

# 5. Team Logic (UI-Driven)

## When Team Screen Appears

Show Team Setup Screen IF: - 4 players selected AND - At least one
selected game requires teams (Nassau 2v2 or Scotch)

Do NOT show team screen if: - Only Stableford selected - 2 players
selected (Nassau defaults to 1v1)

------------------------------------------------------------------------

## Auto-Pairing Rule (4 Players)

1.  Sort players by course handicap (ascending)
2.  Team A = lowest + highest
3.  Team B = middle two

Display banner: "Balanced teams created based on handicap"

Allow manual drag-and-drop override.

------------------------------------------------------------------------

## 3 Player Rule (Phase 1)

-   Disable Scotch
-   Allow 1v1 Nassau
-   Allow Stableford individual

No 3-player team logic in v1.

------------------------------------------------------------------------

## Screen 3 --- Teams (Conditional)

Layout:

Team A \| Team B\
Drag to swap players

Display total team handicap indicator.

CTA → Continue

------------------------------------------------------------------------

## Screen 4 --- Game Settings (Unified)

Expandable panels per selected game.

### Nassau

-   Front stake
-   Back stake
-   Overall stake
-   Auto press toggle

### Scotch

-   1-2-3 rotation (default)
-   Carryover toggle

### Stableford

-   Standard
-   Modified

All configuration on one screen. No deep drilldowns.

CTA → Start Round

------------------------------------------------------------------------

# 6. Live Round Screen

Single scoring surface.

## Layout

Top: Hole \# \| Par \| HCP

Middle: Score entry grid (single source of truth)

Bottom: Game Strip (horizontal scroll)

------------------------------------------------------------------------

## Game Strip Behavior

Each selected game appears as pill:

\[Nassau: 1 Up\]\
\[Scotch: +3\]\
\[Stableford: Justin +14\]

Tap pill → expand inline panel (not new screen).

No duplicate score entry per game.

------------------------------------------------------------------------

# 7. Multi-Game Engine Contract

RoundSession - players\[\] - teams\[\] (optional) - hole_results\[\]

GameInstance\[\] - type - config - state

Score entry updates: hole_results → triggers recalculation in all active
games.

UI reads from: game.state

------------------------------------------------------------------------

# 8. End of Round Screen

Tabbed summary:

-   Nassau Settlement
-   Scotch Results
-   Stableford Leaderboard

Clear per-player settlement display. No raw match math exposed.

------------------------------------------------------------------------

# 9. UI Guardrails

-   No more than 4 setup screens
-   No unnecessary popups
-   No gambling visuals
-   Dark, clean, neutral aesthetic
-   Money exposure visible but subtle

------------------------------------------------------------------------

# 10. Phase 1 Exclusions

Not included in Saturday Mode:

-   Club admin controls
-   Tee sheet integration
-   GHIN sync
-   Payment processing
-   Season leaderboards
-   5+ player formats

These are future platform extensions.

------------------------------------------------------------------------

# 11. Success Criteria

-   Setup time under 60 seconds
-   1 tap per hole scoring
-   Auto-balanced teams
-   Accurate multi-game scoring
-   Clear end-of-round settlement

If four players can: 1. Start in under a minute\
2. Keep score easily\
3. Settle instantly

The product wins.
