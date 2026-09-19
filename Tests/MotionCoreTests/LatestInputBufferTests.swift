import XCTest
@testable import MotionCore

final class LatestInputBufferTests: XCTestCase {
    func testBusyConsumerGetsNewestSampleOnlyOnce() {
        let buffer = LatestInputBuffer<Int>()
        let session = buffer.begin()
        for sample in 1...100 { buffer.submit(sample, session: session) }
        XCTAssertEqual(buffer.take(), 100)
        XCTAssertNil(buffer.take())
    }
    func testStoppedSessionCannotInjectSamplesIntoReconnect() {
        let buffer = LatestInputBuffer<Int>()
        let old = buffer.begin()
        buffer.submit(1, session: old)
        buffer.stop()
        buffer.submit(2, session: old)
        XCTAssertNil(buffer.take())
        let current = buffer.begin()
        buffer.submit(3, session: current)
        buffer.submit(999, session: old)
        XCTAssertEqual(buffer.take(), 3)
    }
}
