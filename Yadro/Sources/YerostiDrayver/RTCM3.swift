import Foundation
import YerostiGeometriya

/// RTCM 3 ramkasi: 0xD3 | 6 bit zaxira + 10 bit uzunlik | payload | CRC-24Q.
public struct RTCM3Ramka: Equatable, Sendable {
    public let xabarRaqami: Int
    public let payload: [UInt8]
}

public enum RTCM3 {
    /// CRC-24Q (polinom 0x1864CFB) — RTCM 10403 standarti.
    public static func crc24q<S: Sequence>(_ baytlar: S) -> UInt32 where S.Element == UInt8 {
        var crc: UInt32 = 0
        for b in baytlar {
            crc ^= UInt32(b) << 16
            for _ in 0..<8 {
                crc <<= 1
                if crc & 0x1000000 != 0 { crc ^= 0x1864CFB }
            }
        }
        return crc & 0xFFFFFF
    }

    /// Payloaddan ramka yasash (sinov va qayta uzatish uchun).
    public static func ramka(_ payload: [UInt8]) -> [UInt8] {
        precondition(payload.count < 1024)
        var r: [UInt8] = [0xD3, UInt8((payload.count >> 8) & 0x03), UInt8(payload.count & 0xFF)] + payload
        let c = crc24q(r)
        r += [UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF)]
        return r
    }

    /// 1005/1006 — baza stansiyasi antenna nuqtasi (ARP) ECEF koordinatasi.
    public static func bazaStansiya(_ r: RTCM3Ramka) -> BazaStansiya? {
        guard r.xabarRaqami == 1005 || r.xabarRaqami == 1006 else { return nil }
        var o = BitOqim(r.payload)
        guard let raqam = o.u(12), raqam == r.xabarRaqami,
              let stansiya = o.u(12), o.otkaz(6), o.otkaz(4),
              let x = o.s(38), o.otkaz(2), let y = o.s(38), o.otkaz(2), let z = o.s(38) else { return nil }
        var balandlik: Double?
        if r.xabarRaqami == 1006 {
            guard let h = o.u(16) else { return nil }
            balandlik = Double(h) * 1e-4
        }
        let ecef = Vektor3(Double(x) * 1e-4, Double(y) * 1e-4, Double(z) * 1e-4)
        let g = Geodeziya.geodezik(ecef)
        return BazaStansiya(stansiyaID: Int(stansiya), ecef: ecef, antennaBalandligiM: balandlik,
                            lat: g.lat, lon: g.lon, h: g.h)
    }
}

public struct BazaStansiya: Equatable, Sendable {
    public let stansiyaID: Int
    public let ecef: Vektor3
    public let antennaBalandligiM: Double?
    public let lat: Double
    public let lon: Double
    public let h: Double

    public func masofaM(lat rLat: Double, lon rLon: Double, h rH: Double = 0) -> Double {
        (ecef - Geodeziya.ecef(lat: rLat, lon: rLon, h: rH)).uzunlik
    }
}

/// Katta-endian bit o'qigich.
struct BitOqim {
    let b: [UInt8]
    var pos = 0
    init(_ b: [UInt8]) { self.b = b }

    mutating func u(_ n: Int) -> UInt64? {
        guard n <= 64, pos + n <= b.count * 8 else { return nil }
        var v: UInt64 = 0
        for _ in 0..<n {
            let bit = (b[pos >> 3] >> (7 - UInt8(pos & 7))) & 1
            v = (v << 1) | UInt64(bit)
            pos += 1
        }
        return v
    }

    mutating func s(_ n: Int) -> Int64? {
        guard let v = u(n) else { return nil }
        if v & (1 << UInt64(n - 1)) != 0 { return Int64(bitPattern: v | ~((1 << UInt64(n)) - 1)) }
        return Int64(v)
    }

    mutating func otkaz(_ n: Int) -> Bool {
        guard pos + n <= b.count * 8 else { return false }
        pos += n; return true
    }
}

/// Oqimdan RTCM3 ramkalarini ajratuvchi: bo'laklarga bo'lingan va axlatli oqimga chidamli.
public final class RTCM3Ajratuvchi {
    private var bufer: [UInt8] = []
    public private(set) var crcXatolari = 0
    public private(set) var jamiRamka = 0
    /// Ramkaga kirmagan (axlat yoki soxta sinxron) baytlar.
    public private(set) var tashlanganBaytlar = 0

    public init() {}

    private enum Nomzod { case yaroqli(Int), toliqEmas, yaroqsiz }

