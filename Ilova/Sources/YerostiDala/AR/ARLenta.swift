import RealityKit
import simd

extension Mesh {
    /// UI-12/13: poliliniya bo'ylab gorizontal lenta (yer yuzasida). `punktir` — (chiziq, oraliq) metrda; nil — uzluksiz.
    /// Ikki tomonlama uchburchaklar: yuqoridan ham, pastdan ham ko'rinadi.
    static func lenta(_ P: [SIMD3<Float>], yarimKenglik w: Float, punktir: (Float, Float)?) -> MeshResource? {
        guard P.count >= 2, w > 0 else { return nil }
        // 5 sm qadam bilan qayta namunalash — punktir va burilishlar tekis chiqsin
        var n: [SIMD3<Float>] = [P[0]]
        for i in 1..<P.count {
            let a = P[i - 1], b = P[i]
            let k = max(1, Int(simd_length(b - a) / 0.05))
            for j in 1...k { n.append(a + (b - a) * (Float(j) / Float(k))) }
        }
        var pos: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        var s: Float = 0
        for i in 1..<n.count {
            let a = n[i - 1], b = n[i], d = b - a
            let l = simd_length(SIMD2<Float>(d.x, d.z))
            let bosh = s
            s += l
            if let p = punktir, bosh.truncatingRemainder(dividingBy: p.0 + p.1) > p.0 { continue }
            guard l > 1e-5 else { continue }
            let yon = SIMD3<Float>(-d.z / l, 0, d.x / l) * w
            let k = UInt32(pos.count)
            pos += [a - yon, a + yon, b + yon, b - yon]
            idx += [k, k + 1, k + 2, k, k + 2, k + 3, k, k + 2, k + 1, k, k + 3, k + 2]
        }
        guard !idx.isEmpty else { return nil }
        var desc = MeshDescriptor(name: "lenta")
        desc.positions = MeshBuffers.Positions(pos)
        desc.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [desc])
    }
}
