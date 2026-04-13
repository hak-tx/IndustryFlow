import XCTest
@testable import IndustryFlow

final class CustomGlossaryTests: XCTestCase {

    func testGlossaryVocabularyHints() {
        let glossary = CustomGlossary(
            name: "Test",
            terms: [
                GlossaryTerm(term: "FTUX", definition: "First Time User Experience"),
                GlossaryTerm(term: "XFN", definition: "Cross-Functional"),
            ],
            importedAt: Date(),
            sourceFileName: "test.csv"
        )

        XCTAssertEqual(glossary.vocabularyHints, ["FTUX", "XFN"])
    }

    func testGlossaryPromptFragment() {
        let glossary = CustomGlossary(
            name: "Test",
            terms: [
                GlossaryTerm(term: "FTUX", definition: "First Time User Experience"),
            ],
            importedAt: Date(),
            sourceFileName: "test.csv"
        )

        let fragment = glossary.glossaryPromptFragment
        XCTAssertTrue(fragment.contains("FTUX"))
        XCTAssertTrue(fragment.contains("First Time User Experience"))
        XCTAssertTrue(fragment.contains("Company-specific terminology"))
    }

    func testEmptyGlossaryPromptFragment() {
        let glossary = CustomGlossary.empty
        XCTAssertEqual(glossary.glossaryPromptFragment, "")
    }

    func testGlossaryCodable() throws {
        let glossary = CustomGlossary(
            name: "Acme Corp",
            terms: [
                GlossaryTerm(term: "TPS", definition: "TPS Report"),
                GlossaryTerm(term: "LGTM", definition: "Looks Good To Me"),
            ],
            importedAt: Date(),
            sourceFileName: "acme.csv"
        )

        let data = try JSONEncoder().encode(glossary)
        let decoded = try JSONDecoder().decode(CustomGlossary.self, from: data)

        XCTAssertEqual(decoded.name, "Acme Corp")
        XCTAssertEqual(decoded.terms.count, 2)
        XCTAssertEqual(decoded.terms[0].term, "TPS")
        XCTAssertEqual(decoded.terms[1].definition, "Looks Good To Me")
    }

    // MARK: - CSV Parser Tests

    func testParseSimpleCSV() throws {
        let csv = """
        FTUX,First Time User Experience
        XFN,Cross-Functional
        L10n,Localization
        """
        let url = try writeTempFile(content: csv, extension: "csv")
        let glossary = try GlossaryImporter.importFile(at: url)

        XCTAssertEqual(glossary.terms.count, 3)
        XCTAssertEqual(glossary.terms[0].term, "FTUX")
        XCTAssertEqual(glossary.terms[0].definition, "First Time User Experience")
        XCTAssertEqual(glossary.terms[2].term, "L10n")
    }

    func testParseCSVWithHeader() throws {
        let csv = """
        Term,Definition
        FTUX,First Time User Experience
        XFN,Cross-Functional
        """
        let url = try writeTempFile(content: csv, extension: "csv")
        let glossary = try GlossaryImporter.importFile(at: url)

        // Header should be skipped
        XCTAssertEqual(glossary.terms.count, 2)
        XCTAssertEqual(glossary.terms[0].term, "FTUX")
    }

    func testParseCSVWithQuotedFields() throws {
        let csv = """
        TPS,"TPS Report, a cover sheet document"
        LGTM,Looks Good To Me
        """
        let url = try writeTempFile(content: csv, extension: "csv")
        let glossary = try GlossaryImporter.importFile(at: url)

        XCTAssertEqual(glossary.terms[0].definition, "TPS Report, a cover sheet document")
    }

    func testParseTSV() throws {
        let tsv = "FTUX\tFirst Time User Experience\nXFN\tCross-Functional"
        let url = try writeTempFile(content: tsv, extension: "tsv")
        let glossary = try GlossaryImporter.importFile(at: url)

        XCTAssertEqual(glossary.terms.count, 2)
        XCTAssertEqual(glossary.terms[0].term, "FTUX")
    }

    func testParseTermsOnly() throws {
        let csv = """
        Kubernetes
        Docker
        Terraform
        """
        let url = try writeTempFile(content: csv, extension: "csv")
        let glossary = try GlossaryImporter.importFile(at: url)

        XCTAssertEqual(glossary.terms.count, 3)
        XCTAssertEqual(glossary.terms[0].term, "Kubernetes")
        XCTAssertEqual(glossary.terms[0].definition, "")
    }

    func testEmptyFileThrows() throws {
        let url = try writeTempFile(content: "", extension: "csv")
        XCTAssertThrowsError(try GlossaryImporter.importFile(at: url))
    }

    func testUnsupportedFormatThrows() throws {
        let url = try writeTempFile(content: "data", extension: "xlsx")
        XCTAssertThrowsError(try GlossaryImporter.importFile(at: url)) { error in
            let importError = error as? GlossaryImporter.ImportError
            if case .unsupportedFormat(let ext) = importError {
                XCTAssertEqual(ext, "xlsx")
            } else {
                XCTFail("Expected unsupportedFormat error")
            }
        }
    }

    func testHeaderAutoDetection() throws {
        let variants = [
            "Acronym,Meaning",
            "Term,Description",
            "Abbreviation,Explanation",
            "Word,Definition",
        ]

        for header in variants {
            let csv = "\(header)\nFTUX,First Time User Experience"
            let url = try writeTempFile(content: csv, extension: "csv")
            let glossary = try GlossaryImporter.importFile(at: url)
            XCTAssertEqual(glossary.terms.count, 1, "Failed for header: \(header)")
            XCTAssertEqual(glossary.terms[0].term, "FTUX")
        }
    }

    // MARK: - Helpers

    private func writeTempFile(content: String, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
