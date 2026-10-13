import Foundation
import CoreGraphics
import Vision
import PDFKit

// MARK: - Models

struct DjVuPageText {
    let pageNumber: Int
    let text: String
}

struct DjVuPageSpec {
    let width: Int
    let height: Int
    let dpi: Int
    let text: String
    let bits: [UInt8]
}

// MARK: - DjVu Reader (Pure Swift + macOS Vision OCR Fallback)

enum DjVuReader {
    static func readDocument(from url: URL, fallbackTitle: String) throws -> Document {
        let data = try Data(contentsOf: url)
        let pages = try readPages(data: data)
        if pages.isEmpty {
            throw ConversionError("DjVu file has no pages or text layer (image OCR did not detect readable text)")
        }
        
        var bodyHTML = ""
        var totalChars = 0
        for p in pages {
            let paras = p.text.components(separatedBy: "\n\n")
            for para in paras {
                let joined = para.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !joined.isEmpty {
                    totalChars += joined.count
                    bodyHTML += "<p>\(HTMLUtil.escape(joined))</p>\n"
                }
            }
        }
        
        if totalChars == 0 {
            throw ConversionError("DjVu file contains no extractable text")
        }
        
        return Document(title: fallbackTitle, bodyHTML: bodyHTML)
    }

    private static func readPages(data: Data) throws -> [DjVuPageText] {
        let bytes = [UInt8](data)
        guard bytes.count >= 16 else {
            throw ConversionError("File too small to be a DjVu document")
        }
        guard bytes[0] == 0x41 && bytes[1] == 0x54 && bytes[2] == 0x26 && bytes[3] == 0x54 else {
            throw ConversionError("Invalid DjVu format: missing AT&T header")
        }
        guard String(bytes: bytes[4..<8], encoding: .ascii) == "FORM" else {
            throw ConversionError("Invalid DjVu format: missing initial FORM chunk")
        }
        
        let formType = String(bytes: bytes[12..<16], encoding: .ascii) ?? ""
        var pages: [DjVuPageText] = []
        
        if formType == "DJVU" {
            // Single-page DjVu
            if let p = try parsePage(bytes: bytes, start: 16, end: bytes.count, pageNum: 1, sharedDict: nil) {
                pages.append(p)
            }
        } else if formType == "DJVM" {
            // Multi-page bundled DJVM
            var pos = 16
            var pageIndex = 1
            var sharedDict: JB2Dict? = nil
            
            while pos + 8 <= bytes.count {
                let chunkID = String(bytes: bytes[pos..<(pos + 4)], encoding: .ascii) ?? ""
                let sz = (Int(bytes[pos + 4]) << 24) | (Int(bytes[pos + 5]) << 16) | (Int(bytes[pos + 6]) << 8) | Int(bytes[pos + 7])
                let chunkStart = pos + 8
                let chunkEnd = min(bytes.count, chunkStart + sz)
                
                if chunkID == "FORM" && chunkStart + 4 <= chunkEnd {
                    let subType = String(bytes: bytes[chunkStart..<(chunkStart + 4)], encoding: .ascii) ?? ""
                    if subType == "DJVU" {
                        if let p = try parsePage(bytes: bytes, start: chunkStart + 4, end: chunkEnd, pageNum: pageIndex, sharedDict: sharedDict) {
                            pages.append(p)
                            pageIndex += 1
                        }
                    } else if subType == "DJVI" {
                        sharedDict = try parseSharedDict(bytes: bytes, start: chunkStart + 4, end: chunkEnd)
                    }
                }
                
                pos = chunkEnd
                if sz % 2 == 1 { pos += 1 }
            }
        } else {
            throw ConversionError("Unsupported DjVu container type: \(formType)")
        }
        
        return pages
    }

