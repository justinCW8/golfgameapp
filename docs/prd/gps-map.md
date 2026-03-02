# GPS On-Course Map — PRD

## 1. Overview

The GPS Map view gives players a live satellite overhead view of the course during a round. It shows the player's current position, hole markers (tee + green) for all 18 holes, and highlights the current hole being played.

No proprietary mapping SDK is required. MapKit in hybrid/satellite mode provides the course visual layer automatically — the actual course layout is visible from satellite imagery without any overlay data.

---

## 2. User Flow

```
Active Round → "Map" tab (or button in scoring screen)
  → MapKit satellite view centered on current hole
  → Player dot tracks live position (CLLocationManager)
  → Hole markers visible for all 18 holes
  → Current hole highlighted
  → Tap any hole marker → shows hole number + par
  → Auto-centers on player when within course bounds
```

---

## 3. Technical Approach

### 3.1 Map Layer

**MapKit** in `.hybrid` mode (satellite imagery + road labels):
- Course layout is visually present from satellite tiles — no overlay data needed
- Works for every course with zero additional data
- Fully offline once tiles are cached by the OS

```swift
Map(
    coordinateRegion: $region,
    interactionModes: .all,
    showsUserLocation: true,
    annotationItems: holeAnnotations
) { annotation in
    MapAnnotation(coordinate: annotation.coordinate) {
        HoleMarkerView(annotation: annotation, isCurrent: annotation.hole == currentHole)
    }
}
.mapStyle(.hybrid)
```

### 3.2 Player Position

`CLLocationManager` streams GPS coordinates to the ViewModel:
- Updates player dot on map in real time
- Authorization: `NSLocationWhenInUseUsageDescription`
- Accuracy: `kCLLocationAccuracyBest` during map view, reduced when map is not visible (battery)
- If location unavailable: show last known position or "GPS unavailable" banner

### 3.3 Hole Markers

Tee box and green GPS coordinates come from `golfapi.io` `HoleDetail` (loaded at round start, stored in `RoundSetup`).

Each hole renders two annotations:
- **Tee marker**: circle with hole number
- **Green marker**: flag icon

Current hole highlights in a distinct color (e.g. yellow). Completed holes dim. Future holes use standard style.

```swift
struct HoleAnnotation: Identifiable {
    var id: String        // e.g. "hole-7-tee"
    var hole: Int
    var type: MarkerType  // .tee / .green
    var coordinate: CLLocationCoordinate2D
}
```

### 3.4 Distance to Pin

When player position is known and green coordinate is available:
- Show distance to current hole's green center in yards (bottom overlay)
- `CLLocation.distance(from:)` → meters → yards conversion

---

## 4. MapViewModel

```swift
@MainActor
final class CourseMapViewModel: ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published var playerLocation: CLLocationCoordinate2D?
    @Published var distanceToGreenYards: Int?
    @Published var locationError: String?

    var holeAnnotations: [HoleAnnotation]
    var currentHole: Int

    func startTracking()
    func stopTracking()
    func centerOnPlayer()
    func centerOnHole(_ hole: Int)
}
```

---

## 5. UI Layout

```
┌─────────────────────────────┐
│  [< Back]     Hole 7 — Par 4│  ← header bar
│─────────────────────────────│
│                             │
│     MapKit Satellite View   │
│                             │
│  ● (player dot)             │
│                    ⛳ 7     │
│                             │
│─────────────────────────────│
│  📍 312 yds to pin          │  ← distance overlay
│  [Center on Me] [Center: H7]│  ← buttons
└─────────────────────────────┘
```

- Header: current hole + par
- Map: full width, most of screen height
- Bottom bar: distance to pin + two action buttons
- Hole markers: tappable, show callout with hole # + par

---

## 6. Fallback Behavior

| Condition | Behavior |
|-----------|----------|
| No GPS permission | Prompt user; if denied, show map without player dot |
| No hole GPS coordinates | Show map without hole markers; satellite view still works |
| No network (tile cache miss) | Standard MapKit offline behavior |
| Poor GPS accuracy | Show accuracy radius circle around player dot |

---

## 7. Battery Considerations

- `CLLocationManager` uses `kCLLocationAccuracyBest` only while map view is active
- Drops to `kCLLocationAccuracyHundredMeters` when map is backgrounded
- No background location mode required (no persistent tracking)

---

## 8. Swarm Breakdown

| Swarm | Scope |
|-------|-------|
| **2.10** | `CourseMapViewModel` + `CourseMapView` wired into scoring screen as a tab/sheet |

---

## 9. Permissions Required

Add to `Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>GolfGame uses your location to show your position on the course and distance to the pin.</string>
```

---

## 10. Out of Scope

- Background location tracking / shot tracking
- Shot distance measurement (Arccos-style)
- Wind data
- 3D course flyover
- Hazard overlays
- Yardage book / layup distances
- Course routing (suggested path)
