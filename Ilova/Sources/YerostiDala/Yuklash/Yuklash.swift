import Foundation
import Observation
import UIKit
import YerostiDrayver
import YerostiGeometriya
import YerostiMuhr
import YerostiTahlil

/// YEROSTI serveri bilan aloqa (API v1, Bearer `YRD.` dala tokeni).
struct ServerMijoz {
    let asos: URL
    let token: String

    struct Xato: LocalizedError { let matn: String; var errorDescription: String? { matn } }

    init(manzil: String, token: String) throws {
        guard let u = URL(string: manzil.trimmingCharacters(in: .whitespaces)), u.scheme != nil, !token.isEmpty else {
            throw Xato(matn: "Sozlamalarda server manzili va dala tokenini kiriting")
        }
        asos = u; self.token = token
    }

    @discardableResult
    func sorov(_ yol: String, metod: String = "GET", json: [String: Any]? = nil, xom: Data? = nil,
               sarlavhalar: [String: String] = [:]) async throws -> [String: Any] {
        var r = URLRequest(url: asos.appendingPathComponent(yol))
        r.httpMethod = metod
        r.timeoutInterval = 60
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (k, v) in sarlavhalar { r.setValue(v, forHTTPHeaderField: k) }
        if let json {
            r.httpBody = try JSONSerialization.data(withJSONObject: json)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let xom {
            r.httpBody = xom
            r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        let (d, javob) = try await URLSession.shared.data(for: r)
        let kod = (javob as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        guard (200..<300).contains(kod) else { throw Xato(matn: (obj["xato"] as? String) ?? "server javobi \(kod)") }
        return obj
    }

    /// AR-02: atrofdagi barcha kiritilgan tarmoqlar (hamma pudratchilardan).
    func atrof(lat: Double, lon: Double, r: Double) async throws -> [GlobalTarmoq] {
        guard var k = URLComponents(url: asos.appendingPathComponent("api/v1/atrof"), resolvingAgainstBaseURL: false) else {
            throw Xato(matn: "server manzili noto'g'ri")
        }
        k.queryItems = [URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lon", value: String(lon)),
                        URLQueryItem(name: "r", value: String(r))]
        guard let url = k.url else { throw Xato(matn: "server manzili noto'g'ri") }
        var q = URLRequest(url: url)
        q.timeoutInterval = 20
        q.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (d, javob) = try await URLSession.shared.data(for: q)
        guard (javob as? HTTPURLResponse)?.statusCode == 200 else { throw Xato(matn: "atrof: server javobi xato") }
        struct Javob: Decodable { let tarmoqlar: [GlobalTarmoq] }
        return try JSONDecoder().decode(Javob.self, from: d).tarmoqlar
    }

    /// LK-10: obyektning geodezik asosi (punktlar va serverdagi o'lchovlar, masalan Emlid Flow importi).
    func geodezikAsos(obyektId: Int) async throws -> (punktlar: [NazoratPunkt], olchovlar: [NazoratOlchov]) {
        let j = try await sorov("api/v1/obyekt/\(obyektId)/geodezik-asos")
        let punktlar: [NazoratPunkt] = ((j["punktlar"] as? [[String: Any]]) ?? []).compactMap { p in
            guard let nomi = p["nomi"] as? String else { return nil }
            return NazoratPunkt(nomi: nomi, x: p["x"] as? Double, y: p["y"] as? Double, h: p["h"] as? Double,
                                sinf: (p["sinf"] as? String) ?? "")
        }
        let iso = ISO8601DateFormatter()
        let olchovlar: [NazoratOlchov] = ((j["olchovlar"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let nomi = o["punkt_nomi"] as? String, let lat = o["lat"] as? Double, let lon = o["lon"] as? Double else {
                return nil
            }
            let vaqt = (o["vaqt"] as? String).flatMap { iso.date(from: $0) } ?? Date()
            return NazoratOlchov(punktNomi: nomi, maqsad: (o["maqsad"] as? String) ?? "kalibrlash", lat: lat, lon: lon,
                                 h: o["h"] as? Double, sigmaHSm: (o["sigma_h_sm"] as? Double) ?? 0,
                                 sigmaVSm: (o["sigma_v_sm"] as? Double) ?? 0, epoxalar: (o["epoxalar"] as? Int) ?? 0,
                                 davomiylikS: (o["davomiylik_s"] as? Double) ?? 0, antennaM: (o["antenna_m"] as? Double) ?? 0,
                                 vaqt: vaqt, serverId: o["id"] as? Int)
        }
        return (punktlar, olchovlar)
    }

    /// LK-02: bitta o'lchovni serverga yuborish; server id sini qaytaradi.
    func nazoratOlchovYubor(obyektId: Int, _ o: NazoratOlchov) async throws -> Int {
        var json: [String: Any] = ["punkt": o.punktNomi, "maqsad": o.maqsad, "lat": o.lat, "lon": o.lon, "rtk_holat": "FIX",
                                   "sigma_h_sm": o.sigmaHSm, "sigma_v_sm": o.sigmaVSm, "epoxalar": o.epoxalar,
                                   "davomiylik_s": o.davomiylikS, "antenna_m": o.antennaM,
                                   "vaqt": ISO8601DateFormatter().string(from: o.vaqt)]
        if let h = o.h { json["h"] = h }
        let j = try await sorov("api/v1/obyekt/\(obyektId)/nazorat-olchov", metod: "POST", json: json)
        guard let id = (j["idlar"] as? [Int])?.first else { throw Xato(matn: (j["xatolar"] as? [String])?.first ?? "server javobi noto'g'ri") }
        return id
    }

    /// TQ-01 (T-031): bitta quvur tasdig'ini serverga yuborish; server id sini qaytaradi.
    func tasdiqYubor(obyektId: Int, _ t: QuvurTasdigi) async throws -> Int {
        var json: [String: Any] = ["nomi": t.nomi, "lat": t.lat, "lon": t.lon, "rtk_holat": "FIX", "sigma_h_sm": t.sigmaHSm,
                                   "sigma_v_sm": t.sigmaVSm, "epoxalar": t.epoxalar, "davomiylik_s": t.davomiylikS,
                                   "antenna_m": t.antennaM, "joy": t.joy, "vaqt": ISO8601DateFormatter().string(from: t.vaqt)]
        if let h = t.h { json["h"] = h }
        let j = try await sorov("api/v1/obyekt/\(obyektId)/tasdiq", metod: "POST", json: json)
        guard let id = (j["idlar"] as? [Int])?.first else { throw Xato(matn: (j["xatolar"] as? [String])?.first ?? "server javobi noto'g'ri") }
        return id
    }

    /// Bo'lakli yuklash: har bo'lak sha256 bilan, server yakunda butun faylni tekshiradi.
    func faylYukla(obyektId: Int, turi: String, url: URL, jarayon: (Double) -> Void) async throws -> (sha: String, hajm: Int) {
        let d = try Data(contentsOf: url, options: .mappedIfSafe)
        let sha = Xesh.hex(d)
        let b = try await sorov("api/v1/skan/boshla", metod: "POST",
                                json: ["obyekt_id": obyektId, "turi": turi, "hajmi": d.count, "sha256": sha])
        guard let sid = b["skan_id"] as? Int, let bh = b["bolak_hajmi"] as? Int, let n = b["bolak_soni"] as? Int else {
            throw Xato(matn: "server skan javobi noto'g'ri")
        }
        for i in 0..<n {
            let bolak = d.subdata(in: (i * bh)..<min(d.count, (i + 1) * bh))
            try await sorov("api/v1/skan/\(sid)/bolak/\(i)", metod: "PUT", xom: bolak,
                            sarlavhalar: ["X-Bolak-SHA256": Xesh.hex(bolak)])
            jarayon(Double(i + 1) / Double(n))
        }
        let y = try await sorov("api/v1/skan/\(sid)/yakunla", metod: "POST")
        guard (y["holat"] as? String) == "tayyor" else { throw Xato(matn: (y["xato"] as? String) ?? "fayl tekshiruvdan o'tmadi") }
        return (sha, d.count)
    }
}

/// Skanni serverga topshirish: obyekt → fayllar → liniyalar (manba: skan) → imzolangan muhr (K-05).
@MainActor @Observable
final class Yuklovchi {
    private(set) var ishlayapti = false
    private(set) var bosqich = ""
    private(set) var jarayon = 0.0

    func yukla(loyihaId: UUID, skanId: UUID, ombor: LoyihaOmbori, sozlama: Sozlamalar) async {
        guard !ishlayapti, var loyiha = ombor.loyiha(loyihaId), var skan = loyiha.skanlar.first(where: { $0.id == skanId }) else { return }
        ishlayapti = true
        defer { ishlayapti = false; bosqich = ""; jarayon = 0 }
        do {
            let m = try ServerMijoz(manzil: sozlama.serverManzil, token: sozlama.dalaToken)
            bosqich = "Qurilma kaliti"
            let kalitBelgi = "kalit:" + m.asos.absoluteString + ":" + String(sozlama.dalaToken.suffix(8))
            if !UserDefaults.standard.bool(forKey: kalitBelgi) {
                try await m.sorov("api/v1/qurilma-kalit", metod: "POST",
                                  json: ["ochiq_kalit": try QurilmaKaliti.ochiqKalit().base64EncodedString()])
                UserDefaults.standard.set(true, forKey: kalitBelgi)
            }
            bosqich = "Obyekt"
            let oid: Int
            if let s = loyiha.serverId {
                oid = s
            } else {
                let j = try await m.sorov("api/v1/obyektlar", metod: "POST", json: [
                    "nomi": loyiha.nomi, "manzil": loyiha.manzil, "buyurtmachi": loyiha.buyurtmachi,
                    "pudratchi": loyiha.pudratchi, "order_raqami": loyiha.orderRaqami,
                    "order_sana": loyiha.orderSana ?? ""])
                guard let id = j["id"] as? Int else { throw ServerMijoz.Xato(matn: "obyekt yaratilmadi") }
                oid = id
                loyiha.serverId = id
                ombor.yangila(loyiha)
            }
            let papka = Papkalar.hujjatlar.appendingPathComponent(skan.papka, isDirectory: true)
            bosqich = "Muhr jurnali"
            let jurnal = try await m.faylYukla(obyektId: oid, turi: "muhr_jurnal", url: papka.appendingPathComponent("jurnal.ymj")) { p in Task { @MainActor in self.jarayon = p } }
            // DS-06: zich rangli bulut bo'lsa — u (quvur shundan topilgan), aks holda mesh
            let plyNomi = skan.xom?.plyNomi ?? "mesh.ply"
            bosqich = plyNomi == "zich.ply" ? "Zich bulut" : "3D mesh"
            let ply = try await m.faylYukla(obyektId: oid, turi: "nuqta_ply", url: papka.appendingPathComponent(plyNomi)) { p in Task { @MainActor in self.jarayon = p } }

            // ShN-05: yopiq ishlar dalolatnomasi uchun kalit kadrlardan 12 tagachasi. Har rasm xeshi muhr jurnalidagi kadr
            // yozuvida bor — server rasmni shu bilan «muhrlangan» deb tan oladi (manifestga qo'shish shart emas).
            let rasmlar = KalitKadrlar.tanla(papka: papka, maks: 12)
            for (i, u) in rasmlar.enumerated() {
                bosqich = "Rasm \(i + 1) / \(rasmlar.count)"
                _ = try await m.faylYukla(obyektId: oid, turi: "foto", url: u) { p in Task { @MainActor in self.jarayon = p } }
            }

            if let x = skan.xom, !x.quvurlar.isEmpty {
                // DS-05: bo'lakli georeferens — har nuqta o'z vaqtidagi transformatsiya bilan; PAST bo'lak σ = 10 sm
                bosqich = "Quvur o'qlari"
                for q in x.quvurlar {
                    let nuqtalar: [[String: Any]] = q.wgs84.indices.map { k in
                        var n: [String: Any] = ["lat": q.wgs84[k][0], "lon": q.wgs84[k][1], "balandlik": q.wgs84[k][2], "rtk_holat": "FIX",
                                                "sigma_h_sm": q.sigmaHSm[k], "sigma_v_sm": q.sigmaVSm[k], "tuzatma_yoshi_s": 0, "manba": "skan"]
                        if let c = q.chuqurlikM { n["chuqurlik_m"] = c }
                        return n
                    }
                    let past = q.past.filter { $0 }.count
                    try await m.sorov("api/v1/liniyalar", metod: "POST", json: [
                        "obyekt_id": oid, "turi": loyiha.tarmoqTuri, "material": loyiha.material,
                        "diametr_mm": Int((q.standartMm ?? q.tashqiDiametrMm).rounded()),
                        "izoh": "Skandan avtomatik (ishonch \(Int(q.ishonch * 100)) %, bo'lakli georeferens"
                            + (past > 0 ? ", \(past) nuqta PAST bo'lakda" : "") + ")", "nuqtalar": nuqtalar])
                }
            } else if let g = skan.georef {
                bosqich = "Quvur o'qlari"
                let T = GorizontalTransformatsiya(burchak: g.burchak, t: Vektor3(g.t[0], g.t[1], g.t[2]))
                // skan nuqtalari: georeferens xatosi + LiDAR shovqini (~1 sm) — T-031: RASMIY emas, SKAN
                let sh = (pow(g.gorizontalRmsM * 100, 2) + 1).squareRoot()
                let sv = (pow(g.vertikalRmsM * 100, 2) + 2.25).squareRoot()
                for q in skan.quvurlar {
                    let nuqtalar: [[String: Any]] = q.oqMahalliy.map { p in
                        let u = T.qolla(ARKitRamka.enu(Vektor3(p[0], p[1], p[2])))
                        let (lat, lon) = UTM.dan(UTMNuqta(zona: g.utmZona, shimoliy: true, x: u.x, y: u.y))
                        var n: [String: Any] = ["lat": lat, "lon": lon, "balandlik": u.z, "rtk_holat": "FIX",
                                                "sigma_h_sm": sh, "sigma_v_sm": sv, "tuzatma_yoshi_s": 0, "manba": "skan"]
                        if let c = q.chuqurlikM { n["chuqurlik_m"] = c }
                        return n
                    }
                    try await m.sorov("api/v1/liniyalar", metod: "POST", json: [
                        "obyekt_id": oid, "turi": loyiha.tarmoqTuri, "material": loyiha.material,
                        "diametr_mm": Int((q.standartMm ?? q.tashqiDiametrMm).rounded()),
                        "izoh": "Skandan avtomatik (ishonch \(Int(q.ishonch * 100)) %)", "nuqtalar": nuqtalar])
                }
            }

            // T-031: telefonda saqlangan quvur tasdiqlari — liniyalardan keyin, server ularni skan o'qiga bog'laydi
            if let l2 = ombor.loyiha(loyihaId) {
                let kutayotgan = l2.tasdiqlar.filter { $0.serverId == nil }
                if !kutayotgan.isEmpty {
                    bosqich = "Quvur tasdiqlari"
                    for var t in kutayotgan {
                        t.serverId = try await m.tasdiqYubor(obyektId: oid, t)
                        ombor.tasdiqSaqla(t, loyihaId: loyihaId)
                    }
                }
            }

            bosqich = "Muhr imzosi"
            let iso = ISO8601DateFormatter()
            let manifest = MuhrManifest(
                obyektId: oid, qurilma: "\(UIDevice.current.model) \(Qurilma.model)", boshlandi: iso.string(from: skan.boshlandi),
                tugadi: iso.string(from: skan.tugadi), yozuvSoni: skan.yozuvSoni, zanjirBoshi: skan.zanjirBoshi,
                fayllar: [.init(nomi: "jurnal.ymj", sha256: jurnal.sha, hajm: jurnal.hajm),
                          .init(nomi: plyNomi, sha256: ply.sha, hajm: ply.hajm)])
            let baytlar = try manifest.kanonik()
            let imzo = try QurilmaKaliti.imzola(baytlar)
            let natija = try await m.sorov("api/v1/muhr", metod: "POST", json: [
                "obyekt_id": oid, "manifest": baytlar.base64EncodedString(), "imzo": imzo.base64EncodedString()])
            let holat = natija["holat"] as? String ?? "?"
            skan.yuklash = .yuklandi(muhrHolati: holat + ((natija["sabab"] as? String).map { $0.isEmpty ? "" : " — \($0)" } ?? ""))
        } catch {
            skan.yuklash = .xato(error.localizedDescription)
        }
        ombor.skanYangila(skan, loyihaId: loyihaId)
    }
}

/// ShN-05: dalolatnoma uchun kalit kadrlar — `kadrlar.jsonl` dan JPEG xeshi yozilganlari; RASMIY (RTK FIX) kadrlar ustun,
/// skan bo'ylab teng oraliqda tanlanadi (bir joydan 12 ta rasm emas).
enum KalitKadrlar {
    private struct Qator: Decodable { let i: Int; let fayl: String; let jpeg: String?; let sifat: String }

    static func tanla(papka: URL, maks: Int) -> [URL] {
        guard let matn = try? String(contentsOf: papka.appendingPathComponent("kadrlar.jsonl"), encoding: .utf8) else { return [] }
        let dek = JSONDecoder()
        let hammasi: [Qator] = matn.split(separator: "\n").compactMap { try? dek.decode(Qator.self, from: Data($0.utf8)) }
            .filter { $0.jpeg != nil && FileManager.default.fileExists(atPath: papka.appendingPathComponent("kadrlar/\($0.fayl)").path) }
        let rasmiy = hammasi.filter { $0.sifat == "RASMIY" }
        let hovuz = rasmiy.count >= maks ? rasmiy : hammasi
        guard !hovuz.isEmpty else { return [] }
        let n = min(maks, hovuz.count)
        let tanlangan = (0..<n).map { k in hovuz[n == 1 ? 0 : k * (hovuz.count - 1) / (n - 1)] }
        return tanlangan.map { papka.appendingPathComponent("kadrlar/\($0.fayl)") }
    }
}
