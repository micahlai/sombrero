// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sombrero",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "sombrero", targets: ["DesktopPet"])],
    targets: [
        .target(name: "PetCore"),
        .target(name: "PetAssets", dependencies: ["PetCore"], exclude: ["Resources/Duck"], resources: [.copy("Resources/FinalDuck"), .copy("Resources/Fonts"), .copy("Resources/Bible"), .copy("Resources/Polaroid"), .copy("Resources/Controls")]),
        .executableTarget(name: "DesktopPet", dependencies: ["PetCore", "PetAssets"]),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore", "PetAssets"])
    ]
)
