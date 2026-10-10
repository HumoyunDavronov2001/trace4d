import ARKit
import CoreVideo
import Foundation
import YerostiGeometriya
import YerostiTahlil

/// DS-06/07: ARFrame → yadro `ChuqurlikKadri` (chuqurlik, ishonch, har piksel uchun kamera tasviridan rang).
/// Asosiy oqimda chaqiriladi va faqat nusxa oladi (≈ 1 ms): ARKit bufer(lar)ini ushlab qolish kadrlar oqimini to'xtatadi.
enum ChuqurlikOlish {
    static func kadr(_ f: ARFrame) -> (kadr: ChuqurlikKadri, sha256: String)? {
        guard let sd = f.sceneDepth else { return nil }
        let dm = sd.depthMap
        guard CVPixelBufferGetPixelFormatType(dm) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(dm, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dm, .readOnly) }
        let en = CVPixelBufferGetWidth(dm), boy = CVPixelBufferGetHeight(dm), qator = CVPixelBufferGetBytesPerRow(dm)
        guard en > 2, boy > 2, let b = CVPixelBufferGetBaseAddress(dm) else { return nil }
        var d = [Float](repeating: 0, count: en * boy)
        for v in 0..<boy {
            let r = b.advanced(by: v * qator).assumingMemoryBound(to: Float32.self)
            for u in 0..<en { d[v * en + u] = r[u] }
        }
        var ishonch: [UInt8]?
        if let cm = sd.confidenceMap, CVPixelBufferGetWidth(cm) == en, CVPixelBufferGetHeight(cm) == boy {
            CVPixelBufferLockBaseAddress(cm, .readOnly)
            if let cb = CVPixelBufferGetBaseAddress(cm) {
                let cq = CVPixelBufferGetBytesPerRow(cm)
                var c = [UInt8](repeating: 0, count: en * boy)
                for v in 0..<boy {
                    let r = cb.advanced(by: v * cq).assumingMemoryBound(to: UInt8.self)
                    for u in 0..<en { c[v * en + u] = r[u] }
                }
                ishonch = c
            }
            CVPixelBufferUnlockBaseAddress(cm, .readOnly)
        }
        let rang = ranglar(f.capturedImage, en: en, boy: boy)
        // ichki parametrlar kamera tasviri o'lchamida → chuqurlik o'lchamiga (piksel markazi — butun indeks)
        let K = f.camera.intrinsics, W = Double(f.camera.imageResolution.width), H = Double(f.camera.imageResolution.height)
        let sx = Double(en) / W, sy = Double(boy) / H
        let T = f.camera.transform
        let m = Matritsa3([[Double(T.columns.0.x), Double(T.columns.1.x), Double(T.columns.2.x)],
                           [Double(T.columns.0.y), Double(T.columns.1.y), Double(T.columns.2.y)],
                           [Double(T.columns.0.z), Double(T.columns.1.z), Double(T.columns.2.z)]])
        let poza = PozaNamuna(t: f.timestamp, p: Vektor3(Double(T.columns.3.x), Double(T.columns.3.y), Double(T.columns.3.z)),
                              q: Kvaternion(m))
        let k = ChuqurlikKadri(t: f.timestamp, en: en, boy: boy, chuqurlik: d, ishonch: ishonch, rang: rang,
                               fx: Double(K[0][0]) * sx, fy: Double(K[1][1]) * sy,
                               cx: (Double(K[2][0]) + 0.5) * sx - 0.5, cy: (Double(K[2][1]) + 0.5) * sy - 0.5, kamera: poza)
        let sha = d.withUnsafeBytes { Xesh.hex(Data($0)) }
        return (k, sha)
    }

    /// Kamera tasviri (YCbCr 4:2:0 bi-planar, to'liq diapazon) → har chuqurlik pikseli markaziga mos RGB (BT.601).
    static func ranglar(_ img: CVPixelBuffer, en: Int, boy: Int) -> [UInt8]? {
        let f = CVPixelBufferGetPixelFormatType(img)
        guard f == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || f == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(img) == 2 else { return nil }
        CVPixelBufferLockBaseAddress(img, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(img, .readOnly) }
        guard let yb = CVPixelBufferGetBaseAddressOfPlane(img, 0), let cb = CVPixelBufferGetBaseAddressOfPlane(img, 1) else { return nil }
        let W = CVPixelBufferGetWidthOfPlane(img, 0), H = CVPixelBufferGetHeightOfPlane(img, 0)
        let yq = CVPixelBufferGetBytesPerRowOfPlane(img, 0), cq = CVPixelBufferGetBytesPerRowOfPlane(img, 1)
        let yp = yb.assumingMemoryBound(to: UInt8.self), cp = cb.assumingMemoryBound(to: UInt8.self)
        let toliq = f == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        var r = [UInt8](repeating: 0, count: en * boy * 3)
        let sx = Double(W) / Double(en), sy = Double(H) / Double(boy)
        @inline(__always) func k(_ x: Double) -> UInt8 { UInt8(max(0, min(255, x.rounded()))) }
        for v in 0..<boy {
            let y = min(H - 1, Int((Double(v) + 0.5) * sy))
            for u in 0..<en {
                let x = min(W - 1, Int((Double(u) + 0.5) * sx))
                var Y = Double(yp[y * yq + x])
                let ci = (y / 2) * cq + (x / 2) * 2
                var Cb = Double(cp[ci]) - 128, Cr = Double(cp[ci + 1]) - 128
                if !toliq { Y = (Y - 16) * 255 / 219; Cb *= 255 / 224; Cr *= 255 / 224 }
                let i = 3 * (v * en + u)
                r[i] = k(Y + 1.402 * Cr)
                r[i + 1] = k(Y - 0.344136 * Cb - 0.714136 * Cr)
                r[i + 2] = k(Y + 1.772 * Cb)
            }
        }
        return r
    }
}

/// DS-06: zich bulut fon oqimida yig'iladi (asosiy oqim bloklanmaydi). Kadrlar navbat bilan qo'shiladi.
actor ZichYiguvchi {
    private var bulut = ZichBulut()
    private(set) var kadrSoni = 0

    func qosh(_ k: ChuqurlikKadri) -> Int {
        kadrSoni += 1
        return bulut.qosh(k)
    }

    func nuqtalar() -> [BulutNuqtasi] { bulut.nuqtalar() }
    func vokselSoni() -> Int { bulut.vokselSoni }
}
