import Foundation

// Self-contained DjVu codecs: ZP arithmetic coder and BZZ (Burrows-Wheeler) compression.
// No external tools or libraries are used.

struct DjVuError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { return message }
}

// MARK: - Byte reading helpers

struct ByteReader {
    let bytes: [UInt8]
    var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var isAtEnd: Bool { return offset >= bytes.count }

    mutating func u8() throws -> Int {
        guard offset < bytes.count else { throw DjVuError("Unexpected end of DjVu data") }
        let v = Int(bytes[offset])
        offset += 1
        return v
    }

    mutating func u16() throws -> Int {
        let a = try u8()
        let b = try u8()
        return (a << 8) | b
    }

    mutating func u24() throws -> Int {
        let a = try u8()
        let b = try u8()
        let c = try u8()
        return (a << 16) | (b << 8) | c
    }

    mutating func u32() throws -> Int {
        let a = try u16()
        let b = try u16()
        return (a << 16) | b
    }

    mutating func take(_ n: Int) throws -> [UInt8] {
        guard n >= 0, offset + n <= bytes.count else { throw DjVuError("Unexpected end of DjVu data") }
        let out = Array(bytes[offset..<(offset + n)])
        offset += n
        return out
    }

    mutating func cString() throws -> String {
        var out: [UInt8] = []
        while true {
            let b = try u8()
            if b == 0 { break }
            out.append(UInt8(b))
        }
        return String(decoding: out, as: UTF8.self)
    }
}

// MARK: - ZP decoder

final class ZPDecoder {
    private let data: [UInt8]
    private var pos: Int
    private var a = 0
    private var c = 0
    private var f = 0
    private var scount = 0
    private var buffer = 0
    private let ffzt: [Int]

    init(data: [UInt8], start: Int = 0) {
        self.data = data
        self.pos = start
        var table = [Int](repeating: 0, count: 256)
        for i in 0..<256 {
            var j = i
            var n = 0
            while (j & 0x80) != 0 {
                n += 1
                j <<= 1
            }
            table[i] = n
        }
        ffzt = table
        c = nextByte() << 8
        c |= nextByte()
        f = min(c, 0x7fff)
        preload()
    }

    private func nextByte() -> Int {
        if pos >= data.count {
            pos += 1
            return 0xff
        }
        let v = Int(data[pos])
        pos += 1
        return v
    }

    private func preload() {
        while scount <= 24 {
            buffer = ((buffer << 8) | nextByte()) & 0xffffffff
            scount += 8
        }
    }

    private func ffz(_ x: Int) -> Int {
        return x >= 0xff00 ? ffzt[x & 0xff] + 8 : ffzt[(x >> 8) & 0xff]
    }

    /// Decodes one bit using (and adapting) the given context.
    func decode(_ ctx: inout UInt8) -> Int {
        var b = Int(ctx) & 1
        var z = a + Int(zpP[Int(ctx)])
        if z <= f {
            a = z
            return b
        }
        let d = 0x6000 + ((a + z) >> 2)
        if z > d { z = d }
        if z > c {
            b = 1 - b
            z = 0x10000 - z
            a += z
            c += z
            ctx = zpDn[Int(ctx)]
            let shift = ffz(a)
            scount -= shift
            a = (a << shift) & 0xffff
            c = ((c << shift) | ((buffer >> scount) & ((1 << shift) - 1))) & 0xffff
        } else {
            if a >= Int(zpM[Int(ctx)]) {
                ctx = zpUp[Int(ctx)]
            }
            scount -= 1
            a = (z << 1) & 0xffff
            c = ((c << 1) | ((buffer >> scount) & 1)) & 0xffff
        }
        if scount < 16 { preload() }
        f = min(c, 0x7fff)
        return b
    }

    /// Decodes one bit without a context (probability ~0.5).
    func decodeRaw() -> Int {
        return passThrough(0x8000 + (a >> 1))
    }

    /// Decodes one bit with the IW44 pass-through probability.
    func decodeIW() -> Int {
        return passThrough(0x8000 + ((a + a + a) >> 3))
    }

