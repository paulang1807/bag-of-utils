import Foundation

// JB2 bi-level image codec (DjVu "Sjbz" / "Djbz" chunks): decoder and a simple encoder.

/// Bi-level bitmap. Row 0 is the BOTTOM row (DjVu coordinate system); one byte per pixel.
final class JB2Bitmap {
    let width: Int
    let height: Int
    var px: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.px = [UInt8](repeating: 0, count: max(0, width * height))
    }

    @inline(__always)
    func get(_ i: Int, _ j: Int) -> Int {
        if i < 0 || i >= height || j < 0 || j >= width { return 0 }
        return Int(px[i * width + j])
    }

    @inline(__always)
    func set(_ i: Int, _ j: Int) {
        px[i * width + j] = 1
    }

    /// Crops fully empty borders (used before storing a symbol in the dictionary).
    func removingEmptyEdges() -> JB2Bitmap {
        var bottom = 0
        var top = 0
        var left = 0
        var right = 0
        var found = false
        rows: for i in 0..<height {
            for j in 0..<width where px[i * width + j] != 0 {
                found = true
                break rows
            }
            bottom += 1
        }
        if !found { return self }
        rows2: for i in stride(from: height - 1, through: 0, by: -1) {
            for j in 0..<width where px[i * width + j] != 0 { break rows2 }
            top += 1
        }
        cols: for j in 0..<width {
            for i in 0..<height where px[i * width + j] != 0 { break cols }
            left += 1
        }
        cols2: for j in stride(from: width - 1, through: 0, by: -1) {
            for i in 0..<height where px[i * width + j] != 0 { break cols2 }
            right += 1
        }
        if top == 0 && bottom == 0 && left == 0 && right == 0 { return self }
        let newW = width - left - right
        let newH = height - top - bottom
        let out = JB2Bitmap(width: newW, height: newH)
        for p in 0..<newH {
            for q in 0..<newW where px[(bottom + p) * width + (left + q)] != 0 {
                out.px[p * newW + q] = 1
            }
        }
        return out
    }
}

final class JB2NumContext {
    var ctx: UInt8 = 0
    private var leftNode: JB2NumContext?
    private var rightNode: JB2NumContext?

    var left: JB2NumContext {
        if let l = leftNode { return l }
        let n = JB2NumContext()
        leftNode = n
        return n
    }

    var right: JB2NumContext {
        if let r = rightNode { return r }
        let n = JB2NumContext()
        rightNode = n
        return n
    }
}

struct JB2Baseline {
    private var arr = [0, 0, 0]
    private var index = -1

    mutating func add(_ val: Int) {
        index += 1
        if index == 3 { index = 0 }
        arr[index] = val
    }

    func value() -> Int {
        if (arr[0] >= arr[1] && arr[0] <= arr[2]) || (arr[0] <= arr[1] && arr[0] >= arr[2]) {
            return arr[0]
        } else if (arr[1] >= arr[0] && arr[1] <= arr[2]) || (arr[1] <= arr[0] && arr[1] >= arr[2]) {
            return arr[1]
        }
        return arr[2]
    }

    mutating func fill(_ val: Int) {
        arr = [val, val, val]
    }
}

/// Shared by decoding and encoding: context models and bitmap context formulas.
class JB2Contexts {
    var directCtx = [UInt8](repeating: 0, count: 1024)
    var refinementCtx = [UInt8](repeating: 0, count: 2048)
    var offsetTypeCtx: UInt8 = 0

    var recordTypeCtx = JB2NumContext()
    var imageSizeCtx = JB2NumContext()
    var symbolWidthCtx = JB2NumContext()
    var symbolHeightCtx = JB2NumContext()
    var inheritDictSizeCtx = JB2NumContext()
    var hoffCtx = JB2NumContext()
    var voffCtx = JB2NumContext()
    var shoffCtx = JB2NumContext()
    var svoffCtx = JB2NumContext()
    var symbolIndexCtx = JB2NumContext()
    var symbolHeightDiffCtx = JB2NumContext()
    var symbolWidthDiffCtx = JB2NumContext()
    var commentLengthCtx = JB2NumContext()
    var commentOctetCtx = JB2NumContext()
    var horizontalAbsLocationCtx = JB2NumContext()
    var verticalAbsLocationCtx = JB2NumContext()

