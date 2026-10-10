// swift-tools-version: 6.0

import PackageDescription

// YEROSTI Dala — iPhone Pro (LiDAR) ilovasi. xtool bilan Linuxda yig'iladi (T-270):
//   xtool dev            — yig'ib, USB orqali ulangan iPhone'ga o'rnatadi
//   xtool dev build      — faqat yig'ish
// Yadro (Linuxda sinalgan) ../Yadro dan olinadi.
let package = Package(
    name: "YerostiDala",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // xtool loyihasida aynan bitta library mahsulot bo'ladi — u ilovaning o'zi.
        .library(name: "YerostiDala", targets: ["YerostiDala"]),
    ],
    dependencies: [
        .package(path: "../Yadro"),
    ],
    targets: [
        .target(
            name: "YerostiDala",
            dependencies: [
                .product(name: "YerostiGeometriya", package: "Yadro"),
                .product(name: "YerostiDrayver", package: "Yadro"),
                .product(name: "YerostiTahlil", package: "Yadro"),
                .product(name: "YerostiMuhr", package: "Yadro"),
                .product(name: "YerostiHUD", package: "Yadro"),
                // DS-04/05: skan yakunida telefonning o'zida server bilan bir xil qayta hisob
                .product(name: "YerostiQaytaHisob", package: "Yadro"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
