import Foundation
import Vision

/// Read only the name directly below the QR, not arbitrary text elsewhere in view.
enum BadgeNameReader {
    static func clean(_ text: String) -> String? {
        let name = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard (2...24).contains(name.count), name.unicodeScalars.contains(where: CharacterSet.letters.contains),
              name.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0) || " '-’·.".unicodeScalars.contains($0) }) else { return nil }
        let lower = name.lowercased()
        guard !["hacker", "mentor", "organizer", "volunteer", "sponsor", "hack the north"].contains(lower),
              !["badge id", "customize", "home apps", "start details", "player "].contains(where: lower.contains) else { return nil }
        return name
    }
    static func read(using handler: VNImageRequestHandler, below qr: CGRect) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        let region = CGRect(x: qr.midX - qr.width * 1.4, y: qr.minY - qr.height * 0.55,
                            width: qr.width * 2.8, height: qr.height * 0.53)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !region.isNull, region.width > 0, region.height > 0 else { return nil }
        request.regionOfInterest = region
        guard (try? handler.perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        for line in lines {
            guard let candidate = line.topCandidates(1).first, candidate.confidence >= 0.6,
                  let name = clean(candidate.string) else { continue }
            return name
        }
        return nil
    }
}
