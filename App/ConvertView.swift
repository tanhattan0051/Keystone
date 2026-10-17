// ConvertView.swift — "Công cụ chuyển mã" (design spec Part 2 §2.3 / Part C §4).
//
// Converts between code tables and applies a case transform. Both go through
// `ConvertBridge` below, which calls `KeystoneEngine.Converter.convert` — the
// same OutputTable live typing uses. Supported source tables: Unicode, Unicode
// compound and CP1258; any target table is supported. Converting FROM TCVN3 or
// VNI Windows has no confident inverse map yet, so `Converter` returns the
// input unchanged for those two (see Converter.swift).

import SwiftUI
import AppKit
import KeystoneEngine

enum ConvertCaseTransform: String, CaseIterable, Identifiable {
    case none, lower, upper, title, sentence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Giữ nguyên"
        case .lower: return "chữ thường"
        case .upper: return "CHỮ HOA"
        case .title: return "Mỗi Từ Viết Hoa"
        case .sentence: return "Câu Viết Hoa"
        }
    }
}

/// Bridges the UI's case-transform enum to `KeystoneEngine.Converter`, the same
/// module live typing uses so the two never diverge byte-for-byte (spec §2.3).
/// Converter fully supports Unicode ↔ Unicode-compound and Unicode ↔ CP1258,
/// and Unicode → TCVN3 / VNI-Windows; converting *from* TCVN3/VNI-Windows isn't
/// wired yet (no confident inverse map) and returns the input unchanged.
enum ConvertBridge {
    static func convert(_ input: String, from: CodeTable, to: CodeTable, caseTransform: ConvertCaseTransform) -> String {
        Converter.convert(input, from: from, to: to, caseTransform: caseTransform.engine)
    }
}

extension ConvertCaseTransform {
    var engine: KeystoneEngine.CaseTransform {
        switch self {
        case .none: return .none
        case .lower: return .lower
        case .upper: return .upper
        case .title: return .title
        case .sentence: return .sentence
        }
    }
}

struct ConvertView: View {
    @Bindable var model: AppModel

    @State private var sourceText = ""
    @State private var fromTable: CodeTable = .unicode
    @State private var toTable: CodeTable = .tcvn3
    @State private var caseTransform: ConvertCaseTransform = .none
    @State private var didCopy = false

    private var resultText: String {
        ConvertBridge.convert(sourceText, from: fromTable, to: toTable, caseTransform: caseTransform)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("Bảng mã nguồn", selection: $fromTable) {
                    ForEach(CodeTable.allCases) { Text($0.displayName).tag($0) }
                }
                Button {
                    let tmp = fromTable
                    fromTable = toTable
                    toTable = tmp
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help("Đổi chiều bảng mã")
                Picker("Bảng mã đích", selection: $toTable) {
                    ForEach(CodeTable.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Picker("Chữ hoa/thường", selection: $caseTransform) {
                ForEach(ConvertCaseTransform.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("Văn bản nguồn").font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $sourceText)
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            HStack {
                Button("Dán từ Clipboard") {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        sourceText = s
                    }
                }
                Spacer()
                Button(didCopy ? "Đã chép ✓" : "Chép kết quả") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(resultText, forType: .string)
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { didCopy = false }
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Kết quả").font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: .constant(resultText))
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            if fromTable == .tcvn3 || fromTable == .vniWindows {
                Label(
                    "Chuyển TỪ \(fromTable.displayName) chưa hỗ trợ (chỉ chuyển SANG). Hãy để nguồn là Unicode.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 520)
        .navigationTitle("Chuyển mã")
    }
}
