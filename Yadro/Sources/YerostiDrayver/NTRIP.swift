import Foundation
import YerostiGeometriya

/// NTRIP ulanish sozlamasi (D-04). Parol faqat qurilmada saqlanadi.
public struct NTRIPSozlama: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var mountpoint: String
    public var login: String
    public var parol: String
    /// 1 — NTRIP 1.0 (ICY), 2 — NTRIP 2.0 (HTTP/1.1)
    public var versiya: Int

    public init(host: String, port: Int = 2101, mountpoint: String, login: String = "", parol: String = "",
                versiya: Int = 2) {
        self.host = host; self.port = port; self.mountpoint = mountpoint
        self.login = login; self.parol = parol; self.versiya = versiya
    }
}

/// NTRIP so'rovlari (RTCM 10410.1).
public enum NTRIPSorov {
    public static let ilova = "NTRIP YEROSTI/1.0"

    static func basic(_ login: String, _ parol: String) -> String? {
        guard !login.isEmpty else { return nil }
        return "Basic " + Data("\(login):\(parol)".utf8).base64EncodedString()
    }

    /// Mountpointga ulanish so'rovi. v2 da GGA sarlavhada yuboriladi (VRS tarmoqlari uchun).
    public static func mountpoint(_ s: NTRIPSozlama, gga: String? = nil) -> Data {
        var q: [String]
        let yol = "/" + s.mountpoint
        if s.versiya >= 2 {
            q = ["GET \(yol) HTTP/1.1", "Host: \(s.host):\(s.port)", "Ntrip-Version: Ntrip/2.0",
                 "User-Agent: \(ilova)"]
            if let a = basic(s.login, s.parol) { q.append("Authorization: \(a)") }
            if let g = gga { q.append("Ntrip-GGA: \(g)") }
            q.append("Connection: close")
        } else {
            q = ["GET \(yol) HTTP/1.0", "User-Agent: \(ilova)", "Accept: */*"]
            if let a = basic(s.login, s.parol) { q.append("Authorization: \(a)") }
            q.append("Connection: close")
        }
        return Data((q.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    /// Manba jadvali (sourcetable) so'rovi — mountpointlar ro'yxati.
    public static func manbaJadvali(host: String, port: Int = 2101, versiya: Int = 2) -> Data {
        let q: [String] = versiya >= 2
            ? ["GET / HTTP/1.1", "Host: \(host):\(port)", "Ntrip-Version: Ntrip/2.0", "User-Agent: \(ilova)",
               "Connection: close"]
            : ["GET / HTTP/1.0", "User-Agent: \(ilova)", "Accept: */*", "Connection: close"]
        return Data((q.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }
}

/// Caster javobini bosqichma-bosqich tahlil qiluvchi (baytlar bo'lak-bo'lak keladi).
public final class NTRIPJavob {
    public enum Holat: Equatable {
        case sarlavhaKutilmoqda
        case oqim              // RTCM oqimi keladi
        case manbaJadvali      // sourcetable matni keladi
        case xato(String)
    }

    public private(set) var holat: Holat = .sarlavhaKutilmoqda
    public private(set) var holatKodi: Int?
    public private(set) var sarlavhalar: [String: String] = [:]
    public private(set) var manbaJadvaliMatni = ""
    public private(set) var manbaJadvaliTugadi = false
    /// v1 casterlar mountpoint topilmasa sourcetable qaytaradi — shuni belgilaymiz.
    public let mountpointSoralgan: Bool

    private var bufer = Data()
    private var chunked = false
    private var chunkQoldi = 0
    private var chunkHolati = 0  // 0: o'lcham satri, 1: ma'lumot, 2: ma'lumotdan keyingi CRLF, 3: tugadi
    private let sarlavhaChek = 16 * 1024

    public init(mountpointSoralgan: Bool = true) { self.mountpointSoralgan = mountpointSoralgan }

    /// Kelgan baytlarni beradi; RTCM oqimi bo'lsa — toza RTCM baytlarini qaytaradi.
    public func qabul(_ d: Data) -> Data {
        switch holat {
        case .xato:
            return Data()
        case .sarlavhaKutilmoqda:
            bufer.append(d)
            guard let chegara = sarlavhaOxiri() else {
                if bufer.count > sarlavhaChek { holat = .xato("sarlavha juda uzun") }
                return Data()
            }
            let sarlavhaQismi = bufer[bufer.startIndex..<chegara.lowerBound]
            let qolgan = Data(bufer[chegara.upperBound...])
            bufer.removeAll()
            sarlavhaniTahlil(String(decoding: sarlavhaQismi, as: UTF8.self))
            return qolgan.isEmpty ? Data() : qabul(qolgan)
        case .oqim:
            return chunked ? chunkdanAjrat(d) : d
        case .manbaJadvali:
            let toza = chunked ? chunkdanAjrat(d) : d
            manbaJadvaliMatni += String(decoding: toza, as: UTF8.self)
            if manbaJadvaliMatni.contains("ENDSOURCETABLE") { manbaJadvaliTugadi = true }
            return Data()
        }
    }

    private func sarlavhaOxiri() -> Range<Data.Index>? {
        // v1: "ICY 200 OK\r\n" (ba'zan bo'sh qatorsiz). Avval shuni tekshiramiz — aks holda RTCM
        // ikkilik oqimi ichidagi tasodifiy "\r\n\r\n" sarlavha oxiri deb olinardi.
        // VRS casterlar GGA kelmaguncha jim turadi — shuning uchun faqat shu 12 bayt bilan ham qabul qilamiz.
        if bufer.starts(with: Data("ICY 200 OK\r\n".utf8)) {
            let s = bufer.startIndex
            if bufer.count >= 14, bufer[s + 12] == 0x0D, bufer[s + 13] == 0x0A { return (s + 10)..<(s + 14) }
            return (s + 10)..<(s + 12)
        }
        if let r = bufer.range(of: Data("\r\n\r\n".utf8)) { return r }
        // Ba'zi eski casterlar "SOURCETABLE 200 OK\r\n" dan keyin darhol STR/CAS qatorlarini yuboradi
        if bufer.starts(with: Data("SOURCETABLE 200 OK\r\n".utf8)),
           bufer.range(of: Data("\r\nSTR;".utf8)) != nil || bufer.range(of: Data("\r\nCAS;".utf8)) != nil
            || bufer.range(of: Data("ENDSOURCETABLE".utf8)) != nil {
            let s = bufer.startIndex
            return (s + 18)..<(s + 20)
        }
        return nil
    }

    private func sarlavhaniTahlil(_ matn: String) {
        let qatorlar = matn.components(separatedBy: "\r\n")
        let birinchi = qatorlar.first ?? ""
        for q in qatorlar.dropFirst() {
            guard let i = q.firstIndex(of: ":") else { continue }
            let k = q[..<i].trimmingCharacters(in: .whitespaces).lowercased()
            let v = q[q.index(after: i)...].trimmingCharacters(in: .whitespaces)
            sarlavhalar[k] = v
        }
        chunked = sarlavhalar["transfer-encoding"]?.lowercased().contains("chunked") == true
        if birinchi.hasPrefix("ICY 200") {
            holatKodi = 200; holat = .oqim; return
        }
        if birinchi.hasPrefix("SOURCETABLE 200") {
            holatKodi = 200
            holat = mountpointSoralgan ? .xato("mountpoint topilmadi (caster manba jadvalini qaytardi)") : .manbaJadvali
            return
        }
        let bolak = birinchi.split(separator: " ")
        guard birinchi.hasPrefix("HTTP/"), bolak.count >= 2, let kod = Int(bolak[1]) else {
            holat = .xato("noma'lum javob: \(birinchi.prefix(60))"); return
        }
        holatKodi = kod
        switch kod {
        case 200:
            let tur = sarlavhalar["content-type"]?.lowercased() ?? ""
            if tur.contains("sourcetable") {
                holat = mountpointSoralgan ? .xato("mountpoint topilmadi (caster manba jadvalini qaytardi)") : .manbaJadvali
            } else {
                holat = .oqim
            }
        case 401: holat = .xato("login yoki parol noto'g'ri (401)")
        case 403: holat = .xato("ruxsat yo'q (403)")
        case 404: holat = .xato("mountpoint topilmadi (404)")
        default: holat = .xato("caster javobi \(kod)")
        }
    }

    private func chunkdanAjrat(_ d: Data) -> Data {
        bufer.append(d)
        var chiqish = Data()
        while !bufer.isEmpty {
            switch chunkHolati {
            case 0:
                guard let r = bufer.range(of: Data("\r\n".utf8)) else { return chiqish }
                let satr = String(decoding: bufer[bufer.startIndex..<r.lowerBound], as: UTF8.self)
                let hex = satr.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
                bufer.removeSubrange(bufer.startIndex..<r.upperBound)
                guard let n = Int(hex, radix: 16) else { holat = .xato("chunk o'lchami noto'g'ri"); return chiqish }
                if n == 0 { chunkHolati = 3; bufer.removeAll(); return chiqish }
                chunkQoldi = n; chunkHolati = 1
            case 1:
                let ol = min(chunkQoldi, bufer.count)
                chiqish.append(bufer[bufer.startIndex..<(bufer.startIndex + ol)])
                bufer.removeSubrange(bufer.startIndex..<(bufer.startIndex + ol))
                chunkQoldi -= ol
                if chunkQoldi == 0 { chunkHolati = 2 }
            case 2:
                guard bufer.count >= 2 else { return chiqish }
                bufer.removeSubrange(bufer.startIndex..<(bufer.startIndex + 2))
                chunkHolati = 0
            default:
                bufer.removeAll(); return chiqish
            }
        }
        return chiqish
    }
}

/// Manba jadvalidagi bitta mountpoint (STR qatori).
public struct Mountpoint: Equatable, Sendable {
    public let nomi: String
    public let identifikator: String
    public let format: String
    public let formatTafsilot: String
    public let navTizim: String
    public let tarmoq: String
    public let davlat: String
    public let lat: Double?
    public let lon: Double?
    /// Caster GGA talab qiladimi (VRS/tarmoq yechimi)
    public let ggaKerak: Bool
    /// 0 — yagona baza, 1 — tarmoq (VRS)
    public let tarmoqYechimi: Bool
    public let autentifikatsiya: String

    public func masofa(lat rLat: Double, lon rLon: Double) -> Double? {
        guard let a = lat, let b = lon else { return nil }
        return Geodeziya.masofa(lat1: a, lon1: b, lat2: rLat, lon2: rLon)
    }
}

public enum ManbaJadvali {
    public static func ajrat(_ matn: String) -> [Mountpoint] {
        var natija: [Mountpoint] = []
        for qator in matn.components(separatedBy: .newlines) where qator.hasPrefix("STR;") {
            let m = qator.components(separatedBy: ";")
            guard m.count >= 16, !m[1].isEmpty else { continue }
            natija.append(Mountpoint(
                nomi: m[1], identifikator: m[2], format: m[3], formatTafsilot: m[4], navTizim: m[6],
                tarmoq: m[7], davlat: m[8], lat: Double(m[9]), lon: Double(m[10]),
                ggaKerak: m[11] == "1", tarmoqYechimi: m[12] == "1", autentifikatsiya: m[15]))
        }
        return natija
    }

    /// Roverga eng yaqin RTCM3 mountpointlar (masofa bo'yicha, km).
    public static func engYaqin(_ royxat: [Mountpoint], lat: Double, lon: Double, soni: Int = 5)
        -> [(mountpoint: Mountpoint, masofaKm: Double)] {
        royxat.filter { $0.format.uppercased().hasPrefix("RTCM 3") || $0.format.uppercased().hasPrefix("RTCM3") }
            .compactMap { m in m.masofa(lat: lat, lon: lon).map { (m, $0 / 1000) } }
            .sorted { $0.1 < $1.1 }
            .prefix(soni).map { (mountpoint: $0.0, masofaKm: $0.1) }
    }
}
