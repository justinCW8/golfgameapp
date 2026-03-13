# Game Rules Source of Truth

## Six Point Scotch
- Buckets per hole:
  - Low Man: 2
  - Low Team: 2
  - Birdie: 1
  - Prox: 1
- Tie behavior:
  - Low Man tie: push
  - Low Team tie: push
  - Birdie both/neither: push
  - Prox tie: push
- Special:
  - Umbrella: sweep all 4 buckets => 12 raw points.
  - Multiplier: `2^(activePresses + roll + reroll)`.
  - Press: trailing side only, max 2 per nine.
  - Roll: trailing side only.
  - Re-roll: only if roll exists, and by leading side.

## Nassau
- Three simultaneous matches: Front, Back, Overall.
- Match play by net scoring.
- Auto-press optional by trigger.
- Manual press by trailing side.

## Stableford
- Modes: Individual, Team 2v2.
- Standard table:
  - Eagle 4, Birdie 3, Par 2, Bogey 1, Double+ 0.
- Modified table:
  - Eagle 5, Birdie 2, Par 0, Bogey -1, Double -3.
- Higher total points wins.

## Skins
- Modes:
  - Gross: lowest raw score wins hole skin.
  - Net: lowest handicap-adjusted score wins hole skin.
  - Both: gross and net tracks both run.
- Unique low score required for a skin.
- Carryover:
  - On: tied skins roll.
  - Off: tied skins void.

## Stroke Play
- Formats:
  - Individual
  - 2v2 Best Ball
  - Team Best Ball
- Tracks gross/net and format-specific standings.
