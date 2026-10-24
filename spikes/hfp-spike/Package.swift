// swift-tools-version: 6.0
import PackageDescription

// HFP 技术验证：Mac 作为免提设备（HF）连接手机（AG），验证来电、接听、挂断、拨号与语音链路（SCO）。
let package = Package(
    name: "hfp-spike",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "hfp-spike",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreAudio"),
                // 嵌入 Info.plist，否则访问蓝牙会因缺少用途说明被系统拒绝
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", "Sources/hfp-spike/Info.plist"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
