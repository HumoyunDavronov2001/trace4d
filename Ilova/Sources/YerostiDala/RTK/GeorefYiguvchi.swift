import ARKit
import Foundation
import YerostiDrayver
import YerostiGeometriya
import YerostiTahlil

/// RTK epoxalari ↔ antenna pozasi (ARKit) juftlari → gravitatsiyali georeferens.
/// Skan va AR ko'rish uchun umumiy (yadrodagi `Georeferens.gravitatsiyaBilan` — sinalgan).
@MainActor
final class GeorefYiguvchi {
    private(set) var mahalliy: [Vektor3] = []
    private(set) var global: [Vektor3] = []
    private(set) var zona: Int?
    private(set) var natija: GorizontalNatija?
    /// Oxirgi qabul qilingan juft — skan uni muhr jurnaliga yozadi (DM-02).
    private(set) var oxirgiJuft: JuftYozuvi?
    private var pozaTarixi: [(t: TimeInterval, T: simd_float4x4)] = []
    private let sozlama: Sozlamalar

    init(sozlama: Sozlamalar) { self.sozlama = sozlama }

    var juftSoni: Int { mahalliy.count }

    /// Gorizontal yoyilish (m): markazdan eng uzoq juft. Burilish aniqlanishi uchun ≥ 0,5 m kerak.
    var yoyilishM: Double {
        guard !mahalliy.isEmpty else { return 0 }
        let c = mahalliy.reduce(Vektor3.nol, +) / Double(mahalliy.count)
        return mahalliy.map { (($0.x - c.x) * ($0.x - c.x) + ($0.y - c.y) * ($0.y - c.y)).squareRoot() }.max() ?? 0
    }

    /// Eng katta qoldiq (gorizontal yoki vertikal RMS).
    var rmsM: Double? { natija.map { max($0.gorizontalRmsM, $0.vertikalRmsM) } }

    func poza(_ t: TimeInterval, _ T: simd_float4x4) {
        pozaTarixi.append((t, T))
        if pozaTarixi.count > 180 { pozaTarixi.removeFirst(pozaTarixi.count - 180) }
    }

    /// Yangi RTK epoxasi. Faqat RASMIY (FIX + σ + tuzatma yoshi, T-103) juftlar olinadi.
    @discardableResult
    func epoxa(_ h: QabulQilgichHolati, _ uptime: TimeInterval) -> Bool {
        guard h.sifat() == .rasmiy, let lat = h.lat, let lon = h.lon, let bal = h.balandlikEllipsoid,
              let T = pozaVaqtda(uptime - sozlama.rtkKechikishS) else { return false }
        let o = sozlama.antennaOfset.count == 3 ? sozlama.antennaOfset : [0, 0, 0]
        // portret (x o'ng, y yuqori, z foydalanuvchiga) → ARKit kamera ramkasi (x = −y, y = x, z = z)
        let a = T * SIMD4<Float>(Float(-o[1]), Float(o[0]), Float(o[2]), 1)
        let z = zona ?? UTM.zona(lon: lon)
        zona = z
        let g = UTM.ga(lat: lat, lon: lon, zona: z)
        let m = ARKitRamka.enu(Vektor3(Double(a.x), Double(a.y), Double(a.z)))
        let gl = Vektor3(g.x, g.y, bal)
        mahalliy.append(m)
        global.append(gl)
        // DS-03: juftlangan poza vaqti va epoxa kelgan vaqt ham yoziladi (server kechikishni qayta baholaydi)
        oxirgiJuft = JuftYozuvi(m: m, g: gl, zona: z, t: uptime - sozlama.rtkKechikishS, te: uptime)
        if mahalliy.count >= 20, mahalliy.count % 10 == 0 { hisobla() }
        return true
    }

    @discardableResult
    func hisobla() -> GorizontalNatija? {
        natija = try? Georeferens.gravitatsiyaBilan(mahalliyENU: mahalliy, global: global)
        return natija
    }

    private func pozaVaqtda(_ t: TimeInterval) -> simd_float4x4? {
        guard let k = pozaTarixi.lastIndex(where: { $0.t <= t }) else { return nil }
        guard k + 1 < pozaTarixi.count else { return pozaTarixi[k].T }
        let a = pozaTarixi[k], b = pozaTarixi[k + 1]
        let u = Float((t - a.t) / max(b.t - a.t, 1e-6))
        var T = a.T
        T.columns.3 = a.T.columns.3 + (b.T.columns.3 - a.T.columns.3) * u
        return T
    }
}
