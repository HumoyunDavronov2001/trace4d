import Foundation
import Observation
import UIKit

/// UI-01, UI-08: telefon harorati, batareya va bo'sh xotira — tayyorlik varag'i va skan HUD i uchun.
@MainActor @Observable
final class QurilmaHolati {
    /// 0 nominal, 1 fair, 2 serious, 3 critical (`ProcessInfo.ThermalState`).
    private(set) var termal = 0
    /// 0…1; noma'lum (simulyator) bo'lsa nil.
    private(set) var batareya: Double?
    private(set) var boshXotiraBayt: Int64?
    @ObservationIgnored private var kuzatuvchilar: [NSObjectProtocol] = []

    func boshla() {
        yangila()
        guard kuzatuvchilar.isEmpty else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let nc = NotificationCenter.default
        for nom in [ProcessInfo.thermalStateDidChangeNotification, UIDevice.batteryLevelDidChangeNotification] {
            kuzatuvchilar.append(nc.addObserver(forName: nom, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.yangila() }
            })
        }
    }

    func toxtat() {
        for k in kuzatuvchilar { NotificationCenter.default.removeObserver(k) }
        kuzatuvchilar = []
    }

    func yangila() {
        termal = switch ProcessInfo.processInfo.thermalState {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 2
        }
        let b = UIDevice.current.batteryLevel
        batareya = b >= 0 ? Double(b) : nil
        let q = try? Papkalar.hujjatlar.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        boshXotiraBayt = q?.volumeAvailableCapacityForImportantUsage
    }
}
