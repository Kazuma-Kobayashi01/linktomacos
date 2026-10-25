import LinkCore
import SwiftUI

enum ChipVendor {
    case qualcomm, samsung, mediatek, google, other

    var displayName: String {
        switch self {
        case .qualcomm: "Qualcomm"
        case .samsung: "Samsung"
        case .mediatek: "MediaTek"
        case .google: "Google"
        case .other: ""
        }
    }

    var gradient: AnyShapeStyle {
        switch self {
        case .qualcomm: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.89, green: 0.15, blue: 0.18), Color(red: 0.62, green: 0.07, blue: 0.12)], startPoint: .top, endPoint: .bottom))
        case .samsung: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.18, green: 0.30, blue: 0.80), Color(red: 0.08, green: 0.16, blue: 0.55)], startPoint: .top, endPoint: .bottom))
        case .mediatek: AnyShapeStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.0), Color(red: 0.96, green: 0.58, blue: 0.0)], startPoint: .top, endPoint: .bottom))
        case .google: AnyShapeStyle(AngularGradient(colors: [.blue, .red, .yellow, .green, .blue], center: .center))
        case .other: AnyShapeStyle(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom))
        }
    }
}

struct ChipInfo: Equatable {
    var vendor: ChipVendor
    /// 完整的芯片名称，如 “Snapdragon 8 Gen 2 for Galaxy”。
    var name: String
}

/// 手机只告诉我们芯片的型号代号（如 SM8550），这里换成大家熟悉的名称。
/// 没收录的型号会原样显示代号，不会显示错误的名字。
enum ChipCatalog {
    static func lookup(_ info: DeviceInfo) -> ChipInfo? {
        guard let rawModel = info.socModel?.trimmingCharacters(in: .whitespaces), !rawModel.isEmpty,
              rawModel.lowercased() != "unknown" else { return nil }
        let model = rawModel.uppercased()
        let vendor = vendor(manufacturer: info.socManufacturer ?? "", hardware: info.hardware ?? "", model: model)

        var name = names[model] ?? names[String(model.split(separator: "-").first ?? "")]
        if name == nil {
            let maker = info.socManufacturer.flatMap { $0.uppercased() == "QTI" ? "Qualcomm" : $0 } ?? vendor.displayName
            return ChipInfo(vendor: vendor, name: [maker, rawModel].filter { !$0.isEmpty }.joined(separator: " "))
        }
        // 三星把骁龙 8 系列旗舰定制为 “for Galaxy” 版本
        if vendor == .qualcomm, info.manufacturer.lowercased() == "samsung",
           let current = name, current.hasPrefix("Snapdragon 8"),
           current.contains("Gen 2") || current.contains("Gen 3") || current.contains("Elite") {
            name = current + " for Galaxy"
        }
        return ChipInfo(vendor: vendor, name: name ?? rawModel)
    }

    private static func vendor(manufacturer: String, hardware: String, model: String) -> ChipVendor {
        let maker = manufacturer.lowercased()
        if maker.contains("qti") || maker.contains("qualcomm") || hardware.lowercased() == "qcom" || model.hasPrefix("SM") || model.hasPrefix("SDM") { return .qualcomm }
        if maker.contains("samsung") || model.hasPrefix("S5E") || hardware.lowercased().hasPrefix("exynos") { return .samsung }
        if maker.contains("mediatek") || maker.contains("mtk") || model.hasPrefix("MT") { return .mediatek }
        if maker.contains("google") || model.hasPrefix("GS") || model.hasPrefix("ZUMA") { return .google }
        return .other
    }

    private static let names: [String: String] = [
        // Qualcomm Snapdragon
        "SM8750": "Snapdragon 8 Elite", "SM8735": "Snapdragon 8s Gen 4", "SM8650": "Snapdragon 8 Gen 3",
        "SM8635": "Snapdragon 8s Gen 3", "SM8550": "Snapdragon 8 Gen 2", "SM8475": "Snapdragon 8+ Gen 1",
        "SM8450": "Snapdragon 8 Gen 1", "SM8350": "Snapdragon 888", "SM8250": "Snapdragon 865", "SM8150": "Snapdragon 855",
        "SM7675": "Snapdragon 7+ Gen 3", "SM7550": "Snapdragon 7 Gen 3", "SM7475": "Snapdragon 7+ Gen 2",
        "SM7450": "Snapdragon 7 Gen 1", "SM7435": "Snapdragon 7s Gen 2", "SM6475": "Snapdragon 6 Gen 3",
        "SM6450": "Snapdragon 6 Gen 1", "SM6375": "Snapdragon 695 5G", "SM6225": "Snapdragon 680 4G",
        // Samsung Exynos
        "S5E9955": "Exynos 2500", "S5E9945": "Exynos 2400", "S5E9925": "Exynos 2200", "S5E9840": "Exynos 2100",
        "S5E9830": "Exynos 990", "S5E8845": "Exynos 1480", "S5E8835": "Exynos 1380", "S5E8535": "Exynos 1330",
        "S5E8825": "Exynos 1280",
        // MediaTek Dimensity
        "MT6991": "Dimensity 9400", "MT6989": "Dimensity 9300", "MT6985": "Dimensity 9200", "MT6983": "Dimensity 9000",
        "MT6897": "Dimensity 8300", "MT6895": "Dimensity 8100", "MT6878": "Dimensity 7050", "MT6877": "Dimensity 900",
        // Google Tensor
        "GS101": "Tensor", "GS201": "Tensor G2", "ZUMA": "Tensor G3", "ZUMAPRO": "Tensor G4",
    ]
}

/// 品牌色的芯片徽标。
struct ChipBadge: View {
    let vendor: ChipVendor
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(vendor.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "cpu.fill")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}
