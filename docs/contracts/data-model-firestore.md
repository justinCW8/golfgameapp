# Firestore Data Model (MVP)

## Collections
- `rounds/{roundId}`
- `rounds/{roundId}/games/{gameId}`
- `rounds/{roundId}/games/{gameId}/holes/{holeNumber}`

## `rounds/{roundId}` document
- `createdAt` (timestamp/epoch seconds)
- `courseName` (string)
- `primaryGame` (string enum: `six_point_scotch`, `nassau`, `stableford`)
- `status` (string enum: `setup`, `active`, `complete`)
- `players` (array of objects):
- `id` (string UUID)
- `displayName` (string)
- `handicapIndex` (number)
- `team` (string nullable)

## `games/{gameId}` document
- `type` (string enum)
- `createdAt` (timestamp/epoch seconds)
- `status` (string)
- `state` (object; game-specific serialized state)

## `holes/{holeNumber}` document
- `number` (int)
- `score` (object; game-specific per-hole score)
- `events` (array; game-specific events such as `press`, `reroll`)
- `points` (object; awarded points by team)