    private static func parseSharedDict(bytes: [UInt8], start: Int, end: Int) throws -> JB2Dict? {
        var pos = start
        while pos + 8 <= end {
            let chunkID = String(bytes: bytes[pos..<(pos + 4)], encoding: .ascii) ?? ""
            let sz = (Int(bytes[pos + 4]) << 24) | (Int(bytes[pos + 5]) << 16) | (Int(bytes[pos + 6]) << 8) | Int(bytes[pos + 7])
            let chunkDataStart = pos + 8
            let chunkDataEnd = min(end, chunkDataStart + sz)
            
            if chunkID == "Djbz" {
                let dictData = Array(bytes[chunkDataStart..<chunkDataEnd])
                let dict = JB2Dict(data: dictData)
                try dict.decode(shared: nil)
                return dict
            }
            pos = chunkDataEnd
            if sz % 2 == 1 { pos += 1 }
        }
        return nil
    }

    private static func parsePage(bytes: [UInt8], start: Int, end: Int, pageNum: Int, sharedDict: JB2Dict?) throws -> DjVuPageText? {
        var pos = start
        var text: String? = nil
        var sjbzData: [UInt8]? = nil
        
        while pos + 8 <= end {
            let chunkID = String(bytes: bytes[pos..<(pos + 4)], encoding: .ascii) ?? ""
            let sz = (Int(bytes[pos + 4]) << 24) | (Int(bytes[pos + 5]) << 16) | (Int(bytes[pos + 6]) << 8) | Int(bytes[pos + 7])
            let chunkDataStart = pos + 8
            let chunkDataEnd = min(end, chunkDataStart + sz)
            
            if chunkID == "TXTz" {
                let compressed = Array(bytes[chunkDataStart..<chunkDataEnd])
                if let decompressed = try? BZZ.decode(compressed), decompressed.count >= 3 {
                    let tLen = (Int(decompressed[0]) << 16) | (Int(decompressed[1]) << 8) | Int(decompressed[2])
                    let actualLen = min(tLen, decompressed.count - 3)
                    if actualLen > 0 {
                        text = String(bytes: decompressed[3..<(3 + actualLen)], encoding: .utf8)
                    }
                }
            } else if chunkID == "TXTa" {
                let raw = Array(bytes[chunkDataStart..<chunkDataEnd])
                if raw.count >= 3 {
                    let tLen = (Int(raw[0]) << 16) | (Int(raw[1]) << 8) | Int(raw[2])
                    let actualLen = min(tLen, raw.count - 3)
                    if actualLen > 0 {
                        text = String(bytes: raw[3..<(3 + actualLen)], encoding: .utf8)
                    }
                }
            } else if chunkID == "Sjbz" {
                sjbzData = Array(bytes[chunkDataStart..<chunkDataEnd])
            }
            
            pos = chunkDataEnd
            if sz % 2 == 1 { pos += 1 }
        }
        
        if let t = text, !t.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return DjVuPageText(pageNumber: pageNum, text: t)
        }
        