    func resetNumContexts() {
        recordTypeCtx = JB2NumContext()
        imageSizeCtx = JB2NumContext()
        symbolWidthCtx = JB2NumContext()
        symbolHeightCtx = JB2NumContext()
        inheritDictSizeCtx = JB2NumContext()
        hoffCtx = JB2NumContext()
        voffCtx = JB2NumContext()
        shoffCtx = JB2NumContext()
        svoffCtx = JB2NumContext()
        symbolIndexCtx = JB2NumContext()
        symbolHeightDiffCtx = JB2NumContext()
        symbolWidthDiffCtx = JB2NumContext()
        commentLengthCtx = JB2NumContext()
        commentOctetCtx = JB2NumContext()
        horizontalAbsLocationCtx = JB2NumContext()
        verticalAbsLocationCtx = JB2NumContext()
    }

    @inline(__always)
    final func directIndex(_ bm: JB2Bitmap, _ i: Int, _ j: Int) -> Int {
        var idx = (bm.get(i + 2, j - 1) << 9) | (bm.get(i + 2, j) << 8) | (bm.get(i + 2, j + 1) << 7)
        idx |= (bm.get(i + 1, j - 2) << 6) | (bm.get(i + 1, j - 1) << 5) | (bm.get(i + 1, j) << 4)
        idx |= (bm.get(i + 1, j + 1) << 3) | (bm.get(i + 1, j + 2) << 2)
        idx |= (bm.get(i, j - 2) << 1) | bm.get(i, j - 1)
        return idx
    }

    final func refinementIndex(_ cbm: JB2Bitmap, _ mbm: JB2Bitmap, _ rowShift: Int, _ colShift: Int, _ i: Int, _ j: Int) -> Int {
        var idx = (cbm.get(i + 1, j - 1) << 10) | (cbm.get(i + 1, j) << 9) | (cbm.get(i + 1, j + 1) << 8)
        idx |= cbm.get(i, j - 1) << 7
        var r = i + rowShift + 1
        let c = j + colShift
        idx |= mbm.get(r, c) << 6
        r -= 1
        idx |= (mbm.get(r, c - 1) << 5) | (mbm.get(r, c) << 4) | (mbm.get(r, c + 1) << 3)
        r -= 1
        idx |= (mbm.get(r, c - 1) << 2) | (mbm.get(r, c) << 1) | mbm.get(r, c + 1)
        return idx
    }
}

let jb2MaxPixels = 120_000_000

class JB2Decoder: JB2Contexts {
    let zp: ZPDecoder

    init(data: [UInt8]) {
        zp = ZPDecoder(data: data)
        super.init()
    }

    func decodeNum(_ lowIn: Int, _ highIn: Int, _ ctxIn: JB2NumContext) -> Int {
        var low = lowIn
        var high = highIn
        var numctx = ctxIn
        var negative = false
        var cutoff = 0
        var phase = 1
        var range = 0xffffffff
        while range != 1 {
            let decision: Bool
            if low >= cutoff {
                decision = true
            } else if high >= cutoff {
                decision = zp.decode(&numctx.ctx) != 0
            } else {
                decision = false
            }
            numctx = decision ? numctx.right : numctx.left
            switch phase {
            case 1:
                negative = !decision
                if negative {
                    let temp = -low - 1
                    low = -high - 1
                    high = temp
                }
                phase = 2
                cutoff = 1
            case 2:
                if !decision {
                    phase = 3
                    range = (cutoff + 1) / 2
                    if range == 1 {
                        cutoff = 0
                    } else {
                        cutoff -= range / 2
                    }
                } else {
                    cutoff += cutoff + 1
                }
            default:
                range /= 2
                if range != 1 {
                    if !decision {
                        cutoff -= range / 2
                    } else {
                        cutoff += range / 2
                    }
                } else if !decision {
                    cutoff -= 1
                }
            }
        }
        return negative ? (-cutoff - 1) : cutoff
    }

    func decodeBitmap(_ width: Int, _ height: Int) throws -> JB2Bitmap {
        if width < 0 || height < 0 || width * height > jb2MaxPixels {
            throw DjVuError("JB2 symbol is too large")
        }
        let bm = JB2Bitmap(width: width, height: height)
        if width == 0 || height == 0 { return bm }
        var i = height - 1
        while i >= 0 {
            for j in 0..<width {
                let idx = directIndex(bm, i, j)
                if zp.decode(&directCtx[idx]) != 0 { bm.set(i, j) }
            }
            i -= 1
        }
        return bm
    }

