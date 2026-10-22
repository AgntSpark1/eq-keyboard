// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PinyinKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PinyinKit", targets: ["PinyinKit"])],
    targets: [
        .target(name: "PinyinKit", resources: [.copy("Resources/pinyin_dict.tsv"), .copy("Resources/chat_predictions.tsv")]),
        .testTarget(name: "PinyinKitTests", dependencies: ["PinyinKit"]),
    ]
)