    /// i dagi 0xD3 dan boshlanadigan ramkani baholash. Zaxira 6 bit nol bo'lishi shart.
    private func nomzod(_ i: Int) -> Nomzod {
        guard bufer[i] == 0xD3 else { return .yaroqsiz }
        guard i + 3 <= bufer.count else { return .toliqEmas }
        guard bufer[i + 1] & 0xFC == 0 else { return .yaroqsiz }
        let uz = (Int(bufer[i + 1] & 0x03) << 8) | Int(bufer[i + 2])
        guard uz >= 2 else { return .yaroqsiz }
        guard i + 6 + uz <= bufer.count else { return .toliqEmas }
        let hisob = RTCM3.crc24q(bufer[i..<(i + 3 + uz)])
        let berilgan = (UInt32(bufer[i + 3 + uz]) << 16) | (UInt32(bufer[i + 4 + uz]) << 8) | UInt32(bufer[i + 5 + uz])
        return hisob == berilgan ? .yaroqli(uz) : .yaroqsiz
    }

    public func qabul<S: Sequence>(_ d: S) -> [RTCM3Ramka] where S.Element == UInt8 {
        bufer.append(contentsOf: d)
        var natija: [RTCM3Ramka] = []
        var i = 0
        tsikl: while i < bufer.count {
            switch nomzod(i) {
            case .yaroqli(let uz):
                let payload = Array(bufer[(i + 3)..<(i + 3 + uz)])
                natija.append(RTCM3Ramka(xabarRaqami: (Int(payload[0]) << 4) | Int(payload[1] >> 4), payload: payload))
                jamiRamka += 1
                i += 6 + uz
            case .yaroqsiz:
                if bufer[i] == 0xD3, i + 3 <= bufer.count, bufer[i + 1] & 0xFC == 0 { crcXatolari += 1 }
                tashlanganBaytlar += 1
                i += 1
            case .toliqEmas:
                // Soxta 0xD3 uzun "uzunlik" bilan oqimni to'sib qo'ymasin: undan keyin to'liq va CRC dan
                // o'tgan ramka bo'lsa, bu nomzod soxta (tasodifiy moslik ehtimoli ~2⁻²⁴).
                var j = i + 1
                while j < bufer.count {
                    if bufer[j] == 0xD3, case .yaroqli = nomzod(j) {
                        tashlanganBaytlar += j - i
                        i = j
                        continue tsikl
                    }
                    j += 1
                }
                break tsikl
            }
        }
        bufer.removeFirst(min(i, bufer.count))
        if bufer.count > 4096 { tashlanganBaytlar += bufer.count - 1024; bufer.removeFirst(bufer.count - 1024) }
        return natija
    }
}

/// Tuzatma oqimi holati — ekranda "NTRIP 1 s", baza masofasi, xabar turlari (K-06, T-057).
public final class TuzatmaKuzatuvchi {
    public private(set) var xabarSoni: [Int: Int] = [:]
    public private(set) var oxirgiVaqt: Date?
    public private(set) var baza: BazaStansiya?
    public private(set) var baytlar = 0
    public static let bazaMasofaOgohKm = 20.0

    public init() {}

    public func qabul(_ ramkalar: [RTCM3Ramka], baytSoni: Int, vaqt: Date = Date()) {
        baytlar += baytSoni
        for r in ramkalar {
            xabarSoni[r.xabarRaqami, default: 0] += 1
            if let b = RTCM3.bazaStansiya(r) { baza = b }
        }
        if !ramkalar.isEmpty { oxirgiVaqt = vaqt }
    }

    public func yoshiS(hozir: Date = Date()) -> Double? { oxirgiVaqt.map { hozir.timeIntervalSince($0) } }

    public func bazaMasofasiKm(lat: Double, lon: Double, h: Double = 0) -> Double? {
        baza.map { $0.masofaM(lat: lat, lon: lon, h: h) / 1000 }
    }

    /// Qaysi GNSS tizimlari kelmoqda (MSM xabarlari bo'yicha).
    public var tizimlar: [String] {
        var t: [String] = []
        let r = Set(xabarSoni.keys)
        if !r.isDisjoint(with: 1071...1077) { t.append("GPS") }
        if !r.isDisjoint(with: 1081...1087) { t.append("GLONASS") }
        if !r.isDisjoint(with: 1091...1097) { t.append("Galileo") }
        if !r.isDisjoint(with: 1121...1127) { t.append("BeiDou") }
        return t
    }
}
