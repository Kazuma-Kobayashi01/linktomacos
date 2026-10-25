import Foundation

/// Mac 键盘 → Android 键值。按 macOS 虚拟键码（与键盘布局无关的物理位置）映射，文字输入走另一条路。
public enum AndroidKeys {
    // Android KeyEvent 键值
    public static let back = 4
    public static let home = 3
    public static let appSwitch = 187

    // Android 修饰键标志（左右键标志一并带上，部分应用只认带左右标志的）
    public static let metaShift = 0x1 | 0x40
    public static let metaAlt = 0x2 | 0x10
    public static let metaCtrl = 0x1000 | 0x2000

    /// macOS 修饰键（`NSEvent.ModifierFlags.rawValue`）→ Android 修饰键。⌘ 当作 Ctrl，这样 ⌘C/⌘V 在手机上也有效。
    public static func metaState(shift: Bool, option: Bool, control: Bool, command: Bool) -> Int {
        var meta = 0
        if shift { meta |= metaShift }
        if option { meta |= metaAlt }
        if control || command { meta |= metaCtrl }
        return meta
    }

    /// 返回 nil 表示这个键不转发。
    public static func keyCode(forMacKeyCode code: UInt16) -> Int? {
        table[code]
    }

    private static let letters: [UInt16: Int] = {
        // macOS 虚拟键码 → 字母，Android 的 A…Z 是 29…54
        let mac: [(UInt16, Character)] = [
            (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"), (34, "I"), (38, "J"),
            (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"),
            (32, "U"), (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        ]
        var result: [UInt16: Int] = [:]
        for (code, letter) in mac { result[code] = 29 + Int(letter.asciiValue! - Character("A").asciiValue!) }
        return result
    }()

    private static let table: [UInt16: Int] = {
        var map = letters
        // 数字行：0 是 7，1…9 是 8…16
        for (code, digit) in [(29, 0), (18, 1), (19, 2), (20, 3), (21, 4), (23, 5), (22, 6), (26, 7), (28, 8), (25, 9)] {
            map[UInt16(code)] = 7 + digit
        }
        let others: [UInt16: Int] = [
            36: 66,   // Return → ENTER
            76: 66,   // 小键盘 Enter
            48: 61,   // Tab
            49: 62,   // Space
            51: 67,   // Delete（退格）→ DEL
            117: 112, // 向前删除 → FORWARD_DEL
            53: back, // Esc → 返回
            123: 21, 124: 22, 125: 20, 126: 19, // 方向键 左右下上
            115: 122, 119: 123, // Home / End
            116: 92, 121: 93,   // Page Up / Page Down
            43: 55,  // ,
            47: 56,  // .
            50: 68,  // `
            27: 69,  // -
            24: 70,  // =
            33: 71,  // [
            30: 72,  // ]
            42: 73,  // \
            41: 74,  // ;
            39: 75,  // '
            44: 76,  // /
        ]
        for (code, value) in others { map[code] = value }
        return map
    }()
}
