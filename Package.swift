// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhraseKeyIME",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PhraseKeyIME", targets: ["PhraseKeyIME"])
    ],
    targets: [
        .executableTarget(
            name: "PhraseKeyIME",
            path: "Sources/PhraseKeyIME",
            resources: [
                .copy("Resources/dict.tsv")
            ],
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
