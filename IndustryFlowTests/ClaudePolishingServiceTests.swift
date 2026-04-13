import XCTest
@testable import IndustryFlow

final class ClaudePolishingServiceTests: XCTestCase {

    func testPolishingEmptyTextThrows() async {
        let service = ClaudePolishingService()

        // Temporarily set a dummy key
        try? KeychainHelper.save(apiKey: "test-key")
        defer { KeychainHelper.delete() }

        do {
            _ = try await service.polish(text: "   ", profile: .general)
            XCTFail("Expected emptyText error")
        } catch let error as PolishingError {
            XCTAssertEqual(error.localizedDescription, PolishingError.emptyText.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPolishingWithoutAPIKeyThrows() async {
        let service = ClaudePolishingService()
        KeychainHelper.delete()

        do {
            _ = try await service.polish(text: "Hello world", profile: .general)
            XCTFail("Expected missingAPIKey error")
        } catch let error as PolishingError {
            XCTAssertEqual(error.localizedDescription, PolishingError.missingAPIKey.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPolishingErrorDescriptions() {
        // Verify all error cases have descriptions
        let errors: [PolishingError] = [
            .missingAPIKey, .invalidAPIKey, .emptyText,
            .invalidResponse, .emptyResponse, .rateLimited,
            .serverError, .apiError("test")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
