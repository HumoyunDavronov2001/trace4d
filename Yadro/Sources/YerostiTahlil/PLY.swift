import Foundation
import YerostiGeometriya

/// Nuqta bulutini binary PLY ga yozish. Katta UTM koordinatalari float32 da aniqlikni yo'qotmasligi uchun
/// `boshlangich` ayiriladi va sarlavhaga `comment boshlangich E N H` sifatida yoziladi.
/// Xossalar: x y z (float) [nx ny nz (float)] [red green blue (uchar), DS-07] [t (double), DS-06 — kuzatilgan vaqt].
public enum PLY {
    public static func yoz(_ nuqtalar: [BulutNuqtasi], boshlangich: Vektor3 = .nol, izoh: String = "YEROSTI") -> Data {
        let bor = !nuqtalar.isEmpty
        let normalBor = bor && nuqtalar.allSatisfy { $0.n != nil }
        let rangBor = bor && nuqtalar.allSatisfy { $0.rang != nil }
        let vaqtBor = bor && nuqtalar.allSatisfy { $0.t != nil }
        var s = "ply\nformat binary_little_endian 1.0\ncomment \(izoh)\n"
        s += String(format: "comment boshlangich %.4f %.4f %.4f\n", boshlangich.x, boshlangich.y, boshlangich.z)
        s += "element vertex \(nuqtalar.count)\nproperty float x\nproperty float y\nproperty float z\n"
        if normalBor { s += "property float nx\nproperty float ny\nproperty float nz\n" }
        if rangBor { s += "property uchar red\nproperty uchar green\nproperty uchar blue\n" }
        if vaqtBor { s += "property double t\n" }
        s += "end_header\n"
        var d = Data(s.utf8)
        let qadam = 12 + (normalBor ? 12 : 0) + (rangBor ? 3 : 0) + (vaqtBor ? 8 : 0)
        d.reserveCapacity(d.count + nuqtalar.count * qadam)
        func f(_ x: Double) { var v = Float(x).bitPattern.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        func f64(_ x: Double) { var v = x.bitPattern.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        for b in nuqtalar {
            let p = b.p - boshlangich
            f(p.x); f(p.y); f(p.z)
            if normalBor, let n = b.n { f(n.x); f(n.y); f(n.z) }
            if rangBor, let r = b.rang { d.append(contentsOf: [r.r, r.g, r.b]) }
            if vaqtBor, let t = b.t { f64(t) }
        }
        return d
    }

    /// Binary little-endian PLY o'qish: x y z majburiy; nx ny nz, red green blue, t bo'lsa olinadi; boshqa xossalar o'tkaziladi.
    public static func oqi(_ d: Data) -> (nuqtalar: [BulutNuqtasi], boshlangich: Vektor3)? {
        guard let r = d.range(of: Data("end_header\n".utf8)) else { return nil }
        let sarlavha = String(decoding: d[d.startIndex..<r.lowerBound], as: UTF8.self)
        var soni = 0, bosh = Vektor3.nol, format = ""
        var xossalar: [(nom: String, tur: String, siljish: Int)] = []
        var qadam = 0, vertexIchida = false
        let olcham: [String: Int] = ["char": 1, "int8": 1, "uchar": 1, "uint8": 1, "short": 2, "int16": 2, "ushort": 2, "uint16": 2,
                                     "int": 4, "int32": 4, "uint": 4, "uint32": 4, "float": 4, "float32": 4, "double": 8, "float64": 8]
        for q in sarlavha.split(separator: "\n") {
            let m = q.split(separator: " ").map(String.init)
            if m.count >= 2, m[0] == "format" { format = m[1] }
            if m.count == 3, m[0] == "element" { vertexIchida = m[1] == "vertex"; if vertexIchida { soni = Int(m[2]) ?? 0 } }
            if m.count == 3, m[0] == "property", vertexIchida {
                guard let o = olcham[m[1]] else { return nil }
                xossalar.append((m[2], m[1], qadam))
                qadam += o
            }
            if m.count == 5, m[0] == "comment", m[1] == "boshlangich" {
                bosh = Vektor3(Double(m[2]) ?? 0, Double(m[3]) ?? 0, Double(m[4]) ?? 0)
            }
        }
        guard format == "binary_little_endian", qadam > 0 else { return nil }
        func top(_ n: String) -> (tur: String, siljish: Int)? { xossalar.first { $0.nom == n }.map { ($0.tur, $0.siljish) } }
        guard let px = top("x"), let py = top("y"), let pz = top("z") else { return nil }
        let nx = top("nx"), ny = top("ny"), nz = top("nz")
        let rr = top("red"), gg = top("green"), bb = top("blue"), tt = top("t")
        let bayt = [UInt8](d[r.upperBound...])
        guard bayt.count >= soni * qadam else { return nil }
        func son(_ x: (tur: String, siljish: Int), _ o: Int) -> Double {
            let i = o + x.siljish
            func u32() -> UInt32 { UInt32(bayt[i]) | UInt32(bayt[i + 1]) << 8 | UInt32(bayt[i + 2]) << 16 | UInt32(bayt[i + 3]) << 24 }
            switch x.tur {
            case "float", "float32": return Double(Float(bitPattern: u32()))
            case "double", "float64":
                var v: UInt64 = 0
                for k in 0..<8 { v |= UInt64(bayt[i + k]) << (8 * UInt64(k)) }
                return Double(bitPattern: v)
            case "uchar", "uint8": return Double(bayt[i])
            case "char", "int8": return Double(Int8(bitPattern: bayt[i]))
            case "ushort", "uint16": return Double(UInt16(bayt[i]) | UInt16(bayt[i + 1]) << 8)
            case "short", "int16": return Double(Int16(bitPattern: UInt16(bayt[i]) | UInt16(bayt[i + 1]) << 8))
            case "uint", "uint32": return Double(u32())
            default: return Double(Int32(bitPattern: u32()))
            }
        }
        var natija: [BulutNuqtasi] = []
        natija.reserveCapacity(soni)
        for k in 0..<soni {
            let o = k * qadam
            var b = BulutNuqtasi(Vektor3(son(px, o), son(py, o), son(pz, o)) + bosh)
            if let nx, let ny, let nz { b.n = Vektor3(son(nx, o), son(ny, o), son(nz, o)) }
            if let rr, let gg, let bb {
                b.rang = Rang(UInt8(clamping: Int(son(rr, o))), UInt8(clamping: Int(son(gg, o))), UInt8(clamping: Int(son(bb, o))))
            }
            if let tt { b.t = son(tt, o) }
            natija.append(b)
        }
        return (natija, bosh)
    }
}
