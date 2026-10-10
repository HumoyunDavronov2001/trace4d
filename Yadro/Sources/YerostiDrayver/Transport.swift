import Foundation

/// Transport — baytlar oqimi. Amalga oshirishlar iOS ilovasida:
/// EA (External Accessory, `com.emlid.nmea` / `com.emlid.corrections`), TCP (Network.framework), BLE.
public protocol NMEATransport: AnyObject {
    var nomi: String { get }
    var qabulQilindi: ((Data) -> Void)? { get set }
    func ulan() throws
    func uz()
    /// RTCM tuzatmalarini qabul qilgichga yuborish (NTRIP klient ilovada bo'lsa).
    func yubor(_ data: Data) throws
}

/// Baytlar oqimidan butun NMEA satrlarini ajratadi; yarim satrlarni keyingi bo'lakkacha saqlaydi.
public final class NMEAOqimYiguvchi {
    private var bufer = Data()
    public let satrChegarasi: Int

    public init(satrChegarasi: Int = 1024) { self.satrChegarasi = satrChegarasi }

    public func qabul(_ d: Data) -> [String] {
        bufer.append(d)
        var satrlar: [String] = []
        while let yangiQator = bufer.firstIndex(of: 0x0A) {
            let qism = bufer[bufer.startIndex..<yangiQator]
            bufer.removeSubrange(bufer.startIndex...yangiQator)
            guard let dollar = qism.firstIndex(of: 0x24) else { continue }  // '$' gacha axlat tashlanadi
            let toza = qism[dollar...]
            if toza.count > satrChegarasi { continue }
            if let s = String(data: toza, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty { satrlar.append(s) }
        }
        if bufer.count > satrChegarasi * 4 { bufer.removeAll() }  // '$' siz oqim — himoya
        return satrlar
    }
}

/// Xom NMEA jurnali (T-105) — sessiyada har satr vaqt muhri bilan; siqish ilovada.
public final class NMEAJurnal {
    public private(set) var satrlar: [(vaqt: Date, satr: String)] = []
    public let chegara: Int
    public init(chegara: Int = 200_000) { self.chegara = chegara }
    public func yoz(_ satr: String, vaqt: Date = Date()) {
        if satrlar.count >= chegara { satrlar.removeFirst(chegara / 10) }
        satrlar.append((vaqt, satr))
    }
    public func matn() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return satrlar.map { "\(f.string(from: $0.vaqt)) \($0.satr)" }.joined(separator: "\n")
    }
}

/// Drayver: transportdan satrlar → holat, jurnal. Ilova shu obyektni kuzatadi.
public final class Drayver {
    public private(set) var holat = QabulQilgichHolati()
    public let jurnal = NMEAJurnal()
    public var holatOzgardi: ((QabulQilgichHolati) -> Void)?
    /// Har bir xom NMEA satri (muhr jurnaliga yozish uchun).
    public var satrKeldi: ((String) -> Void)?
    /// Oxirgi GGA satri — VRS casterga yuborish uchun (T-104).
    public private(set) var oxirgiGGASatri: String?
    private let yiguvchi = NMEAOqimYiguvchi()
    private let transport: NMEATransport

    public init(transport: NMEATransport) {
        self.transport = transport
        transport.qabulQilindi = { [weak self] d in self?.baytlar(d) }
    }

    public func ulan() throws { try transport.ulan() }
    public func uz() { transport.uz() }

    func baytlar(_ d: Data, hozir: Date = Date()) {
        for satr in yiguvchi.qabul(d) {
            jurnal.yoz(satr, vaqt: hozir)
            satrKeldi?(satr)
            guard let x = try? NMEAXabar.ajrat(satr) else { continue }  // buzuq satr jimgina tashlanmaydi — jurnalda qoladi
            if case .gga = x { oxirgiGGASatri = satr }
            holat.qabul(x, hozir: hozir)
        }
        holatOzgardi?(holat)
    }
}
