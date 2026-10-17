// MacrosView.swift — "Gõ tắt" editor window (design spec Part 2 §2.2 "Gõ tắt"
// tab / Part C §3). UI + storage: `MacroStore` owns the persisted list and
// pushes it into EngineConfig; the engine expands macros (Engine.finalize in
// Vietnamese mode, processInactive in English mode).

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os
import KeystoneEngine

struct Macro: Identifiable, Codable, Hashable {
    var id = UUID()
    var trigger: String = ""
    var replacement: String = ""
    var enabled: Bool = true
    /// "Gõ tắt cả khi tắt tiếng Việt" — expand even when Vietnamese input is off.
    var expandInEnglishMode: Bool = false
    /// "Tự động viết hoa dòng đầu câu" — capitalize the replacement's first
    /// letter at a sentence start (also needs AppModel's global toggle on).
    var autoCapitalize: Bool = false

    /// Explicit keys (same names the synthesized coder used) so the encoded
    /// output is unchanged and old macros.json files / exports round-trip.
    enum CodingKeys: String, CodingKey {
        case id, trigger, replacement, enabled, expandInEnglishMode, autoCapitalize
    }

    func toRule() -> MacroRule {
        MacroRule(
            trigger: trigger,
            replacement: replacement,
            enabled: enabled,
            expandInEnglishMode: expandInEnglishMode,
            autoCapitalize: autoCapitalize
        )
    }
}

extension Macro {
    /// Tolerant decoding: every field is optional and falls back to the
    /// property default (a missing `id` gets a fresh UUID), so a file written
    /// by an older/newer build or a hand-edited export still loads instead of
    /// failing the whole list. Lives in an extension to keep the memberwise init.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try c.decodeIfPresent(String.self, forKey: .trigger) ?? trigger
        replacement = try c.decodeIfPresent(String.self, forKey: .replacement) ?? replacement
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        expandInEnglishMode = try c.decodeIfPresent(Bool.self, forKey: .expandInEnglishMode) ?? expandInEnglishMode
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? autoCapitalize
    }
}

enum MacroImportMode { case merge, replace }

enum MacroImportError: LocalizedError {
    case noMacrosFound
    var errorDescription: String? {
        "Không tìm thấy gõ tắt nào trong tệp này."
    }
}

@Observable
@MainActor
final class MacroStore {
    static let shared = MacroStore()
    private static let log = Logger(subsystem: "com.tanta.keystone", category: "MacroStore")

    var macros: [Macro] = []

    /// Vietnamese warning shown at the top of the editor when macros.json
    /// existed but could not be read (nil = all good).
    var loadIssue: String?

    /// True when macros.json is unreadable AND could not be backed up: save()
    /// must not write, or it would destroy the only copy of the user's data.
    private var saveBlocked = false

    /// Notified after every `save()` (success or failure — the in-memory
    /// `macros` list is authoritative regardless), so the app can re-push
    /// the current macro set into `EngineConfig`. Set by `AppModel.bootstrap()`.
    var onChange: (() -> Void)?

