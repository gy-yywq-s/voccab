import AppKit
import Foundation
import UniformTypeIdentifiers
import VocabKit

/// Turning the draft into text: files for the user, and a parse-able table for
/// VocabKit's importer.
enum DraftExport {

    // MARK: - CSV (for the user)

    /// RFC 4180: `word,note` header, quotes doubled, any field containing a
    /// comma, quote or newline wrapped.
    static func csv(rows: [DraftRow]) -> String {
        var lines = ["word,note"]
        for row in rows where row.isSubstantive {
            lines.append("\(csvField(row.trimmedWord)),\(csvField(row.note))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
        let needsQuotes = normalized.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        guard needsQuotes else { return normalized }
        return "\"" + normalized.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Markdown (for the user)

    /// A `| Word | Notes |` table. Pipes are escaped and newlines become
    /// `<br>`, because a Markdown table cell cannot contain a line break.
    static func markdown(rows: [DraftRow]) -> String {
        var lines = ["| Word | Notes |", "| --- | --- |"]
        for row in rows where row.isSubstantive {
            lines.append("| \(markdownCell(row.trimmedWord)) | \(markdownCell(row.trimmedNote)) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func markdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    // MARK: - Save panel

    enum Format {
        case csv
        case markdown

        var suggestedName: String {
            switch self {
            case .csv: return "Voccab Draft.csv"
            case .markdown: return "Voccab Draft.md"
            }
        }

        var contentType: UTType {
            switch self {
            case .csv: return .commaSeparatedText
            // There is no `UTType.markdown` constant; resolve by extension and
            // fall back to plain text on systems that do not know the type.
            case .markdown: return UTType(filenameExtension: "md") ?? .plainText
            }
        }
    }

    /// Runs a save panel and writes the text. Returns the written URL, or nil
    /// when the user cancelled or the write failed.
    @MainActor
    @discardableResult
    static func present(format: Format, rows: [DraftRow]) -> URL? {
        let title: String
        let text: String
        switch format {
        case .csv:
            title = "Export Draft as CSV"
            text = csv(rows: rows)
        case .markdown:
            title = "Export Draft as Markdown"
            text = markdown(rows: rows)
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = format.suggestedName
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = title

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}

/// Hands the draft to VocabKit's importer.
///
/// `CSVImport.ImportedRow` has public properties but no public initialiser, so
/// its memberwise init is internal and the rows cannot be built directly from
/// this module. The supported route is `CSVImport.parse(_:)`, so the draft is
/// serialised into a table that parser is guaranteed to read back exactly.
///
/// Tab is chosen as the delimiter deliberately: `CSVImport`'s delimiter sniffer
/// returns tab unconditionally when the text contains one, whereas comma vs.
/// semicolon is decided by counting characters — a note full of semicolons
/// would flip the parse. Tabs inside fields are replaced by spaces so the
/// delimiter stays unambiguous, and every field is quoted so embedded quotes,
/// commas and newlines survive.
enum DraftTransfer {

    static func importTable(rows: [DraftRow]) -> String {
        var lines = ["\"word\"\t\"note\""]
        for row in rows where row.isSubstantive {
            lines.append("\(field(row.trimmedWord))\t\(field(row.trimmedNote))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func field(_ value: String) -> String {
        let flattened = value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(flattened)\""
    }

    /// Parses the draft back out as importer rows. Words the importer refuses
    /// (blank, no letters) and case-insensitive duplicates are dropped by
    /// `CSVImport.parse` itself, which is the behaviour we want.
    static func importedRows(from rows: [DraftRow]) -> [CSVImport.ImportedRow] {
        guard rows.contains(where: \.isSubstantive) else { return [] }
        return (try? CSVImport.parse(importTable(rows: rows))) ?? []
    }
}
