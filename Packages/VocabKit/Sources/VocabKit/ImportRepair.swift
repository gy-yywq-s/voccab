import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Inspects a failed word-list import, explains exactly what is wrong with
/// the file, and silently fixes the common problems it knows how to fix.
/// The original file is never touched — every repair happens on an
/// in-memory copy that exists only for the import.
///
/// The contract with the UI: the user is never asked to decide anything
/// mid-import. The pipeline either ends in rows (plus a list of the fixes
/// it applied, for the success message) or in a single specific reason why
/// the file cannot be imported.
public enum ImportRepair {

    public struct Outcome: Sendable {
        /// Parsed rows, ready for `CSVImport.importRows`.
        public var rows: [CSVImport.ImportedRow]
        /// Human-readable descriptions of every repair that was needed,
        /// in the order they were applied. Empty when the file was fine.
        public var fixes: [String]
    }

    public enum Failure: Error, Equatable {
        case cancelled
        /// The one specific reason the file cannot be imported.
        case unfixable(reason: String)

        public var reason: String {
            switch self {
            case .cancelled: return "Import cancelled."
            case .unfixable(let reason): return reason
            }
        }
    }

    /// Full pipeline for a picked file: container sniffing, text decoding,
    /// then the text-level repairs. `status` receives short progress lines
    /// ("Checking the file format…") for the loading UI; `isCancelled` is
    /// polled between stages so a stuck import can always be abandoned.
    public static func run(
        data: Data,
        status: @escaping @Sendable (String) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> Outcome {
        func checkpoint() throws {
            if isCancelled() { throw Failure.cancelled }
        }

        status("Checking the file format…")
        try checkpoint()
        var fixes: [String] = []
        var text: String

        switch sniffContainer(data) {
        case .zipArchive:
            throw Failure.unfixable(reason:
                "This is a compressed spreadsheet file (Excel .xlsx or Numbers), not a text table. Open it in the spreadsheet app and export it as CSV, then import that file.")
        case .legacyExcel:
            throw Failure.unfixable(reason:
                "This is a legacy Excel workbook (.xls), not a text table. Open it in Excel or Numbers and export it as CSV, then import that file.")
        case .pdf:
            throw Failure.unfixable(reason:
                "This is a PDF. Copy the word list out of it and paste it, or save it as a plain text or CSV file.")
        case .rtf:
            guard let converted = rtfToPlainText(data) else {
                throw Failure.unfixable(reason:
                    "This is a rich-text (RTF) file and its text could not be extracted. Save it as plain text and try again.")
            }
            fixes.append("Converted the rich-text (RTF) file to plain text")
            text = converted
        case .plainText:
            status("Decoding text…")
            let decoded = decodeVerbose(data)
            guard let decoded else {
                throw Failure.unfixable(reason:
                    "The file is not readable text in any supported encoding (UTF-8, UTF-16, GB18030 or Latin-1). It may be a binary file.")
            }
            if let note = decoded.fixNote { fixes.append(note) }
            text = decoded.text
        }

        try checkpoint()
        if looksLikeHTML(text) {
            status("Converting the web page to text…")
            text = htmlToPlainText(text)
            fixes.append("Extracted the table from HTML")
        }

        let outcome = try run(text: text, status: status, isCancelled: isCancelled)
        return Outcome(rows: outcome.rows, fixes: fixes + outcome.fixes)
    }

    /// Text-level pipeline (also the entry point for clipboard imports):
    /// try a straight parse first, then apply repairs one at a time,
    /// re-parsing after each, and keep only the repairs that were needed.
    public static func run(
        text: String,
        status: @escaping @Sendable (String) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> Outcome {
        func checkpoint() throws {
            if isCancelled() { throw Failure.cancelled }
        }

        status("Reading the rows…")
        try checkpoint()
        if let rows = try? CSVImport.parse(text), !rows.isEmpty {
            return Outcome(rows: rows, fixes: [])
        }

        status("Repairing common issues…")
        var fixes: [String] = []
        var current = text

        // Each repair returns nil when it had nothing to change, so a fix
        // is only reported when it actually altered the text.
        let repairs: [(String) -> (text: String, note: String)?] = [
            stripInvisibleCharacters,
            straightenSmartQuotes,
            normalizeFullWidthPunctuation,
            unwrapExcelFormulas,
            balanceQuotes,
        ]
        for repair in repairs {
            try checkpoint()
            guard let (repairedText, note) = repair(current) else { continue }
            current = repairedText
            fixes.append(note)
            if let rows = try? CSVImport.parse(current), !rows.isEmpty {
                return Outcome(rows: rows, fixes: fixes)
            }
        }

        // Last resort: a paste that lost its line breaks — one giant row.
        try checkpoint()
        if let (rows, note) = rebuildLostLineBreaks(current) {
            fixes.append(note)
            return Outcome(rows: rows, fixes: fixes)
        }

        throw Failure.unfixable(reason:
            "No word rows were found even after repairs. \(CSVImport.diagnose(current)) Expected one word per line, or a table with a “word” column.")
    }

    // MARK: - Container sniffing

    private enum Container {
        case zipArchive, legacyExcel, pdf, rtf, plainText
    }

    private static func sniffContainer(_ data: Data) -> Container {
        guard data.count >= 4 else { return .plainText }
        let head = [UInt8](data.prefix(8))
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .zipArchive }      // "PK.."
        if head.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) { return .legacyExcel }    // OLE2
        if head.starts(with: Array("%PDF".utf8)) { return .pdf }
        if head.starts(with: Array("{\\rtf".utf8)) { return .rtf }
        return .plainText
    }

