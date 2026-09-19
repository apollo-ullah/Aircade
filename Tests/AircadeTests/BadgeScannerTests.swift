import XCTest
import CoreImage
import Vision
@testable import Aircade

final class BadgeScannerTests: XCTestCase {
    private func qr(_ value: String) throws -> CIImage {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        return try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    }
    private func handler(_ values: [String]) throws -> VNImageRequestHandler {
        let images = try values.map(qr)
        let height = (images.map { $0.extent.height }.max() ?? 240) + 100
        let width = max(300, images.reduce(40) { $0 + $1.extent.width + 80 })
        var canvas = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        var x = CGFloat(40)
        for image in images {
            canvas = image.transformed(by: CGAffineTransform(translationX: x, y: 50)).composited(over: canvas)
            x += image.extent.width + 80
        }
        let cg = try XCTUnwrap(CIContext().createCGImage(canvas, from: canvas.extent))
        return VNImageRequestHandler(cgImage: cg, orientation: .up)
    }
    func testVisionReadsAnOpaqueBadgeWithoutOpeningItsURL() throws {
        let payload = "https://badge.example.invalid/hacker/test-only?code=fixture-123"
        let scan = try XCTUnwrap(BadgeScanner.read(using: handler([payload])))
        XCTAssertEqual(scan.payload, payload)
        XCTAssertNil(scan.suggestedName)
    }
    func testMultipleBadgesAreRejectedRatherThanSelectingSomeoneElse() throws {
        XCTAssertNil(BadgeScanner.read(using: try handler(["test-badge-one", "test-badge-two"])))
    }
    func testBlankFrameDoesNotSignIn() throws {
        XCTAssertNil(BadgeScanner.read(using: try handler([])))
    }
}