    func decodeBitmapRef(_ width: Int, _ height: Int, _ mbm: JB2Bitmap) throws -> JB2Bitmap {
        if width < 0 || height < 0 || width * height > jb2MaxPixels {
            throw DjVuError("JB2 symbol is too large")
        }
        let cbm = JB2Bitmap(width: width, height: height)
        if width == 0 || height == 0 { return cbm }
        let rowShift = ((mbm.height - 1) >> 1) - ((cbm.height - 1) >> 1)
        let colShift = ((mbm.width - 1) >> 1) - ((cbm.width - 1) >> 1)
        var i = height - 1
        while i >= 0 {
            for j in 0..<width {
                let idx = refinementIndex(cbm, mbm, rowShift, colShift, i, j)
                if zp.decode(&refinementCtx[idx]) != 0 { cbm.set(i, j) }
            }
            i -= 1
        }
        return cbm
    }

    func decodeComment() {
        let length = decodeNum(0, 262142, commentLengthCtx)
        var n = 0
        while n < length {
            _ = decodeNum(0, 255, commentOctetCtx)
            n += 1
        }
    }
}

final class JB2Dict: JB2Decoder {
    var dict: [JB2Bitmap] = []
    private var decoded = false

    func decode(shared: JB2Dict?) throws {
        if decoded { return }
        decoded = true
        var type = decodeNum(0, 11, recordTypeCtx)
        if type == 9 {
            let size = decodeNum(0, 262142, inheritDictSizeCtx)
            if let s = shared {
                try s.decode(shared: nil)
                dict = Array(s.dict.prefix(size))
            }
            type = decodeNum(0, 11, recordTypeCtx)
        }
        _ = decodeNum(0, 262142, imageSizeCtx)
        _ = decodeNum(0, 262142, imageSizeCtx)
        var flagCtx: UInt8 = 0
        if zp.decode(&flagCtx) != 0 { throw DjVuError("Bad JB2 dictionary flag") }
        type = decodeNum(0, 11, recordTypeCtx)

        var records = 0
        while type != 11 {
            records += 1
            if records > 5_000_000 { throw DjVuError("JB2 dictionary is corrupted") }
            switch type {
            case 2:
                let w = decodeNum(0, 262142, symbolWidthCtx)
                let h = decodeNum(0, 262142, symbolHeightCtx)
                dict.append(try decodeBitmap(w, h))
            case 5:
                guard !dict.isEmpty else { throw DjVuError("JB2 dictionary is corrupted") }
                let idx = decodeNum(0, dict.count - 1, symbolIndexCtx)
                let wd = decodeNum(-262143, 262142, symbolWidthDiffCtx)
                let hd = decodeNum(-262143, 262142, symbolHeightDiffCtx)
                let mbm = dict[idx]
                let cbm = try decodeBitmapRef(mbm.width + wd, hd + mbm.height, mbm)
                dict.append(cbm.removingEmptyEdges())
            case 9:
                resetNumContexts()
            case 10:
                decodeComment()
            default:
                throw DjVuError("Unsupported JB2 dictionary record \(type)")
            }
            type = decodeNum(0, 11, recordTypeCtx)
            if type > 11 { break }
        }
    }
}

struct JB2Blit {
    let bitmap: JB2Bitmap
    let x: Int
    let y: Int
}

final class JB2Image: JB2Decoder {
    private(set) var width = 0
    private(set) var height = 0
    private(set) var blits: [JB2Blit] = []
    private var dict: [JB2Bitmap] = []
    private var initialDictLength = 0
    private var lastRight = 0
    private var firstLeft = -1
    private var firstBottom = 0
    private var baseline = JB2Baseline()

    override init(data: [UInt8]) {
        super.init(data: data)
    }

