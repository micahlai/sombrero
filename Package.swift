// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WatercolorDuck",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WatercolorDuck", targets: ["DesktopPet"])],
    targets: [
        .target(name: "PetCore"),
        .target(name: "PetAssets", dependencies: ["PetCore"], resources: [.copy("Resources/Duck"), .copy("Resources/Fonts")]),
        .executableTarget(name: "DesktopPet", dependencies: ["PetCore", "PetAssets"]),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore", "PetAssets"])
    ]
)
