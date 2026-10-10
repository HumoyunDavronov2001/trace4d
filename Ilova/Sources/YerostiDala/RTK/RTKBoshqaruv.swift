import Foundation
import Observation
import YerostiDrayver
import YerostiGeometriya

/// RTK qabul qilgich + NTRIP + tuzatma kuzatuvi — ekranda doim ko'rinadigan holat (T-057, T-150, K-06).
@MainActor @Observable
final class RTKBoshqaruv {
    enum Ulanish: Equatable {
        case yoq
        case ulanmoqda
        case ulangan(String)
        case xato(String)
    }

    private(set) var ulanish: Ulanish = .yoq
    private(set) var holat = QabulQilgichHolati()
    private(set) var ntripHolati: NTRIPKlient.Holat = .ochiq
    private(set) var tuzatmaYoshiS: Double?
    private(set) var bazaMasofaKm: Double?
    private(set) var tizimlar: [String] = []
    private(set) var qurilmaSeriya: String?
    /// DS-01: ulangan qabul qilgich iOS bilan mosmi (RX2 / RX MFi) — ekranda ko'rsatiladi, profil yozuviga kiradi.
    private(set) var moslik: ReachMoslik.Natija?
    private(set) var qurilmaNomi: String?
    private(set) var soat = Date()

    var sifat: Sifat { holat.sifat(hozir: soat) }
    var ulangan: Bool { if case .ulangan = ulanish { return true } else { return false } }

    /// Har NMEA satri va telefonga kelgan vaqti (uptime, s) — skan paytida muhr jurnaliga yoziladi (K-05, DS-03).
    @ObservationIgnored var satrKeldi: ((String, TimeInterval) -> Void)?
    /// Yangi GGA epoxasi — skan dvigateli kamera pozasi bilan juftlaydi (georeferens).
    @ObservationIgnored var epoxaKeldi: ((QabulQilgichHolati, TimeInterval) -> Void)?
    /// RTCM bo'laklari — muhr jurnaliga xeshi yoziladi.
    @ObservationIgnored var tuzatmaKeldi: ((Data) -> Void)?

    @ObservationIgnored private var drayver: Drayver?
    @ObservationIgnored private var transport: NMEATransport?
    @ObservationIgnored private let ntrip = NTRIPKlient()
    @ObservationIgnored private let rtcm = RTCM3Ajratuvchi()
    @ObservationIgnored private var kuzatuvchi = TuzatmaKuzatuvchi()
    @ObservationIgnored private var taymer: Timer?
    @ObservationIgnored private var oxirgiGGAVaqt: String?

    func ulanEA() {
        let t = EATransport()
        t.uzildi = { [weak self] m in Task { @MainActor in self?.ulanish = .xato(m) } }
        ulan(t)
        qurilmaSeriya = t.seriya
        if let a = t.aksessuar {
            qurilmaNomi = a.name
            moslik = ReachMoslik.aksessuardan(nomi: a.name, model: a.modelNumber, seriya: a.serialNumber, protokollar: a.protocolStrings)
        }
    }

    func ulanTCP(host: String, port: Int) {
        qurilmaNomi = "TCP \(host):\(port)"
        moslik = nil
        let t = TCPTransport(host: host, port: UInt16(clamping: port))
        t.uzildi = { [weak self] m in Task { @MainActor in self?.ulanish = .xato(m) } }
        ulan(t)
    }

    private func ulan(_ t: NMEATransport) {
        uz()
        ulanish = .ulanmoqda
        let d = Drayver(transport: t)
        d.satrKeldi = { [weak self] s in self?.satrKeldi?(s, ProcessInfo.processInfo.systemUptime) }
        d.holatOzgardi = { [weak self] h in
            guard let self else { return }
            self.holat = h
            // Yangi GGA epoxasi (vaqt maydoni o'zgargan) — pozani juftlash uchun
            if h.oxirgiGGA != nil, h.vaqtUTC != self.oxirgiGGAVaqt {
                self.oxirgiGGAVaqt = h.vaqtUTC
                self.epoxaKeldi?(h, ProcessInfo.processInfo.systemUptime)
            }
        }
        do {
            try d.ulan()
            drayver = d; transport = t
            ulanish = .ulangan(t.nomi)
        } catch {
            ulanish = .xato(error.localizedDescription)
        }
        taymer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tikla() }
        }
    }

    func uz() {
        taymer?.invalidate(); taymer = nil
        drayver?.uz(); drayver = nil; transport = nil
        ntrip.uz()
        ulanish = .yoq
    }

    func ntripUlan(_ s: NTRIPSozlama) {
        kuzatuvchi = TuzatmaKuzatuvchi()
        ntrip.holatOzgardi = { [weak self] h in self?.ntripHolati = h }
        ntrip.rtcmKeldi = { [weak self] d in
            guard let self else { return }
            self.kuzatuvchi.qabul(self.rtcm.qabul(d), baytSoni: d.count)
            try? self.transport?.yubor(d)  // qabul qilgichga (MFi: com.emlid.corrections)
            self.tuzatmaKeldi?(d)
        }
        ntrip.ulan(s) { [weak self] in self?.drayver?.oxirgiGGASatri }
    }

    func ntripUz() { ntrip.uz() }

    private func tikla() {
        soat = Date()
        tuzatmaYoshiS = kuzatuvchi.yoshiS(hozir: soat)
        tizimlar = kuzatuvchi.tizimlar
        if let lat = holat.lat, let lon = holat.lon {
            bazaMasofaKm = kuzatuvchi.bazaMasofasiKm(lat: lat, lon: lon, h: holat.balandlikEllipsoid ?? 0)
        }
    }
}
