import CryptoKit
import Foundation
import YerostiMuhr

/// Qurilma kaliti — iPhone Secure Enclave ichida yaratiladi va undan hech qachon chiqmaydi (K-05).
/// Faylda faqat shu qurilmaning Secure Enclave'i ocha oladigan shifrlangan havola saqlanadi.
enum QurilmaKaliti {
    private static var fayl: URL { Papkalar.ichki.appendingPathComponent("qurilma_kaliti.se") }

    static func kalit() throws -> SecureEnclave.P256.Signing.PrivateKey {
        if let d = try? Data(contentsOf: fayl) {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: d)
        }
        guard SecureEnclave.isAvailable else {
            throw NSError(domain: "TRACE4D", code: 1, userInfo: [NSLocalizedDescriptionKey: "Secure Enclave mavjud emas"])
        }
        let k = try SecureEnclave.P256.Signing.PrivateKey()
        try k.dataRepresentation.write(to: fayl, options: [.atomic, .completeFileProtection])
        return k
    }

    /// 65 baytli siqilmagan ochiq kalit — serverga ro'yxatdan o'tkaziladi.
    static func ochiqKalit() throws -> Data { try kalit().publicKey.x963Representation }

    static func barmoqIzi() -> String? {
        guard let k = try? ochiqKalit() else { return nil }
        return CryptoKit.SHA256.hash(data: k).prefix(6).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// ECDSA P-256 / SHA-256 imzo, DER ko'rinishida (server `cryptography` bilan tekshiradi).
    static func imzola(_ d: Data) throws -> Data { try kalit().signature(for: d).derRepresentation }
}

/// Muhr jurnali: har yozuv zanjirga qo'shiladi va darhol diskka yoziladi ("YMJ1" formati).
final class MuhrYozuvchi {
    private(set) var zanjir = MuhrZanjir()
    let url: URL
    private let dastak: FileHandle

    init(papka: URL) throws {
        url = papka.appendingPathComponent("jurnal.ymj")
        FileManager.default.createFile(atPath: url.path, contents: Data(MuhrZanjir.jurnalSarlavha))
        dastak = try FileHandle(forWritingTo: url)
        try dastak.seekToEnd()
    }

    func yoz(_ tur: YozuvTuri, _ d: Data) {
        let b = zanjir.qosh(tur, Array(d))
        try? dastak.write(contentsOf: Data(b))
    }

    func yoz(_ tur: YozuvTuri, matn: String) { yoz(tur, Data(matn.utf8)) }

    func yoz<T: Encodable>(_ tur: YozuvTuri, json: T) {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        if let d = try? e.encode(json) { yoz(tur, d) }
    }

    func yop() { try? dastak.synchronize(); try? dastak.close() }
}

enum Xesh {
    static func hex(_ d: Data) -> String { CryptoKit.SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
    static func fayl(_ u: URL) -> (sha: String, hajm: Int)? {
        guard let d = try? Data(contentsOf: u, options: .mappedIfSafe) else { return nil }
        return (hex(d), d.count)
    }
}