    private func passThrough(_ zIn: Int) -> Int {
        var z = zIn
        var b = 0
        if z > c {
            b = 1
            z = 0x10000 - z
            a += z
            c += z
            let shift = ffz(a)
            scount -= shift
            a = (a << shift) & 0xffff
            c = ((c << shift) | ((buffer >> scount) & ((1 << shift) - 1))) & 0xffff
        } else {
            scount -= 1
            a = (z << 1) & 0xffff
            c = ((c << 1) | ((buffer >> scount) & 1)) & 0xffff
        }
        if scount < 16 { preload() }
        f = min(c, 0x7fff)
        return b
    }
}

// MARK: - ZP encoder

final class ZPEncoder {
    private(set) var output: [UInt8] = []
    private var a = 0
    private var scount = 0
    private var byte = 0
    private var delay = 25
    private var subend = 0
    private var buffer: UInt32 = 0xffffff
    private var nrun = 0

    private func outbit(_ bit: Int) {
        if delay > 0 {
            if delay < 0xff { delay -= 1 }
        } else {
            byte = ((byte << 1) | bit) & 0xff
            scount += 1
            if scount == 8 {
                output.append(UInt8(byte))
                scount = 0
                byte = 0
            }
        }
    }

    private func zemit(_ bIn: Int) {
        buffer = (buffer << 1) &+ UInt32(truncatingIfNeeded: bIn)
        let b = Int(buffer >> 24)
        buffer &= 0xffffff
        switch b {
        case 1:
            outbit(1)
            while nrun > 0 {
                outbit(0)
                nrun -= 1
            }
            nrun = 0
        case 0xff:
            outbit(0)
            while nrun > 0 {
                outbit(1)
                nrun -= 1
            }
            nrun = 0
        case 0:
            nrun += 1
        default:
            break
        }
    }

    func encode(_ bit: Int, _ ctx: inout UInt8) {
        var z = a + Int(zpP[Int(ctx)])
        if bit != (Int(ctx) & 1) {
            let d = 0x6000 + ((z + a) >> 2)
            if z > d { z = d }
            ctx = zpDn[Int(ctx)]
            z = 0x10000 - z
            subend += z
            a += z
        } else if z >= 0x8000 {
            let d = 0x6000 + ((z + a) >> 2)
            if z > d { z = d }
            if a >= Int(zpM[Int(ctx)]) {
                ctx = zpUp[Int(ctx)]
            }
            a = z
        } else {
            a = z
            return
        }
        exportBits()
    }

    func encodeRaw(_ bit: Int) {
        passThrough(bit, 0x8000 + (a >> 1))
    }

    private func passThrough(_ bit: Int, _ zIn: Int) {
        var z = zIn
        if bit != 0 {
            z = 0x10000 - z
            subend += z
            a += z
        } else {
            a = z
        }
        exportBits()
    }

    private func exportBits() {
        while a >= 0x8000 {
            zemit(1 - (subend >> 15))
            subend = 0xffff & (subend << 1)
            a = 0xffff & (a << 1)
        }
    }

    /// Flushes pending bits. Must be called once after the last symbol.
    func finish() {
        if subend > 0x8000 {
            subend = 0x10000
        } else if subend > 0 {
            subend = 0x8000
        }
        while buffer != 0xffffff || subend != 0 {
            zemit(1 - (subend >> 15))
            subend = 0xffff & (subend << 1)
        }
        outbit(1)
        while nrun > 0 {
            outbit(0)
            nrun -= 1
        }
        nrun = 0
        while scount > 0 {
            outbit(1)
        }
        delay = 0xff
    }
}

// MARK: - BZZ

enum BZZ {
    private static let freqMax = 4
    private static let ctxIds = 3

