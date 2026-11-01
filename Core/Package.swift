// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AdegaCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AdegaCore", targets: ["AdegaCore"]),
        .executable(name: "adega", targets: ["adega"]),
    ],
    targets: [
        // Núcleo sem UI: compila em macOS e Linux (o Linux serve só para testes/CI).
        .target(name: "AdegaCore"),
        // CLI para uso no Terminal e para a "Fase 0" (prova de conceito).
        .executableTarget(name: "adega", dependencies: ["AdegaCore"]),
        .testTarget(name: "AdegaCoreTests", dependencies: ["AdegaCore"]),
    ]
)