    /// Reads the image header. Must be called before `decode`.
    func readHeader() throws {
        var type = decodeNum(0, 11, recordTypeCtx)
        if type == 9 {
            initialDictLength = decodeNum(0, 262142, inheritDictSizeCtx)
            type = decodeNum(0, 11, recordTypeCtx)
        }
        width = decodeNum(0, 262142, imageSizeCtx)
        height = decodeNum(0, 262142, imageSizeCtx)
        if width == 0 { width = 200 }
        if height == 0 { height = 200 }
        if width * height > jb2MaxPixels { throw DjVuError("JB2 image is too large") }
        firstBottom = height - 1
        var flagCtx: UInt8 = 0
        if zp.decode(&flagCtx) != 0 { throw DjVuError("Bad JB2 image flag") }
    }

    func decode(shared: JB2Dict?) throws {
        if initialDictLength > 0 {
            if let s = shared {
                try s.decode(shared: nil)
                dict = Array(s.dict.prefix(initialDictLength))
            }
        }
        var type = decodeNum(0, 11, recordTypeCtx)
        var records = 0
        while type != 11 {
            records += 1
            if records > 5_000_000 { throw DjVuError("JB2 image is corrupted") }
            switch type {
            case 1:
                let w = decodeNum(0, 262142, symbolWidthCtx)
                let h = decodeNum(0, 262142, symbolHeightCtx)
                let bm = try decodeBitmap(w, h)
                let c = decodeSymbolCoords(bm.width, bm.height)
                blits.append(JB2Blit(bitmap: bm, x: c.x, y: c.y))
                dict.append(bm.removingEmptyEdges())
            case 2:
                let w = decodeNum(0, 262142, symbolWidthCtx)
                let h = decodeNum(0, 262142, symbolHeightCtx)
                dict.append(try decodeBitmap(w, h).removingEmptyEdges())
            case 3:
                let w = decodeNum(0, 262142, symbolWidthCtx)
                let h = decodeNum(0, 262142, symbolHeightCtx)
                let bm = try decodeBitmap(w, h)
                let c = decodeSymbolCoords(bm.width, bm.height)
                blits.append(JB2Blit(bitmap: bm, x: c.x, y: c.y))
            case 4, 5, 6:
                guard !dict.isEmpty else { throw DjVuError("JB2 image is corrupted") }
                let idx = decodeNum(0, dict.count - 1, symbolIndexCtx)
                let wd = decodeNum(-262143, 262142, symbolWidthDiffCtx)
                let hd = decodeNum(-262143, 262142, symbolHeightDiffCtx)
                let mbm = dict[idx]
                let cbm = try decodeBitmapRef(mbm.width + wd, hd + mbm.height, mbm)
                if type != 5 {
                    let c = decodeSymbolCoords(cbm.width, cbm.height)
                    blits.append(JB2Blit(bitmap: cbm, x: c.x, y: c.y))
                }
                if type != 6 {
                    dict.append(cbm.removingEmptyEdges())
                }
            case 7:
                guard !dict.isEmpty else { throw DjVuError("JB2 image is corrupted") }
                let idx = decodeNum(0, dict.count - 1, symbolIndexCtx)
                let bm = dict[idx]
                let c = decodeSymbolCoords(bm.width, bm.height)
                blits.append(JB2Blit(bitmap: bm, x: c.x, y: c.y))
            case 8:
                let w = decodeNum(0, 262142, symbolWidthCtx)
                let h = decodeNum(0, 262142, symbolHeightCtx)
                let bm = try decodeBitmap(w, h)
                let left = decodeNum(1, width, horizontalAbsLocationCtx)
                let top = decodeNum(1, height, verticalAbsLocationCtx)
                blits.append(JB2Blit(bitmap: bm, x: left - 1, y: top - bm.height))
            case 9:
                resetNumContexts()
            case 10:
                decodeComment()
            default:
                throw DjVuError("Unsupported JB2 record \(type)")
            }
            type = decodeNum(0, 11, recordTypeCtx)
            if type > 11 { break }
        }
    }

    private func decodeSymbolCoords(_ w: Int, _ h: Int) -> (x: Int, y: Int) {
        let flag = zp.decode(&offsetTypeCtx)
        let hctx = flag != 0 ? hoffCtx : shoffCtx
        let vctx = flag != 0 ? voffCtx : svoffCtx
        let hoff = decodeNum(-262143, 262142, hctx)
        let voff = decodeNum(-262143, 262142, vctx)
        var x: Int
        var y: Int
        if flag != 0 {
            x = firstLeft + hoff
            y = firstBottom + voff - h + 1
            firstLeft = x
            firstBottom = y
            baseline.fill(y)
        } else {
            x = lastRight + hoff
            y = baseline.value() + voff
        }
        baseline.add(y)
        lastRight = x + w - 1
        return (x, y)
    }