    /// Decompresses a complete BZZ stream (possibly several blocks).
    static func decode(_ data: [UInt8], start: Int = 0) throws -> [UInt8] {
        let zp = ZPDecoder(data: data, start: start)
        var ctx = [UInt8](repeating: 0, count: 300)
        var result: [UInt8] = []

        func decodeRaw(_ bits: Int) -> Int {
            var n = 1
            let m = 1 << bits
            while n < m {
                n = (n << 1) | zp.decodeRaw()
            }
            return n - m
        }

        func decodeBinary(_ ctxoffIn: Int, _ bits: Int) -> Int {
            var n = 1
            let m = 1 << bits
            let ctxoff = ctxoffIn - 1
            while n < m {
                let b = zp.decode(&ctx[ctxoff + n])
                n = (n << 1) | b
            }
            return n - m
        }

        while true {
            let size = decodeRaw(24)
            if size == 0 { break }
            if size > 4096 * 1024 { throw DjVuError("BZZ block too large") }

            var fshift = 0
            if zp.decodeRaw() != 0 {
                fshift += 1
                if zp.decodeRaw() != 0 { fshift += 1 }
            }

            var mtf = [UInt8](repeating: 0, count: 256)
            for i in 0..<256 { mtf[i] = UInt8(i) }
            var freq = [Int](repeating: 0, count: freqMax)
            var fadd = 4
            var mtfno = 3
            var markerpos = -1
            var block = [UInt8](repeating: 0, count: size)

            var i = 0
            while i < size {
                var ctxid = ctxIds - 1
                if ctxid > mtfno { ctxid = mtfno }
                var ctxoff = 0
                var matched = false

                if zp.decode(&ctx[ctxoff + ctxid]) != 0 {
                    mtfno = 0
                    matched = true
                }
                if !matched {
                    ctxoff += ctxIds
                    if zp.decode(&ctx[ctxoff + ctxid]) != 0 {
                        mtfno = 1
                        matched = true
                    }
                }
                if !matched {
                    ctxoff += ctxIds
                    // groups of 2^k symbols: (flag context, bits)
                    var base = 2
                    var bits = 1
                    var found = false
                    while bits <= 7 {
                        if zp.decode(&ctx[ctxoff + 0]) != 0 {
                            mtfno = base + decodeBinary(ctxoff + 1, bits)
                            found = true
                            break
                        }
                        ctxoff += (1 << bits)
                        base += (1 << bits)
                        bits += 1
                    }
                    if !found {
                        mtfno = 256
                        block[i] = 0
                        markerpos = i
                        i += 1
                        continue
                    }
                }

                block[i] = mtf[mtfno]

                // Rotate MTF according to empirical frequencies
                fadd = fadd + (fadd >> fshift)
                if fadd > 0x10000000 {
                    fadd >>= 24
                    for k in 0..<freqMax { freq[k] >>= 24 }
                }
                var fc = fadd
                if mtfno < freqMax { fc += freq[mtfno] }
                var k = mtfno
                while k >= freqMax {
                    mtf[k] = mtf[k - 1]
                    k -= 1
                }
                while k > 0 && fc >= freq[k - 1] {
                    mtf[k] = mtf[k - 1]
                    freq[k] = freq[k - 1]
                    k -= 1
                }
                mtf[k] = block[i]
                freq[k] = fc
                i += 1
            }

            if markerpos < 1 || markerpos >= size {
                throw DjVuError("BZZ stream is corrupted")
            }

            // Undo the block-sorting transform
            var pos = [UInt32](repeating: 0, count: size)
            var count = [Int](repeating: 0, count: 256)
            for idx in 0..<markerpos {
                let c = Int(block[idx])
                pos[idx] = (UInt32(c) << 24) | UInt32(count[c] & 0xffffff)
                count[c] += 1
            }
            if markerpos + 1 < size {
                for idx in (markerpos + 1)..<size {
                    let c = Int(block[idx])
                    pos[idx] = (UInt32(c) << 24) | UInt32(count[c] & 0xffffff)
                    count[c] += 1
                }
            }
            var last = 1
            for idx in 0..<256 {
                let tmp = count[idx]
                count[idx] = last
                last += tmp
            }
            var j = 0
            var out = [UInt8](repeating: 0, count: size)
            var remaining = size - 1
            while remaining > 0 {
                let n = pos[j]
                let c = Int(n >> 24)
                remaining -= 1
                out[remaining] = UInt8(c)
                j = count[c] + Int(n & 0xffffff)
                if j < 0 || j >= size { throw DjVuError("BZZ stream is corrupted") }
            }
            if j != markerpos { throw DjVuError("BZZ stream is corrupted") }
            result.append(contentsOf: out[0..<(size - 1)])
        }
        return result
    }

