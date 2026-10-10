import ExternalAccessory
import Foundation
import YerostiDrayver

enum TransportXato: LocalizedError {
    case qurilmaTopilmadi
    case sessiyaOchilmadi
    case manzilNotogri

    var errorDescription: String? {
        switch self {
        case .qurilmaTopilmadi: return "Emlid qabul qilgich ulanmagan. Bluetooth orqali juftlang va Emlid Flow'da NMEA oqimini yoqing."
        case .sessiyaOchilmadi: return "Qabul qilgich bilan sessiya ochilmadi"
        case .manzilNotogri: return "TCP manzil yoki port noto'g'ri"
        }
    }
}

/// MFi (Made for iPhone) qabul qilgich — Emlid Reach RX/RX2. External Accessory framework:
/// `com.emlid.nmea` — NMEA o'qish, `com.emlid.corrections` — RTCM tuzatmalarini yozish (T-101).
final class EATransport: NSObject, NMEATransport, StreamDelegate {
    static let nmeaProtokol = "com.emlid.nmea"
    static let tuzatmaProtokol = "com.emlid.corrections"

    var nomi: String { aksessuar.map { "\($0.name) (MFi)" } ?? "Emlid (MFi)" }
    var qabulQilindi: ((Data) -> Void)?
    var uzildi: ((String) -> Void)?
    private(set) var aksessuar: EAAccessory?
    var seriya: String? { aksessuar?.serialNumber }

    private var nmea: EASession?
    private var tuzatma: EASession?
    private var navbat = Data()
    private var bufer = [UInt8](repeating: 0, count: 4096)

    /// Hali juftlanmagan Bluetooth MFi qurilmani tanlash oynasi.
    static func tanlash(_ tugadi: @escaping (Error?) -> Void) {
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil) { tugadi($0) }
    }

    func ulan() throws {
        let m = EAAccessoryManager.shared()
        m.registerForLocalNotifications()
        guard let a = m.connectedAccessories.first(where: { $0.protocolStrings.contains(EATransport.nmeaProtokol) }) else {
            throw TransportXato.qurilmaTopilmadi
        }
        aksessuar = a
        guard let s = EASession(accessory: a, forProtocol: EATransport.nmeaProtokol) else { throw TransportXato.sessiyaOchilmadi }
        nmea = s
        ochish(s.inputStream)
        if a.protocolStrings.contains(EATransport.tuzatmaProtokol),
           let t = EASession(accessory: a, forProtocol: EATransport.tuzatmaProtokol) {
            tuzatma = t
            ochish(t.outputStream)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(ajraldi(_:)), name: .EAAccessoryDidDisconnect, object: nil)
    }

    private func ochish(_ s: Stream?) {
        guard let s else { return }
        s.delegate = self
        s.schedule(in: .main, forMode: .default)
        s.open()
    }

    func uz() {
        for s in [nmea?.inputStream, tuzatma?.outputStream] as [Stream?] {
            s?.close(); s?.remove(from: .main, forMode: .default); s?.delegate = nil
        }
        nmea = nil; tuzatma = nil; navbat.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    func yubor(_ data: Data) throws {
        guard tuzatma != nil else { return }
        navbat.append(data)
        if navbat.count > 64 * 1024 { navbat.removeFirst(navbat.count - 64 * 1024) }  // eski tuzatma foydasiz
        yuborNavbat()
    }

    private func yuborNavbat() {
        guard let o = tuzatma?.outputStream, o.hasSpaceAvailable, !navbat.isEmpty else { return }
        let n = navbat.withUnsafeBytes { p in o.write(p.bindMemory(to: UInt8.self).baseAddress!, maxLength: p.count) }
        if n > 0 { navbat.removeFirst(n) }
    }

    func stream(_ s: Stream, handle e: Stream.Event) {
        switch e {
        case .hasBytesAvailable:
            guard let i = s as? InputStream else { return }
            while i.hasBytesAvailable {
                let n = bufer.withUnsafeMutableBufferPointer { b in i.read(b.baseAddress!, maxLength: b.count) }
                if n <= 0 { break }
                qabulQilindi?(Data(bufer[0..<n]))
            }
        case .hasSpaceAvailable:
            yuborNavbat()
        case .errorOccurred, .endEncountered:
            uzildi?("qabul qilgich oqimi uzildi")
        default:
            break
        }
    }

    @objc private func ajraldi(_ n: Notification) {
        guard let a = n.userInfo?[EAAccessoryKey] as? EAAccessory, a.connectionID == aksessuar?.connectionID else { return }
        uz()
        uzildi?("\(a.name) uzildi")
    }
}
