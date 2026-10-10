import Foundation
import YerostiGeometriya
import YerostiQaytaHisob
import YerostiTahlil

// DM-02: data markaz ishchisi chaqiradigan CLI. Natija — JSON (stdout yoki --chiqish fayli).
//   yerosti-tahlil tekshir --jurnal jurnal.ymj --ply mesh.ply [--korinish korinish.ply] [--chiqish natija.json]
//   yerosti-tahlil aniqla --ply bulut.ply --zona 42 [--tarmoq suv] [--korinish k.ply] [--chiqish n.json]   (LD-02, tashqi LiDAR)
//   yerosti-tahlil farq --ply1 A.ply --ply2 B.ply [--georef1 "grad,tx,ty,tz" --georef2 ...] [--registratsiya 0.02] [--korinish f.ply] [--chiqish x.json]
//   yerosti-tahlil versiya
// Chiqish kodi: 0 — JSON yozildi (xulosa MOS/FARQ/XATO ichida), 64 — noto'g'ri buyruq, 74 — fayl o'qish/yozish xatosi.

func xato(_ m: String, _ kod: Int32) -> Never {
    FileHandle.standardError.write(Data(("yerosti-tahlil: " + m + "\n").utf8))
    exit(kod)
}

let a = Array(CommandLine.arguments.dropFirst())
guard let buyruq = a.first else { xato("buyruq kerak: tekshir | versiya", 64) }
if buyruq == "versiya" {
    print("\(QaytaHisob.versiya) · yadro \(YadroVersiya.matn)")
    exit(0)
}
guard buyruq == "tekshir" || buyruq == "aniqla" || buyruq == "farq" else { xato("noma'lum buyruq: \(buyruq)", 64) }

var bayroq: [String: String] = [:]
var i = 1
while i < a.count {
    guard a[i].hasPrefix("--"), i + 1 < a.count else { xato("bayroq qiymatsiz: \(a[i])", 64) }
    bayroq[String(a[i].dropFirst(2))] = a[i + 1]
    i += 2
}
if buyruq == "farq" {
    // KU-04: ikki ko'rinish buluti (ENU) orasidagi M3C2 farqi. --georef1/--georef2 "burchak_grad,tx,ty,tz" — B ni A ramkasiga.
    guard let p1 = bayroq["ply1"], let p2 = bayroq["ply2"] else { xato("--ply1 va --ply2 kerak", 64) }
    guard let d1 = FileManager.default.contents(atPath: p1), let d2 = FileManager.default.contents(atPath: p2) else { xato("PLY o'qilmadi", 74) }
    guard let A = PLY.oqi(d1), let B = PLY.oqi(d2) else { xato("PLY tuzilmasi noto'g'ri", 74) }
    func georef(_ s: String?) -> (Double, Vektor3)? {
        guard let s, !s.isEmpty else { return nil }
        let q = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard q.count == 4 else { xato("--georef: burchak_grad,tx,ty,tz", 64) }
        return (q[0] * .pi / 180, Vektor3(q[1], q[2], q[3]))
    }
    var Bn = B.nuqtalar.map(\.p)
    if let g1 = georef(bayroq["georef1"]), let g2 = georef(bayroq["georef2"]) {
        let T2 = GorizontalTransformatsiya(burchak: g2.0, t: g2.1), T1 = GorizontalTransformatsiya(burchak: g1.0, t: g1.1)
        let c = cos(-g1.0), s = sin(-g1.0)
        Bn = Bn.map { p in
            let u = T2.qolla(p) - T1.t                       // UTM ga, keyin A boshlang'ichiga nisbatan
            return Vektor3(c * u.x - s * u.y, s * u.x + c * u.y, u.z)   // A burilishini teskari qo'llash
        }
    }
    var sz = Farq.Sozlama()
    if let r = bayroq["registratsiya"].flatMap({ Double($0) }) { sz.registratsiyaM = r }
    let (natijalar, xulosa) = Farq.hisobla(A.nuqtalar.map(\.p), Bn, sz)
    if let k = bayroq["korinish"] {
        do { try Farq.ply(natijalar).write(to: URL(fileURLWithPath: k), options: .atomic) } catch { xato("farq buluti yozilmadi: \(error)", 74) }
    }
    do {
        let j = try Farq.json(xulosa)
        if let c = bayroq["chiqish"] { try j.write(to: URL(fileURLWithPath: c), options: .atomic) } else { FileHandle.standardOutput.write(j) }
    } catch { xato("natija yozilmadi: \(error)", 74) }
    exit(0)
}
guard let py = bayroq["ply"] else { xato("--ply kerak", 64) }
guard let pd = FileManager.default.contents(atPath: py) else { xato("PLY o'qilmadi: \(py)", 74) }
let korinishYoli = bayroq["korinish"]
let natija: QaytaHisob.Natija
let korinish: Data?
if buyruq == "aniqla" {
    // LD-02: tashqi LiDAR buluti (UTM, boshlang'ich PLY sarlavhasida) — muhrsiz, faqat quvur aniqlash
    guard let zona = bayroq["zona"].flatMap({ Int($0) }), (1...60).contains(zona) else { xato("--zona 1…60 kerak", 64) }
    (natija, korinish) = QaytaHisob.aniqla(ply: Array(pd), zona: zona, tarmoq: bayroq["tarmoq"],
                                           korinishMaks: korinishYoli == nil ? 0 : 600_000)
} else {
    guard let jy = bayroq["jurnal"] else { xato("--jurnal va --ply kerak", 64) }
    guard let jd = FileManager.default.contents(atPath: jy) else { xato("jurnal o'qilmadi: \(jy)", 74) }
    (natija, korinish) = QaytaHisob.tekshir(jurnal: Array(jd), ply: Array(pd), korinishMaks: korinishYoli == nil ? 0 : 600_000)
}
if let k = korinishYoli, let d = korinish {
    do { try d.write(to: URL(fileURLWithPath: k), options: .atomic) } catch { xato("ko'rinish yozilmadi: \(error)", 74) }
}
do {
    let j = try QaytaHisob.json(natija)
    if let c = bayroq["chiqish"] {
        try j.write(to: URL(fileURLWithPath: c), options: .atomic)
    } else {
        FileHandle.standardOutput.write(j)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
} catch {
    xato("natija yozilmadi: \(error)", 74)
}