    /// Compresses data as a single BZZ block.
    static func encode(_ payload: [UInt8]) -> [UInt8] {
        // The block is the payload followed by an end-of-block marker byte.
        var arr = payload
        arr.append(0)
        let size = arr.count
        let zp = ZPEncoder()
        var ctx = [UInt8](repeating: 0, count: 300)

        // Block sort (suffix order, marker smallest)
        var markerpos = size - 1
        var offs = [Int](repeating: 0, count: size)
        for i in 0..<size { offs[i] = i }
        let startMarker = markerpos
        offs.sort { (x: Int, y: Int) -> Bool in
            var a = x
            var b = y
            for _ in 0..<size {
                if a == startMarker { return true }
                if b == startMarker { return false }
                let d = Int(arr[a % size]) - Int(arr[b % size])
                if d != 0 { return d < 0 }
                a += 1
                b += 1
            }
            return false
        }
        var data = [UInt8](repeating: 0, count: size)
        for i in 0..<size {
            let p = offs[i] - 1
            if p >= 0 {
                data[i] = arr[p]
            } else {
                data[i] = 0
                markerpos = i
            }
        }

        func encodeRaw(_ bits: Int, _ xIn: Int) {
            var x = xIn
            var n = 1
            let m = 1 << bits
            while n < m {
                x = (x & (m - 1)) << 1
                let b = x >> bits
                zp.encodeRaw(b)
                n = (n << 1) | b
            }
        }

        func encodeBinary(_ ctxoffIn: Int, _ bits: Int, _ xIn: Int) {
            var x = xIn
            var n = 1
            let m = 1 << bits
            let ctxoff = ctxoffIn - 1
            while n < m {
                x = (x & (m - 1)) << 1
                let b = x >> bits
                zp.encode(b, &ctx[ctxoff + n])
                n = (n << 1) | b
            }
        }

        encodeRaw(24, size)
        var fshift = 0
        if size < 100000 {
            fshift = 0
            zp.encodeRaw(0)
        } else if size < 1000000 {
            fshift = 1
            zp.encodeRaw(1)
            zp.encodeRaw(0)
        } else {
            fshift = 2
            zp.encodeRaw(1)
            zp.encodeRaw(1)
        }

        var mtf = [UInt8](repeating: 0, count: 256)
        var rmtf = [Int](repeating: 0, count: 256)
        for m in 0..<256 {
            mtf[m] = UInt8(m)
            rmtf[m] = m
        }
        var freq = [Int](repeating: 0, count: freqMax)
        var fadd = 4
        var mtfno = 3

        for i in 0..<size {
            let c = data[i]
            var ctxid = ctxIds - 1
            if ctxid > mtfno { ctxid = mtfno }
            mtfno = rmtf[Int(c)]
            if i == markerpos { mtfno = 256 }

            var ctxoff = 0
            var done = false

            var b = mtfno == 0 ? 1 : 0
            zp.encode(b, &ctx[ctxoff + ctxid])
            if b != 0 { done = true }

            if !done {
                ctxoff += ctxIds
                b = mtfno == 1 ? 1 : 0
                zp.encode(b, &ctx[ctxoff + ctxid])
                if b != 0 { done = true }
            }
            if !done {
                ctxoff += ctxIds
                var base = 2
                var bits = 1
                while bits <= 7 {
                    b = mtfno < base + (1 << bits) ? 1 : 0
                    zp.encode(b, &ctx[ctxoff])
                    if b != 0 {
                        encodeBinary(ctxoff + 1, bits, mtfno - base)
                        done = true
                        break
                    }
                    ctxoff += (1 << bits)
                    base += (1 << bits)
                    bits += 1
                }
                if !done {
                    // marker symbol (mtfno == 256): nothing more to encode
                    continue
                }
            }

            fadd = fadd + (fadd >> fshift)
            if fadd > 0x10000000 {
                fadd >>= 24
                for k in 0..<freqMax { freq[k] >>= 24 }
            }
            var fc = fadd
            if mtfno < freqMax { fc += freq[mtfno] }
            var k = mtfno
            while k >= freqMax {
                mtf[k] = mtf[k - 1]
                rmtf[Int(mtf[k])] = k
                k -= 1
            }
            while k > 0 && fc >= freq[k - 1] {
                mtf[k] = mtf[k - 1]
                freq[k] = freq[k - 1]
                rmtf[Int(mtf[k])] = k
                k -= 1
            }
            mtf[k] = c
            freq[k] = fc
            rmtf[Int(mtf[k])] = k
        }

        encodeRaw(24, 0)
        zp.finish()
        return zp.output
    }
}
