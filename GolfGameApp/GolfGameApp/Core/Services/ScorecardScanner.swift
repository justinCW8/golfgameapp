import Vision
import UIKit

struct ScorecardScanner {
    /// Runs Vision OCR on the given image and returns recognized text strings
    /// in approximate reading order (top-left to bottom-right).
    func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations: [(text: String, box: CGRect)] = (request.results ?? []).compactMap {
                    guard let observation = $0 as? VNRecognizedTextObservation,
                          let text = observation.topCandidates(1).first?.string else { return nil }
                    return (text: text, box: observation.boundingBox)
                }

                let strings = observations
                    .sorted { lhs, rhs in
                        // Group by visual rows first (top to bottom), then left to right.
                        let rowDelta = abs(lhs.box.midY - rhs.box.midY)
                        if rowDelta > 0.02 { return lhs.box.midY > rhs.box.midY }
                        return lhs.box.minX < rhs.box.minX
                    }
                    .map(\.text)
                continuation.resume(returning: strings)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
