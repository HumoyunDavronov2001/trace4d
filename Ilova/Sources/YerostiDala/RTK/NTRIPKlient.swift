import Foundation
import Network
import YerostiDrayver

/// NTRIP klient (Network.framework) — protokol tahlili yadroda (NTRIPJavob, sinalgan).
@MainActor
final class NTRIPKlient {
    enum Holat: Equatable {
        case ochiq
        case ulanmoqda
        case oqim
        case xato(String)
    }

    var holatOzgardi: ((Holat) -> Void)?
    var rtcmKeldi: ((Data) -> Void)?
    private(set) var holat: Holat = .ochiq { didSet { holatOzgardi?(holat) } }
    private var ulanish: NWConnection?
    private var javob: NTRIPJavob?
    private var ggaTaymer: Timer?

    func ulan(_ s: NTRIPSozlama, gga: @escaping () -> String?) {
        uz()
        guard !s.host.isEmpty, !s.mountpoint.isEmpty, let port = NWEndpoint.Port(rawValue: UInt16(clamping: s.port)) else {
            holat = .xato("NTRIP sozlamasi to'liq emas"); return
        }
        holat = .ulanmoqda
        let j = NTRIPJavob(mountpointSoralgan: true)
        javob = j
        let c = NWConnection(host: NWEndpoint.Host(s.host), port: port, using: s.port == 443 ? .tls : .tcp)
        ulanish = c
        c.stateUpdateHandler = { [weak self] h in
            Task { @MainActor in
                guard let self else { return }
                switch h {
                case .ready:
                    c.send(content: NTRIPSorov.mountpoint(s, gga: gga()), completion: .contentProcessed { _ in })
                case .failed(let x):
                    self.holat = .xato("caster: \(x.localizedDescription)")
                default: break
                }
            }
        }
        c.start(queue: .main)
        oqi(c)
        // VRS tarmoqlari rover joyini so'raydi: har 10 s da oxirgi GGA
        ggaTaymer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.holat == .oqim, let g = gga() else { return }
                self.ulanish?.send(content: Data((g + "\r\n").utf8), completion: .contentProcessed { _ in })
            }
        }
    }

    private func oqi(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] d, _, tugadi, x in
            Task { @MainActor in
                guard let self, let j = self.javob else { return }
                if let d, !d.isEmpty {
                    let rtcm = j.qabul(d)
                    switch j.holat {
                    case .oqim: if self.holat != .oqim { self.holat = .oqim }
                    case .xato(let m): self.holat = .xato(m); self.uz(holatniSaqla: true); return
                    default: break
                    }
                    if !rtcm.isEmpty { self.rtcmKeldi?(rtcm) }
                }
                if x == nil, !tugadi { self.oqi(c) } else if self.holat == .oqim { self.holat = .xato("caster ulanishni yopdi") }
            }
        }
    }

    func uz(holatniSaqla: Bool = false) {
        ggaTaymer?.invalidate(); ggaTaymer = nil
        ulanish?.cancel(); ulanish = nil
        javob = nil
        if !holatniSaqla { holat = .ochiq }
    }

    /// Manba jadvalini olish (mountpointlar ro'yxati) — eng yaqin bazani tanlash uchun (K-06).
    static func manbaJadvali(host: String, port: Int, versiya: Int) async throws -> [Mountpoint] {
        try await withCheckedThrowingContinuation { (davom: CheckedContinuation<[Mountpoint], Error>) in
            guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
                davom.resume(throwing: TransportXato.manzilNotogri); return
            }
            let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: port == 443 ? .tls : .tcp)
            let j = NTRIPJavob(mountpointSoralgan: false)
            let bayroq = Bayroq()
            func yakun(_ r: Result<[Mountpoint], Error>) {
                guard !bayroq.tugadi else { return }
                bayroq.tugadi = true
                c.cancel()
                davom.resume(with: r)
            }
            func oqi() {
                c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { d, _, oxir, x in
                    if let d { _ = j.qabul(d) }
                    if case .xato(let m) = j.holat { yakun(.failure(NSError(domain: "NTRIP", code: 1, userInfo: [NSLocalizedDescriptionKey: m]))); return }
                    if j.manbaJadvaliTugadi || oxir || x != nil { yakun(.success(ManbaJadvali.ajrat(j.manbaJadvaliMatni))); return }
                    oqi()
                }
            }
            c.stateUpdateHandler = { h in
                switch h {
                case .ready: c.send(content: NTRIPSorov.manbaJadvali(host: host, port: port, versiya: versiya), completion: .contentProcessed { _ in })
                case .failed(let x): yakun(.failure(x))
                default: break
                }
            }
            c.start(queue: .main)
            oqi()
        }
    }
}

/// Bir marta yakunlash belgisi (callbacklar asosiy navbatda keladi).
private final class Bayroq { var tugadi = false }
