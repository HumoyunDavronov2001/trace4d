import Foundation

/// RTK holati — GGA 6-maydon (fix quality) dan.
public enum RTKHolat: String, Codable, Sendable, Equatable {
    case fix = "FIX"
    case float = "FLOAT"
    case dgps = "DGPS"
    case gps = "GPS"
    case yoq = "YOQ"

    public init(ggaSifatKodi: Int) {
        switch ggaSifatKodi {
        case 4: self = .fix
        case 5: self = .float
        case 2: self = .dgps
        case 1: self = .gps
        default: self = .yoq
        }
    }
}

public enum Sifat: String, Codable, Sendable, Equatable {
    case rasmiy = "RASMIY"
    case past = "PAST"
}

/// T-103 — sifat qoidasi. Serverdagi `yerosti_baza.sifat_hisobla` bilan BIR XIL.
/// Isbotsiz (sigma yoki tuzatma yoshi yo'q) nuqta hech qachon RASMIY bo'lmaydi.
public enum SifatQoidasi {
    public static let sigmaHChekSm = 2.0
    public static let sigmaVChekSm = 5.0
    public static let tuzatmaYoshiChekS = 10.0

    public static func hisobla(rtk: RTKHolat, sigmaHSm: Double?, sigmaVSm: Double?,
                               tuzatmaYoshiS: Double?) -> Sifat {
        guard rtk == .fix,
              let h = sigmaHSm, h <= sigmaHChekSm,
              let v = sigmaVSm, v <= sigmaVChekSm,
              let y = tuzatmaYoshiS, y <= tuzatmaYoshiChekS else { return .past }
        return .rasmiy
    }
}
