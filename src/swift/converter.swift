import Foundation
import AppKit
import PDFKit
import CoreText

// MARK: - Errors

struct ConversionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Process helpers

enum Tools {
    static let searchDirs = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        "/Applications/calibre.app/Contents/MacOS"
    ]

    static func find(_ name: String) -> String? {
        for dir in searchDirs {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Runs an executable. Returns stdout data on success, throws with stderr on failure.
    @discardableResult
    static func run(_ exe: String, _ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        let outPipe = Pipe()
        let errFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("bou-stderr-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errFile.path, contents: nil)
        let errHandle = try FileHandle(forWritingTo: errFile)
        process.standardOutput = outPipe
        process.standardError = errHandle
        defer {
            try? errHandle.close()
            try? FileManager.default.removeItem(at: errFile)
        }
        try process.run()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let err = (try? String(contentsOf: errFile, encoding: .utf8)) ?? ""
            throw ConversionError("\((exe as NSString).lastPathComponent) failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return data
    }

    /// Describes which optional high-fidelity tools are installed.
    static func status() -> [String: Bool] {
        return [
            "calibre": find("ebook-convert") != nil,
            "djvulibre": true, // Built-in pure Swift engine
            "pdf2djvu": true   // Built-in pure Swift engine
        ]
    }
}

// MARK: - Intermediate representation

struct Document {
    var title: String
    var bodyHTML: String   // inner HTML of <body>
}

enum HTMLUtil {
    static func escape(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func wrap(_ doc: Document) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="UTF-8"><title>\(escape(doc.title))</title>
        <style>body{font-family:-apple-system,Helvetica,Arial,sans-serif;line-height:1.5;max-width:46em;margin:2em auto;padding:0 1em}</style>
        </head><body>\(doc.bodyHTML)</body></html>
        """
    }

    static func bodyContent(of html: String) -> String {
        if let start = html.range(of: "<body", options: .caseInsensitive),
           let tagEnd = html.range(of: ">", range: start.upperBound..<html.endIndex),
           let end = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            return String(html[tagEnd.upperBound..<end.lowerBound])
        }
        return html
    }

    static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).map { m in
            (0..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    static func decodeEntities(_ s: String) -> String {
        return s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - Markdown <-> HTML (lightweight)

enum Markdown {
    static func inline(_ text: String) -> String {
        var s = HTMLUtil.escape(text)
        s = HTMLUtil.replace("`([^`]+)`", in: s, with: "<code>$1</code>")
        s = HTMLUtil.replace("\\*\\*([^*]+)\\*\\*", in: s, with: "<strong>$1</strong>")
        s = HTMLUtil.replace("(?<![*\\w])\\*([^*\\n]+)\\*(?![*\\w])", in: s, with: "<em>$1</em>")
        s = HTMLUtil.replace("\\[([^\\]]+)\\]\\(([^)]+)\\)", in: s, with: "<a href=\"$2\">$1</a>")
        return s
    }

    static func toHTML(_ md: String) -> String {
        var out = ""
        var paragraph: [String] = []
        var listOpen: String? = nil
        var inCode = false
        var codeLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                out += "<p>\(inline(paragraph.joined(separator: " ")))</p>\n"
                paragraph.removeAll()
            }
        }
        func closeList() {
            if let l = listOpen { out += "</\(l)>\n"; listOpen = nil }
        }

        for rawLine in md.components(separatedBy: .newlines) {
            let line = rawLine
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    out += "<pre><code>\(HTMLUtil.escape(codeLines.joined(separator: "\n")))</code></pre>\n"
                    codeLines.removeAll(); inCode = false
                } else {
                    flushParagraph(); closeList(); inCode = true
                }
                continue
            }
            if inCode { codeLines.append(line); continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flushParagraph(); closeList(); continue }

            if let m = HTMLUtil.firstMatch("^(#{1,6})\\s+(.*)$", in: trimmed) , trimmed.hasPrefix("#") {
                _ = m
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                flushParagraph(); closeList()
                out += "<h\(level)>\(inline(text))</h\(level)>\n"
                continue
            }
            if let item = HTMLUtil.firstMatch("^[-*+]\\s+(.*)$", in: trimmed) {
                flushParagraph()
                if listOpen != "ul" { closeList(); out += "<ul>\n"; listOpen = "ul" }
                out += "<li>\(inline(item))</li>\n"
                continue
            }
            if let item = HTMLUtil.firstMatch("^\\d+[.)]\\s+(.*)$", in: trimmed) {
                flushParagraph()
                if listOpen != "ol" { closeList(); out += "<ol>\n"; listOpen = "ol" }
                out += "<li>\(inline(item))</li>\n"
                continue
            }
            if HTMLUtil.firstMatch("^(---+|\\*\\*\\*+)$", in: trimmed) != nil {
                flushParagraph(); closeList(); out += "<hr>\n"; continue
            }
            closeList()
            paragraph.append(trimmed)
        }
        if inCode {
            out += "<pre><code>\(HTMLUtil.escape(codeLines.joined(separator: "\n")))</code></pre>\n"
        }
        flushParagraph(); closeList()
        return out
    }

    static func fromHTML(_ html: String) -> String {
        var s = HTMLUtil.bodyContent(of: html)
        s = HTMLUtil.replace("<(script|style)[^>]*>.*?</\\1>", in: s, with: "")
        for level in 1...6 {
            s = HTMLUtil.replace("<h\(level)[^>]*>(.*?)</h\(level)>", in: s,
                                 with: "\n\n\(String(repeating: "#", count: level)) $1\n\n")
        }
        s = HTMLUtil.replace("<(strong|b)(\\s[^>]*)?>(.*?)</\\1>", in: s, with: "**$3**")
        s = HTMLUtil.replace("<(em|i)(\\s[^>]*)?>(.*?)</\\1>", in: s, with: "*$3*")
        s = HTMLUtil.replace("<a[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>", in: s, with: "[$2]($1)")
        s = HTMLUtil.replace("<li[^>]*>", in: s, with: "\n- ")
        s = HTMLUtil.replace("<br\\s*/?>", in: s, with: "  \n")
        s = HTMLUtil.replace("</(p|div|ul|ol|pre|tr|blockquote)>", in: s, with: "\n\n")
        s = HTMLUtil.replace("<[^>]+>", in: s, with: "")
        s = HTMLUtil.decodeEntities(s)
        s = HTMLUtil.replace("[ \\t]+\\n", in: s, with: "\n")
        s = HTMLUtil.replace("\\n{3,}", in: s, with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}

// MARK: - Engine

final class ConversionEngine {
    private let fm = FileManager.default

    private func makeTempDir() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("bou-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func formatID(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "pdf": return "pdf"
        case "epub": return "epub"
        case "djvu", "djv": return "djvu"
        case "docx": return "docx"
        case "html", "htm": return "html"
        case "txt", "text": return "txt"
        case "rtf": return "rtf"
        case "md", "markdown": return "md"
        default: return nil
        }
    }

    // Convert a single file. Throws ConversionError on failure.
    func convert(source: URL, target: URL, targetFormat: String) throws {
        guard let sourceFormat = ConversionEngine.formatID(forExtension: source.pathExtension) else {
            throw ConversionError("Unsupported source format: \(source.pathExtension)")
        }
        if sourceFormat == targetFormat {
            throw ConversionError("Source and target formats are identical")
        }
        guard fm.fileExists(atPath: source.path) else {
            throw ConversionError("Source file not found")
        }

        // Prefer Calibre for fidelity when installed and both sides are supported by it.
        let calibreFormats: Set<String> = ["pdf", "epub", "docx", "html", "txt", "rtf"]
        if let calibre = Tools.find("ebook-convert"),
           calibreFormats.contains(sourceFormat), calibreFormats.contains(targetFormat) {
            if (try? Tools.run(calibre, [source.path, target.path])) != nil,
               fm.fileExists(atPath: target.path) {
                return
            }
            // Fall through to built-in engine if Calibre fails.
        }

        let temp = try makeTempDir()
        defer { try? fm.removeItem(at: temp) }

        // Write to a temp file first so a failed conversion never leaves a partial output.
        let partial = temp.appendingPathComponent("out.\(target.pathExtension)")
        if targetFormat == "djvu" {
            try writeDjVu(from: source, sourceFormat: sourceFormat, to: partial, temp: temp)
        } else {
            let doc = try read(source: source, format: sourceFormat, temp: temp)
            try write(doc, format: targetFormat, to: partial, temp: temp)
        }

        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: partial, to: target)
    }

    // MARK: Readers

    private func read(source: URL, format: String, temp: URL) throws -> Document {
        let baseTitle = source.deletingPathExtension().lastPathComponent
        switch format {
        case "txt":
            let text = try readText(source)
            let paras = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { "<p>\(HTMLUtil.escape($0).replacingOccurrences(of: "\n", with: "<br>\n"))</p>" }
            return Document(title: baseTitle, bodyHTML: paras.joined(separator: "\n"))
        case "md":
            let text = try readText(source)
            return Document(title: baseTitle, bodyHTML: Markdown.toHTML(text))
        case "html":
            let html = try readText(source)
            let title = HTMLUtil.firstMatch("<title[^>]*>(.*?)</title>", in: html).map { HTMLUtil.decodeEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? baseTitle
            return Document(title: title.isEmpty ? baseTitle : title, bodyHTML: HTMLUtil.bodyContent(of: html))
        case "rtf", "docx":
            let out = temp.appendingPathComponent("in.html")
            try textutil(["-convert", "html", "-encoding", "UTF-8", "-output", out.path, source.path])
            let html = try readText(out)
            return Document(title: baseTitle, bodyHTML: HTMLUtil.bodyContent(of: html))
        case "pdf":
            return try readPDF(source, title: baseTitle)
        case "epub":
            return try readEPUB(source, fallbackTitle: baseTitle)
        case "djvu":
            return try DjVuReader.readDocument(from: source, fallbackTitle: baseTitle)
        default:
            throw ConversionError("Unsupported source format: \(format)")
        }
    }

    private func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw ConversionError("Could not decode text file")
    }

    private func readPDF(_ url: URL, title: String) throws -> Document {
        guard let pdf = PDFDocument(url: url) else {
            throw ConversionError("Could not open PDF (corrupt or password protected)")
        }
        if pdf.isLocked { throw ConversionError("PDF is password protected") }
        var html = ""
        var totalChars = 0
        for i in 0..<pdf.pageCount {
            guard let text = pdf.page(at: i)?.string else { continue }
            let paras = text.components(separatedBy: "\n\n")
            for p in paras {
                let joined = p.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !joined.isEmpty {
                    totalChars += joined.count
                    html += "<p>\(HTMLUtil.escape(joined))</p>\n"
                }
            }
        }
        if totalChars == 0 {
            throw ConversionError("PDF contains no extractable text (it may be a scanned image)")
        }
        let docTitle = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? title
        return Document(title: docTitle, bodyHTML: html)
    }

    private func readEPUB(_ url: URL, fallbackTitle: String) throws -> Document {
        guard let unzip = Tools.find("unzip") else { throw ConversionError("unzip not available") }
        func entry(_ path: String) throws -> String {
            let data = try Tools.run(unzip, ["-p", url.path, path])
            return String(decoding: data, as: UTF8.self)
        }
        let container = try entry("META-INF/container.xml")
        guard let opfPath = HTMLUtil.firstMatch("full-path=\"([^\"]+)\"", in: container) else {
            throw ConversionError("Invalid EPUB: missing package document")
        }
        let opf = try entry(opfPath)
        let opfDir = (opfPath as NSString).deletingLastPathComponent

        var manifest: [String: String] = [:]
        for m in HTMLUtil.allMatches("<item\\s[^>]*>", in: opf) {
            let tag = m[0]
            if let id = HTMLUtil.firstMatch("\\bid=\"([^\"]+)\"", in: tag),
               let href = HTMLUtil.firstMatch("\\bhref=\"([^\"]+)\"", in: tag) {
                manifest[id] = href
            }
        }
        let spineIDs = HTMLUtil.allMatches("<itemref\\s[^>]*idref=\"([^\"]+)\"", in: opf).map { $0[1] }
        if spineIDs.isEmpty { throw ConversionError("Invalid EPUB: empty reading order") }

        var body = ""
        for id in spineIDs {
            guard let href = manifest[id] else { continue }
            let decoded = href.removingPercentEncoding ?? href
            let path = opfDir.isEmpty ? decoded : (opfDir as NSString).appendingPathComponent(decoded)
            guard let html = try? entry(path) else { continue }
            body += HTMLUtil.bodyContent(of: html) + "\n"
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConversionError("EPUB contains no readable content")
        }
        let title = HTMLUtil.firstMatch("<dc:title[^>]*>(.*?)</dc:title>", in: opf)
            .map { HTMLUtil.decodeEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? fallbackTitle
        return Document(title: title.isEmpty ? fallbackTitle : title, bodyHTML: body)
    }

    // MARK: Writers

    private func write(_ doc: Document, format: String, to out: URL, temp: URL) throws {
        switch format {
        case "html":
            try HTMLUtil.wrap(doc).write(to: out, atomically: true, encoding: .utf8)
        case "md":
            let md = "# \(doc.title)\n\n" + Markdown.fromHTML(doc.bodyHTML)
            // Avoid duplicating the title when body already starts with a heading.
            let body = Markdown.fromHTML(doc.bodyHTML)
            let result = body.hasPrefix("#") ? body : md
            try result.write(to: out, atomically: true, encoding: .utf8)
        case "txt":
            let htmlFile = temp.appendingPathComponent("w.html")
            try HTMLUtil.wrap(doc).write(to: htmlFile, atomically: true, encoding: .utf8)
            try textutil(["-convert", "txt", "-encoding", "UTF-8", "-output", out.path, htmlFile.path])
        case "rtf", "docx":
            let htmlFile = temp.appendingPathComponent("w.html")
            try HTMLUtil.wrap(doc).write(to: htmlFile, atomically: true, encoding: .utf8)
            try textutil(["-convert", format, "-encoding", "UTF-8", "-output", out.path, htmlFile.path])
        case "pdf":
            try writePDF(doc, to: out, temp: temp)
        case "epub":
            try writeEPUB(doc, to: out, temp: temp)
        default:
            throw ConversionError("Unsupported target format: \(format)")
        }
    }

    private func textutil(_ args: [String]) throws {
        guard let tool = Tools.find("textutil") else { throw ConversionError("textutil not available") }
        try Tools.run(tool, args)
    }

    private func writePDF(_ doc: Document, to out: URL, temp: URL) throws {
        let htmlFile = temp.appendingPathComponent("p.html")
        let rtfFile = temp.appendingPathComponent("p.rtf")
        try HTMLUtil.wrap(doc).write(to: htmlFile, atomically: true, encoding: .utf8)
        try textutil(["-convert", "rtf", "-encoding", "UTF-8", "-output", rtfFile.path, htmlFile.path])
        let rtfData = try Data(contentsOf: rtfFile)
        guard let attr = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
            throw ConversionError("Failed to lay out document for PDF output")
        }

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        var mediaBox = pageRect
        guard let ctx = CGContext(out as CFURL, mediaBox: &mediaBox, nil) else {
            throw ConversionError("Could not create PDF output")
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let textRect = pageRect.insetBy(dx: 54, dy: 54)
        var index = 0
        let length = attr.length
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: index, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length == 0 { break }
            index += visible.length
        } while index < length
        ctx.closePDF()
    }

    private func xhtmlBody(_ html: String) throws -> String {
        let wrapped = "<html><body>\(html)</body></html>"
        guard let data = wrapped.data(using: .utf8) else { throw ConversionError("Encoding error") }
        let xml = try XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
        guard let bodyNode = try xml.nodes(forXPath: "//body").first else {
            throw ConversionError("Could not normalise HTML for EPUB")
        }
        return (bodyNode.children ?? []).map { $0.xmlString }.joined(separator: "\n")
    }

    private func writeEPUB(_ doc: Document, to out: URL, temp: URL) throws {
        guard let zip = Tools.find("zip") else { throw ConversionError("zip not available") }
        let root = temp.appendingPathComponent("epub")
        try fm.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("OEBPS"), withIntermediateDirectories: true)

        try "application/epub+zip".write(to: root.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: root.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)

        let title = HTMLUtil.escape(doc.title)
        let body = try xhtmlBody(doc.bodyHTML)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
        <head><meta charset="UTF-8"/><title>\(title)</title></head>
        <body>
        \(body)
        </body></html>
        """.write(to: root.appendingPathComponent("OEBPS/content.xhtml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
        <head><meta charset="UTF-8"/><title>\(title)</title></head>
        <body><nav epub:type="toc"><ol><li><a href="content.xhtml">\(title)</a></li></ol></nav></body></html>
        """.write(to: root.appendingPathComponent("OEBPS/nav.xhtml"), atomically: true, encoding: .utf8)

        let modified = ISO8601DateFormatter().string(from: Date()).prefix(19) + "Z"
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">urn:uuid:\(UUID().uuidString)</dc:identifier>
            <dc:title>\(title)</dc:title>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="content"/></spine>
        </package>
        """.write(to: root.appendingPathComponent("OEBPS/content.opf"), atomically: true, encoding: .utf8)

        // The mimetype entry must be first and stored uncompressed.
        let archive = temp.appendingPathComponent("book.epub")
        try runIn(root, zip, ["-X0", archive.path, "mimetype"])
        try runIn(root, zip, ["-Xr9D", archive.path, "META-INF", "OEBPS"])
        try fm.moveItem(at: archive, to: out)
    }

    private func runIn(_ dir: URL, _ exe: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ConversionError("\((exe as NSString).lastPathComponent) failed")
        }
    }

    private func writeDjVu(from source: URL, sourceFormat: String, to out: URL, temp: URL) throws {
        let pdfURL: URL
        if sourceFormat == "pdf" {
            pdfURL = source
        } else {
            pdfURL = temp.appendingPathComponent("intermediate.pdf")
            let doc = try read(source: source, format: sourceFormat, temp: temp)
            try writePDF(doc, to: pdfURL, temp: temp)
        }
        try DjVuWriter.writeDjVu(fromPDF: pdfURL, to: out)
    }
}
