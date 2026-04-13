import Foundation
import os

/// A single term in a company's custom glossary.
/// Example: term = "FTUX", definition = "First Time User Experience"
struct GlossaryTerm: Codable, Hashable, Identifiable {
    var id: String { term }
    let term: String
    let definition: String
}

/// A user-uploaded glossary of company-specific terminology.
/// Stored as JSON in Application Support for persistence.
struct CustomGlossary: Codable {
    var name: String
    var terms: [GlossaryTerm]
    var importedAt: Date
    var sourceFileName: String

    /// All terms as plain strings for SFSpeechRecognizer contextualStrings.
    var vocabularyHints: [String] {
        terms.map(\.term)
    }

    /// Formatted glossary for inclusion in Claude's system prompt.
    /// Gives Claude the context to understand what each acronym/term means.
    var glossaryPromptFragment: String {
        guard !terms.isEmpty else { return "" }

        var lines = ["\n\nCompany-specific terminology glossary (use these terms correctly):"]
        for entry in terms {
            lines.append("- \(entry.term): \(entry.definition)")
        }
        return lines.joined(separator: "\n")
    }

    static let empty = CustomGlossary(
        name: "",
        terms: [],
        importedAt: Date(),
        sourceFileName: ""
    )
}

// MARK: - CSV / TSV Parser

enum GlossaryImporter {

    enum ImportError: LocalizedError {
        case fileUnreadable
        case emptyFile
        case noValidRows
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .fileUnreadable:
                return "Could not read the file. Ensure it is a valid CSV or TSV file."
            case .emptyFile:
                return "The file is empty."
            case .noValidRows:
                return "No valid terminology rows found. Each row needs at least a term in the first column."
            case .unsupportedFormat(let ext):
                return "Unsupported file format: .\(ext). Please use .csv or .tsv files. You can export to CSV from Excel or Google Sheets."
            }
        }
    }

    /// Imports a glossary from a CSV or TSV file.
    ///
    /// Expected format:
    /// - Column 1: Term / acronym (required)
    /// - Column 2: Definition / explanation (optional but recommended)
    /// - First row can be a header (auto-detected and skipped)
    ///
    /// Supports: .csv (comma-separated), .tsv (tab-separated), .txt (tab-separated)
    static func importFile(at url: URL) throws -> CustomGlossary {
        let ext = url.pathExtension.lowercased()

        guard ["csv", "tsv", "txt"].contains(ext) else {
            throw ImportError.unsupportedFormat(ext)
        }

        // Access security-scoped resource if needed (file from Open panel)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Try other encodings
            guard let content = try? String(contentsOf: url, encoding: .macOSRoman) else {
                throw ImportError.fileUnreadable
            }
            return try parseContent(content, separator: detectSeparator(ext: ext, content: content), fileName: url.lastPathComponent)
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }

        let separator = detectSeparator(ext: ext, content: content)
        return try parseContent(content, separator: separator, fileName: url.lastPathComponent)
    }

    private static func detectSeparator(ext: String, content: String) -> Character {
        if ext == "tsv" { return "\t" }

        // Auto-detect: check first line for tabs vs commas
        let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
        let tabCount = firstLine.filter { $0 == "\t" }.count
        let commaCount = firstLine.filter { $0 == "," }.count

        return tabCount > commaCount ? "\t" : ","
    }

    private static func parseContent(_ content: String, separator: Character, fileName: String) throws -> CustomGlossary {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw ImportError.emptyFile
        }

        var terms: [GlossaryTerm] = []
        var startIndex = 0

        // Auto-detect header row: if first row looks like a header, skip it
        if let firstLine = lines.first {
            let lower = firstLine.lowercased()
            let headerIndicators = ["term", "acronym", "abbreviation", "word", "name",
                                    "definition", "meaning", "description", "explanation"]
            if headerIndicators.contains(where: { lower.contains($0) }) {
                startIndex = 1
            }
        }

        for i in startIndex..<lines.count {
            let columns = parseCSVLine(lines[i], separator: separator)
            guard let term = columns.first, !term.isEmpty else { continue }

            let definition = columns.count > 1 ? columns[1] : ""
            terms.append(GlossaryTerm(
                term: term.trimmingCharacters(in: .whitespaces),
                definition: definition.trimmingCharacters(in: .whitespaces)
            ))
        }

        guard !terms.isEmpty else {
            throw ImportError.noValidRows
        }

        Logger.app.info("Imported \(terms.count) terms from \(fileName)")

        return CustomGlossary(
            name: fileName,
            terms: terms,
            importedAt: Date(),
            sourceFileName: fileName
        )
    }

    /// Parses a single CSV line, handling quoted fields (for commas/tabs within values).
    private static func parseCSVLine(_ line: String, separator: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == separator && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)

        return fields.map { $0.trimmingCharacters(in: .init(charactersIn: "\"")) }
    }
}

// MARK: - Persistent Storage

enum GlossaryStorage {
    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("IndustryFlow", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return dir.appendingPathComponent("custom_glossary.json")
    }

    static func save(_ glossary: CustomGlossary) throws {
        let data = try JSONEncoder().encode(glossary)
        try data.write(to: storageURL, options: .atomic)
        Logger.app.info("Saved glossary with \(glossary.terms.count) terms")
    }

    static func load() -> CustomGlossary? {
        guard let data = try? Data(contentsOf: storageURL) else {
            return nil
        }
        return try? JSONDecoder().decode(CustomGlossary.self, from: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: storageURL)
        Logger.app.info("Deleted custom glossary")
    }
}
