import XCTest
@testable import IndustryFlow

final class TranscriptionSessionTests: XCTestCase {

    func testSessionInitialization() {
        let session = TranscriptionSession(profile: .legal)

        XCTAssertEqual(session.profile.id, "legal")
        XCTAssertEqual(session.rawTranscript, "")
        XCTAssertNil(session.polishedText)
        XCTAssertEqual(session.status, .recording)
        XCTAssertNotNil(session.id)
        XCTAssertNotNil(session.startedAt)
    }

    func testSessionStatusEquatable() {
        XCTAssertEqual(TranscriptionSession.Status.recording, .recording)
        XCTAssertEqual(TranscriptionSession.Status.processing, .processing)
        XCTAssertEqual(TranscriptionSession.Status.completed, .completed)
        XCTAssertNotEqual(TranscriptionSession.Status.recording, .completed)
    }

    func testSessionMutation() {
        var session = TranscriptionSession(profile: .general)
        session.rawTranscript = "Hello world"
        session.polishedText = "Hello, world."
        session.status = .completed

        XCTAssertEqual(session.rawTranscript, "Hello world")
        XCTAssertEqual(session.polishedText, "Hello, world.")
        XCTAssertEqual(session.status, .completed)
    }
}
