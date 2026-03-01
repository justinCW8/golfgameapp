# Six Point Scotch MVP Engine Notes

## Hole resolution
- Base value is `6` points per hole.
- Lower strokes wins the hole and receives all pending points.
- Tie behavior:
- If `rollOnTie = true`, pending points carry and add another 6 next hole.
- If `rollOnTie = false`, pending points split 50/50 and reset.

## Press
- A press can be opened for either team on a hole.
- A press has its own pending points, starts at 6, and resolves independently.
- In MVP logic, a press closes on first decisive award (or split if rolling is disabled).

## Reroll
- Reroll resets pending points to base (`6`) before resolving the hole.
- Applies to main match and all open presses.
