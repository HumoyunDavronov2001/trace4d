import Foundation

/// WGS84 geodeziya: ECEF ↔ geodezik, ellipsoid ustidagi masofa.
public enum Geodeziya {
    public static let a = 6378137.0
    public static let f = 1.0 / 298.257223563
    public static var e2: Double { f * (2 - f) }

    /// Geodezik (daraja, metr) → ECEF (metr).
    public static func ecef(lat: Double, lon: Double, h: Double) -> Vektor3 {
        let fi = lat * .pi / 180, la = lon * .pi / 180
        let N = a / (1 - e2 * sin(fi) * sin(fi)).squareRoot()
        return Vektor3((N + h) * cos(fi) * cos(la), (N + h) * cos(fi) * sin(la), (N * (1 - e2) + h) * sin(fi))
    }

    /// ECEF → geodezik (Bowring + 3 iteratsiya; mm dan yaxshi).
    public static func geodezik(_ p: Vektor3) -> (lat: Double, lon: Double, h: Double) {
        let lon = atan2(p.y, p.x)
        let r = (p.x * p.x + p.y * p.y).squareRoot()
        var fi = atan2(p.z, r * (1 - e2))
        var h = 0.0
        for _ in 0..<6 {
            let N = a / (1 - e2 * sin(fi) * sin(fi)).squareRoot()
            h = r / cos(fi) - N
            fi = atan2(p.z, r * (1 - e2 * N / (N + h)))
        }
        return (fi * 180 / .pi, lon * 180 / .pi, h)
    }

    /// Ikki nuqta orasidagi to'g'ri chiziqli (ECEF) masofa — RTK baza-rover masofasi uchun yetarli.
    public static func masofa(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        (ecef(lat: lat1, lon: lon1, h: 0) - ecef(lat: lat2, lon: lon2, h: 0)).uzunlik
    }
}