    private static func rtfToPlainText(_ data: Data) -> String? {
        #if canImport(UIKit) || canImport(AppKit)
        let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil)
        return attributed?.string
        #else
        return nil
        #endif
    }

    // MARK: - Decoding

    /// Same fallback chain as `CSVImport.decode`, but reports when the file
    /// needed a non-UTF-8 encoding so the success message can mention it.
    private static func decodeVerbose(_ data: Data) -> (text: String, fixNote: String?)? {
        if let text = String(data: data, encoding: .utf8) { return (text, nil) }
        if let text = String(data: data, encoding: .unicode) {
            return (text, "Decoded the file as UTF-16")
        }
        let gbEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gbEncoding) {
            return (text, "Decoded the file as GB18030 (Chinese Excel encoding)")
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return (text, "Decoded the file as Latin-1")
        }
        return nil
    }

    // MARK: - HTML

    private static func looksLikeHTML(_ text: String) -> Bool {
        let head = text.prefix(512).lowercased()
        return head.contains("<!doctype html") || head.contains("<html")
            || (text.lowercased().contains("</td>") && text.lowercased().contains("</tr>"))
    }

    /// Table-aware tag stripping: row ends become newlines, cell ends
    /// become tabs, everything else is dropped, entities are decoded.
    /// Deliberately not NSAttributedString's HTML importer — that one is
    /// main-thread-only and can hang on malformed markup.
    private static func htmlToPlainText(_ html: String) -> String {
        var text = html
        for (pattern, replacement) in [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(tr|p|div|li|h[1-6])>", "\n"),
            ("(?i)</(td|th)>", "\t"),
            ("(?i)<(script|style)[^>]*>.*?</\\1>", ""),
            ("<[^>]+>", ""),
        ] {
            text = text.replacingOccurrences(
                of: pattern, with: replacement,
                options: [.regularExpression])
        }
        for (entity, char) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text
    }

    // MARK: - Text repairs

    private static func stripInvisibleCharacters(_ text: String) -> (text: String, note: String)? {
        var changed = false
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\u{FEFF}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}":
                changed = true
            case "\u{00A0}", "\u{202F}", "\u{2007}":
                changed = true
                result.unicodeScalars.append(" ")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return changed ? (result, "Removed invisible characters (zero-width and non-breaking spaces)") : nil
    }

    private static func straightenSmartQuotes(_ text: String) -> (text: String, note: String)? {
        var result = text
        var changed = false
        for (curly, straight) in [
            ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{201E}", "\""), ("\u{201F}", "\""),
        ] {
            if result.contains(curly) {
                changed = true
                result = result.replacingOccurrences(of: curly, with: straight)
            }
        }
        return changed ? (result, "Straightened curly quotation marks") : nil
    }

    private static func normalizeFullWidthPunctuation(_ text: String) -> (text: String, note: String)? {
        var result = text
        var changed = false
        for (fullWidth, halfWidth) in [
            ("\u{FF0C}", ","), ("\u{FF1B}", ";"), ("\u{3000}", " "), ("\u{FF09}", ")"), ("\u{FF08}", "("),
        ] {
            if result.contains(fullWidth) {
                changed = true
                result = result.replacingOccurrences(of: fullWidth, with: halfWidth)
            }
        }
        return changed ? (result, "Converted full-width punctuation to standard punctuation") : nil
    }

    /// Excel sometimes exports text cells as `="value"` to preserve leading
    /// zeros; unwrap those back to the value.
    private static func unwrapExcelFormulas(_ text: String) -> (text: String, note: String)? {
        guard text.contains("=\"") else { return nil }
        let result = text.replacingOccurrences(
            of: "=\"([^\"]*)\"", with: "$1", options: .regularExpression)
        return result == text ? nil : (result, "Unwrapped Excel formula-quoted cells")
    }

    /// A single stray quote makes the CSV parser swallow everything after
    /// it as one quoted field. Lines with an odd number of quotes get their
    /// quotes removed so parsing can recover the rows.
    private static func balanceQuotes(_ text: String) -> (text: String, note: String)? {
        var fixedLines = 0
        let repaired = text
            .components(separatedBy: .newlines)
            .map { line -> String in
                let count = line.reduce(into: 0) { if $1 == "\"" { $0 += 1 } }
                guard count % 2 == 1 else { return line }
                fixedLines += 1
                return line.replacingOccurrences(of: "\"", with: "")
            }
            .joined(separator: "\n")
        guard fixedLines > 0 else { return nil }
        let plural = fixedLines == 1 ? "1 line" : "\(fixedLines) lines"
        return (repaired, "Fixed unbalanced quotation marks on \(plural)")
    }

    /// A paste that lost its line breaks arrives as one giant delimiter-
    /// separated row. Rebuild word/note pairs from the flat field list when
    /// the even-position fields overwhelmingly look like words.
    private static func rebuildLostLineBreaks(_ text: String) -> (rows: [CSVImport.ImportedRow], note: String)? {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        let delimiter: Character = flat.contains("\t") ? "\t" : ","
        var fields = flat.split(separator: delimiter, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard fields.count >= 4 else { return nil }

        // Drop a leaked header pair.
        if fields.count >= 2,
           ["word", "words", "term", "单词"].contains(fields[0].lowercased()),
           ["note", "notes", "meaning", "definition", "释义", "笔记"].contains(fields[1].lowercased()) {
            fields.removeFirst(2)
        }
        guard fields.count >= 4, fields.count % 2 == 0 else { return nil }

        let candidateWords = stride(from: 0, to: fields.count, by: 2).map { fields[$0] }
        let wordLike = candidateWords.filter { looksLikeWord($0) }.count
        guard Double(wordLike) >= Double(candidateWords.count) * 0.6 else { return nil }

        var rows: [CSVImport.ImportedRow] = []
        var seen: Set<String> = []
        for index in stride(from: 0, to: fields.count - 1, by: 2) {
            let word = fields[index]
            guard looksLikeWord(word), seen.insert(word.lowercased()).inserted else { continue }
            rows.append(CSVImport.ImportedRow(word: word, note: fields[index + 1]))
        }
        guard rows.count >= 2 else { return nil }
        return (rows, "Rebuilt \(rows.count) rows from a paste that had lost its line breaks")
    }

    private static func looksLikeWord(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 40,
              text.rangeOfCharacter(from: .letters) != nil,
              text.filter({ $0 == " " }).count <= 4 else { return false }
        // A word shouldn't end in sentence punctuation the way a note does.
        return !text.hasSuffix(".") && !text.hasSuffix("。")
    }
}
