// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "cryptomako-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14), // so `swift test` can run library tests on the Mac host
    ],
    products: [
        .library(name: "CryptoMakoVault", targets: ["CryptoMakoVault"]),
        .library(name: "CryptoMakoS3", targets: ["CryptoMakoS3"]),
        .library(name: "CryptoMakoShared", targets: ["CryptoMakoShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/cryptomator/cryptolib-swift.git", .upToNextMinor(from: "1.1.0")),
    ],
    targets: [
        .target(name: "CryptoMakoS3"),
        .target(name: "CryptoMakoShared"),
        .target(
            name: "CryptoMakoVault",
            dependencies: [
                "CryptoMakoS3",
                "CryptoMakoShared",
                .product(name: "CryptomatorCryptoLib", package: "cryptolib-swift"),
            ]
        ),
        .testTarget(
            name: "CryptoMakoVaultTests",
            dependencies: [
                "CryptoMakoVault",
                "CryptoMakoS3",
                "CryptoMakoShared",
            ]
        ),
    ]
)
