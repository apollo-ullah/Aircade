import Vision

struct BadgeScan {
    let payload: String
    let suggestedName: String?
}

/// The same local Vision path is used for camera frames and generated QR regression fixtures.
enum BadgeScanner {
    static func read(using handler: VNImageRequestHandler) -> BadgeScan? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        guard (try? handler.perform([request])) != nil,
              request.results?.count == 1, let observation = request.results?.first,
              let payload = observation.payloadStringValue, !payload.isEmpty, payload.utf8.count <= 4096 else { return nil }
        return BadgeScan(payload: payload, suggestedName: BadgeNameReader.read(using: handler, below: observation.boundingBox))
    }
}