    private let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.tanta.keystone", isDirectory: true)
        // Best-effort: if this fails, the later save() write fails and logs there.
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("macros.json")
    }()

    private init() {
        load()
    }

    @discardableResult
    func add() -> Macro {
        let m = Macro(trigger: "vt", replacement: "Việt Nam")
        macros.append(m)
        save()
        return m
    }

    func delete(_ ids: Set<Macro.ID>) {
        macros.removeAll { ids.contains($0.id) }
        save()
    }

    /// A two-way binding into one macro by id, for the Table + inline editor.
    func binding(for id: Macro.ID) -> Binding<Macro>? {
        guard let initial = macros.first(where: { $0.id == id }) else { return nil }
        // The index is re-resolved by id on every access: the list can shrink
        // or reorder (delete, import) while a binding is still alive.
        var lastKnown = initial
        return Binding(
            get: {
                if let current = self.macros.first(where: { $0.id == id }) {
                    lastKnown = current
                }
                return lastKnown
            },
            set: { newValue in
                guard let idx = self.macros.firstIndex(where: { $0.id == id }) else { return }
                self.macros[idx] = newValue
                self.save()
            }
        )
    }

    func load() {
        // First run: no file yet is normal, not an error.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            macros = try JSONDecoder().decode([Macro].self, from: data)
        } catch {
            Self.log.error("load macros failed (\(self.fileURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            preserveUnreadableFile()
        }
    }

    /// The existing macros.json could not be read. Copy it (never move or
    /// delete the original) to a timestamped sibling so a later save() of the
    /// empty in-memory list cannot lose the user's data. If even the copy
    /// fails, block saving so the original stays untouched.
    private func preserveUnreadableFile() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupName = "macros.json.unreadable-\(formatter.string(from: Date()))"
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
        do {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            Self.log.error("backed up unreadable macros file to \(backupURL.path, privacy: .public)")
            loadIssue = "Không đọc được tệp gõ tắt đã lưu. Bản gốc được giữ lại ở \(backupName) (cùng thư mục dữ liệu của Keystone)."
        } catch {
            saveBlocked = true
            Self.log.error("backup of unreadable macros file failed (\(backupURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public); saving is disabled")
            loadIssue = "Không đọc được tệp gõ tắt đã lưu và không sao lưu được: thay đổi sẽ không được lưu."
        }
    }

    func save() {
        if saveBlocked {
            Self.log.error("save macros skipped: macros.json is unreadable and could not be backed up (\(self.fileURL.path, privacy: .public))")
        } else {
            do {
                let data = try JSONEncoder().encode(macros)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Self.log.error("save macros failed (\(self.fileURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }
        onChange?()
    }

    /// Read a macro file WITHOUT touching the list. Accepts our own JSON
    /// export (JSON tried first, tolerant decoding) or a text file: OpenKey's
    /// `name:content` export or the legacy tab-separated format (UTF-8, or
    /// UTF-16 when the data starts with a UTF-16 BOM). Throws when no usable
    /// macro is found so a bad file can never wipe or change the list.
    func parseImportFile(_ url: URL) throws -> [MacroRule] {
        let data = try Data(contentsOf: url)
        let jsonError: Error
        do {
            let rules = try JSONDecoder().decode([Macro].self, from: data).map { $0.toRule() }
            if !rules.isEmpty { return rules }
            jsonError = MacroImportError.noMacrosFound
        } catch {
            jsonError = error
        }
        // Valid JSON that was merely empty: nothing to import.
        if jsonError is MacroImportError { throw jsonError }
        guard let text = Self.decodeText(data) else { throw jsonError }
        let rules = MacroTable.parseLegacyText(text)
        guard !rules.isEmpty else { throw MacroImportError.noMacrosFound }
        return rules
    }

    private static func decodeText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let isUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        return isUTF16BOM ? String(data: data, encoding: .utf16) : nil
    }

    /// Apply parsed rules. `.merge` keeps existing macros and skips triggers
    /// already present (like OpenKey); `.replace` dedupes the incoming rules
    /// and swaps the whole list. Imported macros always get fresh UUIDs so
    /// re-importing our own export cannot create duplicate ids in the Table.
    @discardableResult
    func applyImport(_ rules: [MacroRule], mode: MacroImportMode) -> (added: Int, skipped: Int) {
        let existing: Set<String> = mode == .merge ? Set(macros.map(\.trigger)) : []
        let result = MacroTable.rulesToAdd(rules, existingTriggers: existing)
        let fresh = result.toAdd.map { rule in
            Macro(
                trigger: rule.trigger,
                replacement: rule.replacement,
                enabled: rule.enabled,
                expandInEnglishMode: rule.expandInEnglishMode,
                autoCapitalize: rule.autoCapitalize
            )
        }
        switch mode {
        case .merge: macros.append(contentsOf: fresh)
        case .replace: macros = fresh
        }
        save()
        return (fresh.count, result.skippedDuplicates)
    }

    func exportFile(to url: URL) throws {
        let data = try JSONEncoder().encode(macros)
        try data.write(to: url, options: .atomic)
    }
}

struct MacrosView: View {
    @Bindable var store: MacroStore
    @State private var selection: Set<Macro.ID> = []
    @State private var query = ""

    private var filtered: [Macro] {
        guard !query.isEmpty else { return store.macros }
        return store.macros.filter {
            $0.trigger.localizedCaseInsensitiveContains(query)
                || $0.replacement.localizedCaseInsensitiveContains(query)
        }
    }

    /// Validated against the CURRENT input method; a different method can make
    /// the same trigger valid (e.g. "k2" is fine in VNI).
    private func triggerProblem(for macro: Macro) -> MacroTriggerProblem? {
        MacroTable.triggerProblem(
            macro.trigger,
            inputMethod: AppModel.shared.inputMethod,
            expandInEnglishMode: macro.expandInEnglishMode
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let issue = store.loadIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12))
            }
            Table(filtered, selection: $selection) {
                TableColumn("Bật") { m in
                    if let b = store.binding(for: m.id) {
                        Toggle("", isOn: b.enabled).labelsHidden()
                    }
                }
                .width(40)
                TableColumn("") { m in
                    if triggerProblem(for: m) != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Gõ tắt này sẽ không bao giờ khớp")
                    }
                }
                .width(24)
                TableColumn("Gõ tắt") { m in
                    Text(m.trigger)
                        .foregroundStyle(triggerProblem(for: m) == nil ? .primary : .secondary)
                }
                TableColumn("Nội dung thay thế", value: \.replacement)
                TableColumn("EN") { m in
                    Image(systemName: m.expandInEnglishMode ? "checkmark" : "")
                        .foregroundStyle(.secondary)
                }
                .width(36)
            }
            .searchable(text: $query, prompt: "Tìm gõ tắt")
            // Rows hidden by the filter must not stay selected: the editor
            // would show an invisible row and "−" would delete it.
            .onChange(of: query) {
                selection.formIntersection(filtered.map(\.id))
            }

            Divider()

            if let id = selection.first, let binding = store.binding(for: id) {
                MacroEditor(
                    macro: binding,
                    problem: triggerProblem(for: binding.wrappedValue)
                )
                    .padding()
                    .background(.regularMaterial)
            } else {
                Text("Chọn một dòng để chỉnh sửa, hoặc bấm + để thêm gõ tắt mới.")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    let m = store.add()
                    selection = [m.id]
                } label: {
                    Image(systemName: "plus")
                }
                .help("Thêm gõ tắt")

                Button {
                    // Belt and braces with the onChange above: only ever
                    // delete rows the user can currently see.
                    let visibleSelected = selection.intersection(filtered.map(\.id))
                    store.delete(visibleSelected)
                    selection.subtract(visibleSelected)
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                .help("Xoá gõ tắt đã chọn")

                Spacer()

                Menu {
                    Button("Nhập gõ tắt (OpenKey .txt hoặc JSON)…") { importMacros() }
                    Button("Xuất ra JSON…") { exportJSON() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .frame(minWidth: 620, minHeight: 440)
        .navigationTitle("Gõ tắt")
    }

    /// Import flow: pick a file, parse it (errors are reported and the list is
    /// left untouched), then merge directly when the list is empty or ask
    /// merge / replace / cancel. Accepts our JSON export, OpenKey's `.txt`
    /// export, and the legacy tab-separated format.
    private func importMacros() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let rules: [MacroRule]
        do {
            rules = try store.parseImportFile(url)
        } catch {
            reportError("Không nhập được gõ tắt từ tệp này", error)
            return
        }

        let mode: MacroImportMode
        if store.macros.isEmpty {
            mode = .merge
        } else {
            let ask = NSAlert()
            ask.messageText = "Nhập \(rules.count) gõ tắt"
            ask.informativeText = "Gộp: giữ gõ tắt hiện có, bỏ qua gõ tắt trùng tên (giống OpenKey). Thay thế: xoá toàn bộ \(store.macros.count) gõ tắt hiện có rồi nhập mới."
            ask.addButton(withTitle: "Gộp")
            ask.addButton(withTitle: "Thay thế toàn bộ")
            ask.addButton(withTitle: "Huỷ")
            switch ask.runModal() {
            case .alertFirstButtonReturn: mode = .merge
            case .alertSecondButtonReturn: mode = .replace
            default: return
            }
        }

        let result = store.applyImport(rules, mode: mode)
        let done = NSAlert()
        done.messageText = "Đã thêm \(result.added) gõ tắt, bỏ qua \(result.skipped) gõ tắt trùng."
        done.alertStyle = .informational
        done.runModal()
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "keystone-macros.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportFile(to: url)
        } catch {
            reportError("Không xuất được gõ tắt", error)
        }
    }

    /// Surface a file-operation failure to the user instead of swallowing it.
    private func reportError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct MacroEditor: View {
    @Binding var macro: Macro
    /// Why the trigger can never fire (nil = fine). Informational only: the
    /// user may be mid-edit, so saving is never blocked.
    let problem: MacroTriggerProblem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sửa gõ tắt").font(.headline)
            HStack {
                TextField("Gõ tắt (vd: vn)", text: $macro.trigger)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                TextField("Nội dung (vd: Việt Nam)", text: $macro.replacement)
                    .textFieldStyle(.roundedBorder)
            }
            if let problem {
                Text(problem.message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 20) {
                Toggle("Bật", isOn: $macro.enabled)
                Toggle("Mở rộng cả khi tắt tiếng Việt", isOn: $macro.expandInEnglishMode)
                Toggle("Tự động viết hoa dòng đầu câu", isOn: $macro.autoCapitalize)
            }
        }
    }
}