        // Fallback: If no embedded text layer, perform OCR on JB2 image mask using Apple Vision
        if let sjbz = sjbzData {
            let jb2 = JB2Image(data: sjbz)
            if (try? jb2.readHeader()) != nil {
                try? jb2.decode(shared: sharedDict)
                let mask = jb2.renderMask()
                let w = jb2.width
                let h = jb2.height
                if w > 0 && h > 0 && mask.count == w * h {
                    var gray = [UInt8](repeating: 255, count: w * h)
                    for i in 0..<mask.count where mask[i] != 0 {
                        gray[i] = 0 // ink pixel is black
                    }
                    let cs = CGColorSpaceCreateDeviceGray()
                    if let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue),
                       let cgImage = ctx.makeImage() {
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try? handler.perform([request])
                        if let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty {
                            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                            let ocrText = lines.joined(separator: "\n")
                            if !ocrText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                                return DjVuPageText(pageNumber: pageNum, text: ocrText)
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
}

// MARK: - DjVu Writer (Pure Swift Bilevel JB2 + Searchable Text)

enum DjVuWriter {
    static func writeDjVu(fromPDF pdfURL: URL, to outURL: URL) throws {
        guard let pdf = PDFDocument(url: pdfURL) else {
            throw ConversionError("Could not open source PDF for DjVu conversion: \(pdfURL.path)")
        }
        let count = pdf.pageCount
        guard count > 0 else {
            throw ConversionError("Source document contains 0 pages")
        }
        
        var pageSpecs = [DjVuPageSpec]()
        let dpi = 150
        let scale = CGFloat(dpi) / 72.0
        
        for i in 0..<count {
            guard let page = pdf.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let w = max(1, Int(box.width * scale))
            let h = max(1, Int(box.height * scale))
            
            var gray = [UInt8](repeating: 255, count: w * h)
            let cs = CGColorSpaceCreateDeviceGray()
            guard let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                throw ConversionError("Could not allocate graphics buffer for page rendering")
            }
            
            ctx.setFillColor(gray: 1.0, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
            
            var bits = [UInt8](repeating: 0, count: w * h)
            for idx in 0..<gray.count {
                if gray[idx] < 200 { bits[idx] = 1 }
            }
            
            let text = page.string ?? ""
            pageSpecs.append(DjVuPageSpec(width: w, height: h, dpi: dpi, text: text, bits: bits))
        }
        
        let djvuData = try packageDjVu(pages: pageSpecs)
        try djvuData.write(to: outURL, options: .atomic)
    }

    private static func makePageChunk(spec: DjVuPageSpec) -> [UInt8] {
        let jb2Data = JB2Encoder.encodePage(width: spec.width, height: spec.height, bits: spec.bits)
        
        // INFO chunk: 10 bytes
        var info = [UInt8]()
        info.append(UInt8((spec.width >> 8) & 0xff))
        info.append(UInt8(spec.width & 0xff))
        info.append(UInt8((spec.height >> 8) & 0xff))
        info.append(UInt8(spec.height & 0xff))
        info.append(24) // minor version
        info.append(0)  // major version
        info.append(UInt8(spec.dpi & 0xff))        // dpi low
        info.append(UInt8((spec.dpi >> 8) & 0xff)) // dpi high
        info.append(22) // gamma = 2.2
        info.append(1)  // rotation = 1 (upright)
        
        // Text chunk (TXTa)
        var txta = [UInt8]()
        let textBytes = Array(spec.text.utf8)
        let tLen = textBytes.count
        txta.append(UInt8((tLen >> 16) & 0xff))
        txta.append(UInt8((tLen >> 8) & 0xff))
        txta.append(UInt8(tLen & 0xff))
        txta.append(contentsOf: textBytes)
        txta.append(1) // version
        
        func chunk(id: String, payload: [UInt8]) -> [UInt8] {
            var out = [UInt8]()
            out.append(contentsOf: Array(id.utf8))
            let sz = payload.count
            out.append(UInt8((sz >> 24) & 0xff))
            out.append(UInt8((sz >> 16) & 0xff))
            out.append(UInt8((sz >> 8) & 0xff))
            out.append(UInt8(sz & 0xff))
            out.append(contentsOf: payload)
            if sz % 2 == 1 { out.append(0) }
            return out
        }
        
        var formPayload = [UInt8]()
        formPayload.append(contentsOf: Array("DJVU".utf8))
        formPayload.append(contentsOf: chunk(id: "INFO", payload: info))
        formPayload.append(contentsOf: chunk(id: "Sjbz", payload: jb2Data))
        if !textBytes.isEmpty {
            formPayload.append(contentsOf: chunk(id: "TXTa", payload: txta))
        }
        
        var pageForm = [UInt8]()
        pageForm.append(contentsOf: Array("FORM".utf8))
        let sz = formPayload.count
        pageForm.append(UInt8((sz >> 24) & 0xff))
        pageForm.append(UInt8((sz >> 16) & 0xff))
        pageForm.append(UInt8((sz >> 8) & 0xff))
        pageForm.append(UInt8(sz & 0xff))
        pageForm.append(contentsOf: formPayload)
        if sz % 2 == 1 { pageForm.append(0) }
        return pageForm
    }

    private static func packageDjVu(pages: [DjVuPageSpec]) throws -> Data {
        if pages.count == 1 {
            let p = makePageChunk(spec: pages[0])
            var file = [UInt8]()
            file.append(contentsOf: Array("AT&T".utf8))
            file.append(contentsOf: p)
            return Data(file)
        }
        
        var pageChunks = [[UInt8]]()
        for p in pages {
            pageChunks.append(makePageChunk(spec: p))
        }
        
        let nfiles = pages.count
        var bzzPayload = [UInt8]()
        for chunk in pageChunks {
            let sz = chunk.count
            bzzPayload.append(UInt8((sz >> 16) & 0xff))
            bzzPayload.append(UInt8((sz >> 8) & 0xff))
            bzzPayload.append(UInt8(sz & 0xff))
        }
        for _ in 0..<nfiles {
            bzzPayload.append(1) // page flag
        }
        for i in 0..<nfiles {
            let name = String(format: "p%04d.djvu", i + 1)
            bzzPayload.append(contentsOf: Array(name.utf8))
            bzzPayload.append(0) // null-terminated
        }
        bzzPayload.append(0)
        
        let compressedBzz = BZZ.encode(bzzPayload)
        
        var dirmPayload = [UInt8]()
        dirmPayload.append(0x80) // bundled flag
        dirmPayload.append(UInt8((nfiles >> 8) & 0xff))
        dirmPayload.append(UInt8(nfiles & 0xff))
        let offsetsPlaceholderIndex = dirmPayload.count
        for _ in 0..<nfiles {
            dirmPayload.append(0); dirmPayload.append(0); dirmPayload.append(0); dirmPayload.append(0)
        }
        dirmPayload.append(contentsOf: compressedBzz)
        
        var dirmChunk = [UInt8]()
        dirmChunk.append(contentsOf: Array("DIRM".utf8))
        let dirmSz = dirmPayload.count
        dirmChunk.append(UInt8((dirmSz >> 24) & 0xff))
        dirmChunk.append(UInt8((dirmSz >> 16) & 0xff))
        dirmChunk.append(UInt8((dirmSz >> 8) & 0xff))
        dirmChunk.append(UInt8(dirmSz & 0xff))
        dirmChunk.append(contentsOf: dirmPayload)
        if dirmSz % 2 == 1 { dirmChunk.append(0) }
        
        var currentOffset = 16 + dirmChunk.count
        var offsets = [Int]()
        for chunk in pageChunks {
            if currentOffset % 2 == 1 { currentOffset += 1 }
            offsets.append(currentOffset)
            currentOffset += chunk.count
        }
        
        for (i, off) in offsets.enumerated() {
            let base = offsetsPlaceholderIndex + i * 4
            dirmChunk[8 + base] = UInt8((off >> 24) & 0xff)
            dirmChunk[8 + base + 1] = UInt8((off >> 16) & 0xff)
            dirmChunk[8 + base + 2] = UInt8((off >> 8) & 0xff)
            dirmChunk[8 + base + 3] = UInt8(off & 0xff)
        }
        
        var djvmPayload = [UInt8]()
        djvmPayload.append(contentsOf: Array("DJVM".utf8))
        djvmPayload.append(contentsOf: dirmChunk)
        for chunk in pageChunks {
            if djvmPayload.count % 2 == 1 { djvmPayload.append(0) }
            djvmPayload.append(contentsOf: chunk)
        }
        
        var fileData = [UInt8]()
        fileData.append(contentsOf: Array("AT&T".utf8))
        fileData.append(contentsOf: Array("FORM".utf8))
        let totalLen = djvmPayload.count
        fileData.append(UInt8((totalLen >> 24) & 0xff))
        fileData.append(UInt8((totalLen >> 16) & 0xff))
        fileData.append(UInt8((totalLen >> 8) & 0xff))
        fileData.append(UInt8(totalLen & 0xff))
        fileData.append(contentsOf: djvmPayload)
        
        return Data(fileData)
    }
}
