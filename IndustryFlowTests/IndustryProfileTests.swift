import XCTest
@testable import IndustryFlow

final class IndustryProfileTests: XCTestCase {

    func testAllProfilesExist() {
        XCTAssertGreaterThanOrEqual(IndustryProfile.allProfiles.count, 12)
    }

    func testProfileIDsAreUnique() {
        let ids = IndustryProfile.allProfiles.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Profile IDs must be unique")
    }

    func testAllProfilesHaveSystemPrompts() {
        for profile in IndustryProfile.allProfiles {
            XCTAssertFalse(profile.systemPrompt.isEmpty, "\(profile.name) has empty system prompt")
        }
    }

    func testAllProfilesHaveIcons() {
        for profile in IndustryProfile.allProfiles {
            XCTAssertFalse(profile.icon.isEmpty, "\(profile.name) has empty icon")
        }
    }

    func testGeneralProfileHasNoVocabularyHints() {
        XCTAssertTrue(IndustryProfile.general.vocabularyHints.isEmpty)
    }

    func testSpecializedProfilesHaveVocabularyHints() {
        let specialized = IndustryProfile.allProfiles.filter { $0.id != "general" }
        for profile in specialized {
            XCTAssertFalse(
                profile.vocabularyHints.isEmpty,
                "\(profile.name) should have vocabulary hints"
            )
        }
    }

    func testProfileCodable() throws {
        let profile = IndustryProfile.legal
        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(IndustryProfile.self, from: encoded)
        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, profile.name)
        XCTAssertEqual(decoded.vocabularyHints, profile.vocabularyHints)
    }

    func testProfileHashable() {
        var set = Set<IndustryProfile>()
        set.insert(.legal)
        set.insert(.legal)
        XCTAssertEqual(set.count, 1)

        set.insert(.accounting)
        XCTAssertEqual(set.count, 2)
    }

    func testExpectedProfiles() {
        let expectedIDs = [
            "general", "legal", "accounting", "engineering", "science",
            "business_management", "sales_marketing", "software_programming",
            "hardware", "manufacturing", "construction", "medical"
        ]
        let actualIDs = IndustryProfile.allProfiles.map(\.id)
        for id in expectedIDs {
            XCTAssertTrue(actualIDs.contains(id), "Missing expected profile: \(id)")
        }
    }
}
