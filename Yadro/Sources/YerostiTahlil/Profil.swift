import Foundation
import YerostiGeometriya

/// UI-17 / UI-21: bo'ylama profil — o'q bo'ylab gorizontal stansiya (m) va balandliklar (yuqori o'q bo'yicha).
/// ГОСТ Р 51872: ijro hujjatida quvur usti belgilari ko'rsatiladi. Stansiya 0 — o'qning yuqori (boshlanish) uchi.
public struct BoylamaProfil: Equatable, Sendable {
    /// [stansiya, quvur markazi balandligi] — o'q cho'qqilari bo'yicha.
    public var oq: [[Double]]
    /// [stansiya, yer sirti balandligi] — qoplama chuqurligi o'lchangan stansiyalar (skan bo'yicha taxmin).
    public var yer: [[Double]]
    public var radius: Double

    /// Saqlangan profildan (ilova hisobotida): interpolyatsiya yadroda bir joyda qolsin.
    public init(oq: [[Double]], yer: [[Double]], radius: Double) {
        self.oq = oq; self.yer = yer; self.radius = radius
    }

    public init(_ q: TopilganQuvur, yuqori: Vektor3 = Vektor3(0, 1, 0)) {
        let up = yuqori.birlik ?? Vektor3(0, 1, 0)
        let gor: (Vektor3) -> Vektor3 = { v in v - up * v.nuqta(up) }
        var s: [Double] = [0]
        for i in 1..<max(q.oq.count, 1) { s.append(s[i - 1] + gor(q.oq[i] - q.oq[i - 1]).uzunlik) }
        oq = zip(s, q.oq).map { [$0, $1.nuqta(up)] }
        radius = q.radius
        yer = q.chuqurlikStansiyalari.compactMap { st -> [Double]? in
            guard q.oq.count >= 2 else { return nil }
            var eng = (d: Double.infinity, s: 0.0)
            for i in 1..<q.oq.count {
                let a = q.oq[i - 1], ab = q.oq[i] - a
                let t = max(0, min(1, (st.nuqta - a).nuqta(ab) / max(ab.uzunlik2, 1e-12)))
                let d = (st.nuqta - (a + ab * t)).uzunlik
                if d < eng.d { eng = (d, s[i - 1] + t * (s[i] - s[i - 1])) }
            }
            return [eng.s, st.nuqta.nuqta(up) + q.radius + st.chuqurlikM]
        }
    }

    /// Stansiyadagi quvur usti balandligi (o'q bo'yicha chiziqli).
    public func quvurUsti(_ stansiya: Double) -> Double? {
        guard let a = oq.first, let b = oq.last else { return nil }
        if stansiya <= a[0] { return a[1] + radius }
        if stansiya >= b[0] { return b[1] + radius }
        for i in 1..<oq.count where oq[i][0] >= stansiya {
            let p = oq[i - 1], q = oq[i]
            let t = q[0] > p[0] ? (stansiya - p[0]) / (q[0] - p[0]) : 0
            return p[1] + (q[1] - p[1]) * t + radius
        }
        return nil
    }
}
