import Foundation

/// UTM koordinatasi (metr). Jizzax — 42N zona.
public struct UTMNuqta: Equatable {
    public let zona: Int
    public let shimoliy: Bool
    public let x: Double   // easting
    public let y: Double   // northing
    public init(zona: Int, shimoliy: Bool, x: Double, y: Double) {
        self.zona = zona; self.shimoliy = shimoliy; self.x = x; self.y = y
    }
}

/// WGS84 ↔ UTM — Krüger qatorlari (mm aniqlik).
public enum UTM {
    static let a = 6378137.0
    static let f = 1.0 / 298.257223563
    static let k0 = 0.9996
    static let e0 = 500_000.0
    static let n = f / (2 - f)
    static let A = a / (1 + n) * (1 + n * n / 4 + n * n * n * n / 64)
    static let alfa = [n / 2 - 2 * n * n / 3 + 5 * n * n * n / 16,
                       13 * n * n / 48 - 3 * n * n * n / 5,
                       61 * n * n * n / 240]
    static let beta = [n / 2 - 2 * n * n / 3 + 37 * n * n * n / 96,
                       n * n / 48 + n * n * n / 15,
                       17 * n * n * n / 480]
    static let delta = [2 * n - 2 * n * n / 3 - 2 * n * n * n,
                        7 * n * n / 3 - 8 * n * n * n / 5,
                        56 * n * n * n / 15]

    public static func zona(lon: Double) -> Int {
        Int(floor((lon + 180) / 6)) + 1
    }

    static func markaziyMeridian(_ zona: Int) -> Double {
        Double(zona - 1) * 6 - 180 + 3
    }

    public static func ga(lat: Double, lon: Double, zona berilganZona: Int? = nil) -> UTMNuqta {
        let z = berilganZona ?? zona(lon: lon)
        let fi = lat * .pi / 180
        let lam = (lon - markaziyMeridian(z)) * .pi / 180
        let sn = 2 * n.squareRoot() / (1 + n)
        let t = sinh(atanh(sin(fi)) - sn * atanh(sn * sin(fi)))
        let xi = atan2(t, cos(lam))
        let eta = atanh(sin(lam) / (1 + t * t).squareRoot())
        var e = eta, nn = xi
        for j in 1...3 {
            let d = Double(j)
            e += alfa[j - 1] * cos(2 * d * xi) * sinh(2 * d * eta)
            nn += alfa[j - 1] * sin(2 * d * xi) * cosh(2 * d * eta)
        }
        let shimoliy = lat >= 0
        return UTMNuqta(zona: z, shimoliy: shimoliy,
                        x: e0 + k0 * A * e,
                        y: (shimoliy ? 0 : 10_000_000) + k0 * A * nn)
    }

    public static func dan(_ p: UTMNuqta) -> (lat: Double, lon: Double) {
        let xi = (p.y - (p.shimoliy ? 0 : 10_000_000)) / (k0 * A)
        let eta = (p.x - e0) / (k0 * A)
        var xi1 = xi, eta1 = eta
        for j in 1...3 {
            let d = Double(j)
            xi1 -= beta[j - 1] * sin(2 * d * xi) * cosh(2 * d * eta)
            eta1 -= beta[j - 1] * cos(2 * d * xi) * sinh(2 * d * eta)
        }
        let chi = asin(sin(xi1) / cosh(eta1))
        var fi = chi
        for j in 1...3 {
            fi += delta[j - 1] * sin(2 * Double(j) * chi)
        }
        let lam = atan2(sinh(eta1), cos(xi1))
        return (fi * 180 / .pi, markaziyMeridian(p.zona) + lam * 180 / .pi)
    }

    /// Meridian egrilik radiusi — sinov va masofa hisoblari uchun.
    public static func meridianRadiusi(lat: Double) -> Double {
        let e2 = f * (2 - f)
        let s = sin(lat * .pi / 180)
        return a * (1 - e2) / pow(1 - e2 * s * s, 1.5)
    }
}
