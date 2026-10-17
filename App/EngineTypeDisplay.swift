// EngineTypeDisplay.swift — UI-facing display names for KeystoneEngine's
// value types, plus the `CaseIterable`/`Identifiable` conformances the
// pickers and `ForEach` loops need. Kept here (App-side, retroactive
// conformance) rather than in Sources/ so the engine module stays free of
// UI concerns.

import KeystoneEngine

extension InputMethod: CaseIterable, Identifiable {
    public static var allCases: [InputMethod] { [.telex, .vni, .simpleTelex1, .simpleTelex2] }
    public var id: String { rawValue }

    /// Label text, matching OpenKey's menu wording (design spec §2.1).
    var displayName: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .simpleTelex1: return "Simple Telex 1"
        case .simpleTelex2: return "Simple Telex 2"
        }
    }

    /// The engine has no Simple Telex rules yet (nothing in KeystoneEngine
    /// branches on these cases), so both run exactly like Telex. The UI says
    /// so rather than implying a behaviour that does not exist.
    var behavesAsTelex: Bool {
        switch self {
        case .simpleTelex1, .simpleTelex2: return true
        case .telex, .vni: return false
        }
    }

    /// Short honesty note shown next to the method name; nil when the method
    /// does what its name says.
    var displayCaption: String? {
        behavesAsTelex ? "(đang chạy như Telex)" : nil
    }

    /// Picker item label: name plus the caption when there is one.
    var pickerLabel: String {
        guard let caption = displayCaption else { return displayName }
        return "\(displayName) \(caption)"
    }
}

extension CodeTable: CaseIterable, Identifiable {
    public static var allCases: [CodeTable] { [.unicode, .tcvn3, .vniWindows, .unicodeCompound, .cp1258] }
    public var id: String { rawValue }

    /// Label text, matching OpenKey's menu wording (design spec §2.1).
    var displayName: String {
        switch self {
        case .unicode: return "Unicode dựng sẵn"
        case .tcvn3: return "TCVN3 (ABC)"
        case .vniWindows: return "VNI Windows"
        case .unicodeCompound: return "Unicode tổ hợp"
        case .cp1258: return "Vietnamese Locale CP1258"
        }
    }
}
