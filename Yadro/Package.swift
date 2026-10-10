// swift-tools-version:5.9
import PackageDescription

// YerostiYadro — platformadan mustaqil yadro (T-100, T-271).
// Linuxda `swift test` bilan isbotlanadi; iOS ilova (Ilova/) shu modullarni import qiladi.
let package = Package(
    name: "YerostiYadro",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "YerostiGeometriya", targets: ["YerostiGeometriya"]),
        .library(name: "YerostiDrayver", targets: ["YerostiDrayver"]),
        .library(name: "YerostiTahlil", targets: ["YerostiTahlil"]),
        .library(name: "YerostiMuhr", targets: ["YerostiMuhr"]),
        .library(name: "YerostiQaytaHisob", targets: ["YerostiQaytaHisob"]),
        // UI v3 mantig'i: tayyorlik, yo'riqnoma ustuvorligi, noaniqlik yo'lagi, yo'nalish (TALABLAR 13)
        .library(name: "YerostiHUD", targets: ["YerostiHUD"]),
        // DM-02: data markazda mustaqil qayta hisob (Linux CLI)
        .executable(name: "yerosti-tahlil", targets: ["yerosti-tahlil"]),
    ],
    targets: [
        .target(name: "YerostiGeometriya"),
        .target(name: "YerostiDrayver", dependencies: ["YerostiGeometriya"]),
        .target(name: "YerostiTahlil", dependencies: ["YerostiGeometriya"]),
        .target(name: "YerostiMuhr"),
        .target(name: "YerostiQaytaHisob",
                dependencies: ["YerostiDrayver", "YerostiGeometriya", "YerostiMuhr", "YerostiTahlil"]),
        .executableTarget(name: "yerosti-tahlil", dependencies: ["YerostiQaytaHisob", "YerostiTahlil"]),
        .target(name: "YerostiHUD", dependencies: ["YerostiGeometriya"]),
        // FAQAT SINOV: dala simulyatsiyasi (DS-04/05/06) — mahsulot (product) emas
        .target(name: "YerostiSimulyatsiya", dependencies: ["YerostiGeometriya", "YerostiTahlil"]),
        .testTarget(name: "YerostiGeometriyaTests", dependencies: ["YerostiGeometriya", "YerostiSimulyatsiya"]),
        .testTarget(name: "YerostiDrayverTests", dependencies: ["YerostiDrayver", "YerostiGeometriya"]),
        .testTarget(name: "YerostiTahlilTests", dependencies: ["YerostiTahlil", "YerostiGeometriya", "YerostiSimulyatsiya"]),
        .testTarget(name: "YerostiMuhrTests", dependencies: ["YerostiMuhr"]),
        .testTarget(name: "YerostiHUDTests", dependencies: ["YerostiHUD", "YerostiGeometriya"]),
        .testTarget(name: "YerostiQaytaHisobTests",
                    dependencies: ["YerostiQaytaHisob", "YerostiDrayver", "YerostiGeometriya", "YerostiMuhr", "YerostiTahlil",
                                   "YerostiSimulyatsiya"]),
    ]
)
