import Foundation
import YerostiGeometriya

/// FAQAT SINOV UCHUN (mahsulotga kirmaydi): transheya bo'ylab dastak bilan yurish.
/// Uch ramka: haqiqiy ARKit dunyosi W (suzishsiz), ARKit ko'rgan A (suzish bilan) va UTM.
/// RTK epoxalari GNSS vaqti, telefonga kelish vaqti (kechikish + tebranish) va shovqin bilan yasaladi.
public struct DalaSimulyatsiya: Sendable {
    public struct Sozlama: Sendable {
        public var davomiylikS = 80.0
        public var pozaHz = 60.0
        public var gnssHz = 5.0
        /// Telefonga kelishning doimiy kechikishi va unga qo'shiladigan tekis tebranish (0…tebranishS).
        public var kechikishS = 0.120
        public var tebranishS = 0.030
        /// uptime − GNSS sutka soniyasi.
        public var soatS = 5_000.0
        /// GNSS vaqti boshida (10:00:00 UTC).
        public var gnssBoshS = 36_000.0
        public var sigmaH = 0.008
        public var sigmaV = 0.012
        /// ARKit suzishi: uzunlik xatosi (0,01 = 1 %), 30 m dagi yaw og'ishi (grad), vertikal (m/m).
        public var suzishMasshtab = 0.0
        public var suzishYawGrad30m = 0.0
        public var suzishVertikal = 0.0
        /// Antenna ofseti, portret ramkasi (m).
        public var ofset = [0.072, 0.108, 0.028]
        /// Bir tekis yurish (tezlik o'zgarmaydi, burilish/tebranish yo'q) — kechikish kuzatilmaydigan holat.
        public var birTekis = false
        public var urug: UInt64 = 1
        public init() {}
    }

    public let s: Sozlama
    /// Haqiqiy ENU → UTM.
    public let utmT = GorizontalTransformatsiya(burchak: 0.6, t: Vektor3(401_336.53, 4_441_252.38, 402.0))
    public let iz: PozaIzi
    public let epoxalar: [RTKEpoxasi]
    public let t0: Double

    public init(_ s: Sozlama = .init()) {
        self.s = s
        t0 = s.gnssBoshS + s.soatS
        var namuna: [PozaNamuna] = []
        let n = Int(s.davomiylikS * s.pozaHz)
        for k in 0...n {
            let t = t0 + Double(k) / s.pozaHz
            namuna.append(DalaSimulyatsiya.arkit(s, t0, t))
        }
        iz = PozaIzi(namuna)
        var rnd = Tasodifiy(urug: s.urug)
        var e: [RTKEpoxasi] = []
        let m = Int(s.davomiylikS * s.gnssHz)
        for k in 0..<m {
            let utc = s.gnssBoshS + Double(k) / s.gnssHz
            let tau = utc + s.soatS
            let a = DalaSimulyatsiya.haqiqiy(s, t0, tau)
            let antenna = ARKitRamka.enu(a.dunyoga(Antenna.kamerada(s.ofset)))
            let g = utmT.qolla(antenna) + Vektor3(rnd.normal(sigma: s.sigmaH / 2.squareRoot()),
                                                  rnd.normal(sigma: s.sigmaH / 2.squareRoot()), rnd.normal(sigma: s.sigmaV))
            let te = tau + s.kechikishS + rnd.birlik() * s.tebranishS
            e.append(RTKEpoxasi(g: g, utcS: utc, te: te, rasmiy: true))
        }
        epoxalar = e
    }

    /// Yo'l (m) — sharqqa qarab, tezlik 0,1…0,7 m/s (to'xtab-yurish).
    static func yol(_ s: Sozlama, _ t: Double) -> Double {
        s.birTekis ? 0.4 * t : 0.4 * t + 0.3 * 7 / (2 * .pi) * (1 - cos(2 * .pi * t / 7))
    }

    /// Haqiqiy kamera pozasi W ramkada (ARKit o'qlari: y yuqori, kamera −z ga qaraydi).
    public static func haqiqiy(_ s: Sozlama, _ t0: Double, _ t: Double) -> PozaNamuna {
        let u = t - t0
        let x = yol(s, u)
        let enu = s.birTekis ? Vektor3(x, 0.2, 1.2) : Vektor3(x, 0.3 * sin(2 * .pi * u / 5), 1.2 + 0.1 * sin(2 * .pi * u / 3))
        let yaw = -Double.pi / 2 + (s.birTekis ? 0 : 0.17 * sin(2 * .pi * u / 6))
        let pitch = -0.6 + (s.birTekis ? 0 : 0.17 * sin(2 * .pi * u / 4.3))
        let roll = s.birTekis ? 0 : 0.09 * sin(2 * .pi * u / 3.7)
        let q = Kvaternion(oq: Vektor3(0, 1, 0), burchak: yaw) * Kvaternion(oq: Vektor3(1, 0, 0), burchak: pitch)
            * Kvaternion(oq: Vektor3(0, 0, 1), burchak: roll)
        return PozaNamuna(t: t, p: ARKitRamka.arkit(enu), q: q)
    }

    /// ARKit ko'rgan poza (suzish bilan): boshlang'ich nuqta atrofida masshtab, yaw va vertikal og'ish yo'l bilan o'sadi.
    public static func arkit(_ s: Sozlama, _ t0: Double, _ t: Double) -> PozaNamuna {
        let h = haqiqiy(s, t0, t), b = haqiqiy(s, t0, t0)
        let (dq, siljish) = suzish(s, t0, t)
        let p = b.p + dq.qolla(h.p - b.p) * (1 + s.suzishMasshtab) + siljish
        return PozaNamuna(t: t, p: p, q: dq * h.q)
    }

    static func suzish(_ s: Sozlama, _ t0: Double, _ t: Double) -> (Kvaternion, Vektor3) {
        let yo = yol(s, t - t0)
        let dpsi = s.suzishYawGrad30m * .pi / 180 * yo / 30
        return (Kvaternion(oq: Vektor3(0, 1, 0), burchak: dpsi), Vektor3(0, s.suzishVertikal * yo, 0))
    }

    /// W ramkadagi nuqta `t` vaqtda kuzatilganda ARKit A ramkada qayerda ko'rinadi (kamera atrofi qattiq bog'langan).
    public func kuzatilgan(_ qW: Vektor3, vaqt t: Double) -> Vektor3 {
        let h = DalaSimulyatsiya.haqiqiy(s, t0, t), a = DalaSimulyatsiya.arkit(s, t0, t)
        let (dq, _) = DalaSimulyatsiya.suzish(s, t0, t)
        return a.p + dq.qolla(qW - h.p)
    }

    /// W ramkadagi nuqtaning haqiqiy UTM i.
    public func utm(_ qW: Vektor3) -> Vektor3 { utmT.qolla(ARKitRamka.enu(qW)) }

    /// Kamera W da shu nuqtaga eng yaqin turgan vaqt (nuqta shu paytda kuzatilgan deb olinadi).
    public func engYaqinVaqt(_ qW: Vektor3) -> Double {
        var eng = (t: t0, d: Double.infinity)
        for k in stride(from: 0, through: Int(s.davomiylikS * 20), by: 1) {
            let t = t0 + Double(k) / 20
            let d = (DalaSimulyatsiya.haqiqiy(s, t0, t).p - qW).uzunlik
            if d < eng.d { eng = (t, d) }
        }
        return eng.t
    }
}
