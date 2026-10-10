import Foundation
import Network
import YerostiDrayver

/// Wi-Fi/TCP orqali NMEA — istalgan qabul qilgich (Emlid Reach RS3 hotspoti, Trimble, CHC...) (T-101, K-10).
final class TCPTransport: NMEATransport {
    let host: String
    let port: UInt16
    var nomi: String { "TCP \(host):\(port)" }
    var qabulQilindi: ((Data) -> Void)?
    var uzildi: ((String) -> Void)?
    private var ulanish: NWConnection?

    init(host: String, port: UInt16) { self.host = host; self.port = port }

    func ulan() throws {
        guard !host.isEmpty, let p = NWEndpoint.Port(rawValue: port) else { throw TransportXato.manzilNotogri }
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        c.stateUpdateHandler = { [weak self] h in
            if case .failed(let x) = h { self?.uzildi?("TCP: \(x.localizedDescription)") }
        }
        c.start(queue: .main)
        ulanish = c
        oqi(c)
    }

    private func oqi(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] d, _, tugadi, x in
            if let d, !d.isEmpty { self?.qabulQilindi?(d) }
            if x == nil, !tugadi { self?.oqi(c) } else { self?.uzildi?("TCP ulanish yopildi") }
        }
    }

    func uz() { ulanish?.cancel(); ulanish = nil }

    func yubor(_ data: Data) throws {
        ulanish?.send(content: data, completion: .contentProcessed { _ in })
    }
}