    /// Paints all blits into a top-down mask (1 = ink), size `width * height`.
    func renderMask() -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: width * height)
        for blit in blits {
            let bm = blit.bitmap
            for k in 0..<bm.height {
                let row = blit.y + k
                if row < 0 || row >= height { continue }
                let base = (height - 1 - row) * width
                for t in 0..<bm.width where bm.px[k * bm.width + t] != 0 {
                    let col = blit.x + t
                    if col >= 0 && col < width { mask[base + col] = 1 }
                }
            }
        }
        return mask
    }
}

// MARK: - Encoder

final class JB2Encoder: JB2Contexts {
    let zp = ZPEncoder()

    func encodeNum(_ valueIn: Int, _ lowIn: Int, _ highIn: Int, _ ctxIn: JB2NumContext) {
        var v = valueIn
        var low = lowIn
        var high = highIn
        var numctx = ctxIn
        var negative = false
        var cutoff = 0
        var phase = 1
        var range = 0xffffffff
        while range != 1 {
            let decision: Bool
            if low >= cutoff {
                decision = true
            } else if high >= cutoff {
                decision = v >= cutoff
                zp.encode(decision ? 1 : 0, &numctx.ctx)
            } else {
                decision = false
            }
            numctx = decision ? numctx.right : numctx.left
            switch phase {
            case 1:
                negative = !decision
                if negative {
                    let temp = -low - 1
                    low = -high - 1
                    high = temp
                    v = -v - 1
                }
                phase = 2
                cutoff = 1
            case 2:
                if !decision {
                    phase = 3
                    range = (cutoff + 1) / 2
                    if range == 1 {
                        cutoff = 0
                    } else {
                        cutoff -= range / 2
                    }
                } else {
                    cutoff += cutoff + 1
                }
            default:
                range /= 2
                if range != 1 {
                    if !decision {
                        cutoff -= range / 2
                    } else {
                        cutoff += range / 2
                    }
                } else if !decision {
                    cutoff -= 1
                }
            }
        }
    }

    func encodeBitmap(_ bm: JB2Bitmap) {
        if bm.width == 0 || bm.height == 0 { return }
        var i = bm.height - 1
        while i >= 0 {
            for j in 0..<bm.width {
                let idx = directIndex(bm, i, j)
                zp.encode(bm.get(i, j), &directCtx[idx])
            }
            i -= 1
        }
    }

    /// Encodes a whole page as a single "non-symbol" bitmap record.
    /// `bits` is top-down, one byte per pixel, nonzero = ink.
    static func encodePage(width: Int, height: Int, bits: [UInt8]) -> [UInt8] {
        let enc = JB2Encoder()
        enc.encodeNum(0, 0, 11, enc.recordTypeCtx)
        enc.encodeNum(width, 0, 262142, enc.imageSizeCtx)
        enc.encodeNum(height, 0, 262142, enc.imageSizeCtx)
        var flagCtx: UInt8 = 0
        enc.zp.encode(0, &flagCtx)

        var hasInk = false
        for b in bits where b != 0 {
            hasInk = true
            break
        }
        if hasInk {
            let bm = JB2Bitmap(width: width, height: height)
            for ytop in 0..<height {
                let i = height - 1 - ytop
                for j in 0..<width where bits[ytop * width + j] != 0 {
                    bm.set(i, j)
                }
            }
            enc.encodeNum(8, 0, 11, enc.recordTypeCtx)
            enc.encodeNum(width, 0, 262142, enc.symbolWidthCtx)
            enc.encodeNum(height, 0, 262142, enc.symbolHeightCtx)
            enc.encodeBitmap(bm)
            enc.encodeNum(1, 1, width, enc.horizontalAbsLocationCtx)
            enc.encodeNum(height, 1, height, enc.verticalAbsLocationCtx)
        }
        enc.encodeNum(11, 0, 11, enc.recordTypeCtx)
        enc.zp.finish()
        return enc.zp.output
    }
}
