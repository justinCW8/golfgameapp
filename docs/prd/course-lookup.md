# Course Setup — PRD

## 1. Overview

Course setup uses the device camera and Apple's built-in **Vision framework** (`VNRecognizeTextRequest`) to read a physical scorecard. The user photographs the scorecard (or course rating placard), the app extracts par, stroke index, slope, and course rating via OCR, and the user reviews/corrects before confirming.

No external API, no subscription cost, works fully offline.

---

## 2. User Flow

```
New Round → Players → Course Setup
  → "Scan Scorecard" button
  → Camera sheet opens (UIImagePickerController or PhotosPicker)
  → User photographs scorecard
  → Vision OCR runs on-device
  → Parsed data shown in review screen
  → User corrects any misreads (inline editable fields)
  → Enter course name, tee color, slope, rating manually if not detected
  → "Confirm" → hole data stored in RoundSetup
  → Teams → Start Round
```

---

## 3. What the Camera Captures

Two photographs may be needed depending on the scorecard layout:

| Photo | Contains |
|-------|----------|
| **Front of scorecard** | Holes 1–9: par, stroke index (HCP row), yardage per tee |
| **Back of scorecard** | Holes 10–18: par, stroke index, slope, course rating per tee |

For MVP: one photo attempt, user manually fills any gaps in the review screen.

---

## 4. Vision OCR Approach

Apple Vision framework — no entitlements, no cost, fully on-device.

```swift
import Vision

func recognizeText(in image: UIImage) async -> [String] {
    guard let cgImage = image.cgImage else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false   // numbers — skip spell check
    let handler = VNImageRequestHandler(cgImage: cgImage)
    try? handler.perform([request])
    return request.results?
        .compactMap { $0.topCandidates(1).first?.string } ?? []
}
```

Returns an array of recognized text strings (one per detected text block).

---

## 5. Parsing Strategy

Scorecards are tabular. Vision returns text blocks in approximate reading order (top-left to bottom-right). The parser looks for known row labels to anchor the table:

**Row label patterns to detect:**
- Par row: `"Par"`, `"PAR"`
- Stroke index row: `"Hcp"`, `"HCP"`, `"Hdcp"`, `"Handicap"`, `"SI"`, `"Stroke Index"`
- Slope: `"Slope"` followed by a 2–3 digit number (55–155)
- Course rating: `"Rating"`, `"CR"` followed by a decimal number (60.0–80.0)

**Parsing steps:**
1. Find the Par row — collect the next 9 or 18 integers after it
2. Find the Stroke Index row — collect next 9 or 18 integers (must be 1–18, all unique)
3. Find Slope value (int 55–155)
4. Find Course Rating value (decimal 60.0–80.0)
5. Validate: par values must be 3, 4, or 5; SI must be a permutation of 1–9 (or 1–18)

Anything that fails validation shows as blank in the review screen for manual entry.

---

## 6. Review Screen

After OCR, user sees a scrollable table to verify:

```
Course Name:  [Pebble Beach         ]   ← text field
Tee:          [● Blue  ○ White  ○ Gold  ○ Red]
Slope:        [131]
Rating:       [74.2]

Hole    Par    SI
  1      [4]   [11]
  2      [5]   [ 3]
  3      [4]   [ 7]
  ...
  9      [3]   [ 9]
 10      [4]   [ 8]
  ...
 18      [5]   [ 2]

[Rescan]           [Confirm →]
```

- Each Par and SI field is an inline number stepper or text field (editable)
- Par constrained to 3–5
- SI constrained to 1–18; duplicate SI values flagged in red
- Slope and Rating editable text fields
- "Rescan" reopens camera
- "Confirm" disabled until all 18 holes have valid par + SI

---

## 7. Data Models

```swift
struct ScannedCourseData {
    var courseName: String
    var teeColor: String
    var slope: Int?
    var courseRating: Double?
    var holes: [ScannedHole]   // 18 entries
}

struct ScannedHole {
    var holeNumber: Int
    var par: Int?              // nil = not detected, user must fill
    var strokeIndex: Int?      // nil = not detected, user must fill
}
```

Confirmed data maps directly to existing `CourseHoleStub` and `RoundSetup` fields.

---

## 8. ScanViewModel

```swift
@MainActor
final class ScanViewModel: ObservableObject {
    @Published var scannedData: ScannedCourseData
    @Published var isScanning: Bool
    @Published var error: String?

    func processImage(_ image: UIImage) async
    func updatePar(hole: Int, par: Int)
    func updateSI(hole: Int, si: Int)
    func confirmedCourseConfig() -> [CourseHoleStub]
    var isValid: Bool   // all 18 holes have par + SI, SI has no duplicates
}
```

---

## 9. Integration with RoundSetup

Same as before — after confirmation:
```swift
RoundSetup.courseHoles = viewModel.confirmedCourseConfig()
RoundSetup.courseName = scannedData.courseName
RoundSetup.teeColor = scannedData.teeColor
RoundSetup.slope = scannedData.slope
RoundSetup.courseRating = scannedData.courseRating
```

`RoundScoringViewModel` consumes `courseHoles` with no changes needed.

---

## 10. Saved Courses

After a round, offer "Save this course" — stores confirmed `ScannedCourseData` in `UserDefaults` (same pattern as `BuddyStore`). On next round, saved courses appear as quick-select chips above the "Scan Scorecard" button. Eliminates re-scanning for the same club.

```swift
@MainActor
final class CourseStore: ObservableObject {
    @Published var courses: [SavedCourse] = []

    func save(_ data: ScannedCourseData)
    func remove(at offsets: IndexSet)
    private func persist() / load()
}

struct SavedCourse: Codable, Identifiable {
    var id: UUID
    var name: String
    var teeColor: String
    var slope: Int?
    var courseRating: Double?
    var holes: [CourseHoleStub]
    var savedAt: Date
}
```

---

## 11. Camera Permission

Add to `Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>GolfGame uses the camera to scan your scorecard and import hole data.</string>
```

---

## 12. Swarm Breakdown

| Swarm | Scope |
|-------|-------|
| **2.8** | Vision OCR service, parser, `ScanViewModel`, `ScannedCourseData` model |
| **2.9** | `ScanScorecardView` (camera + review screen) wired into round setup |
| **2.10** | `CourseStore` (saved courses), quick-select UI above scan button |

---

## 13. Known Limitations (MVP)

- Scorecard layouts vary — some cards will OCR poorly due to fonts, glare, or unusual table structure
- User is expected to correct misreads in the review screen
- No automatic front/back nine split detection — if only 9 holes parse correctly, user fills the other 9 manually
- Yardage per hole is not captured (not needed for Six Point Scotch or Stableford scoring)

---

## 14. Out of Scope

- Real-time course database lookup
- GHIN integration
- Automatic tee color detection from card color
- Yardage tracking
