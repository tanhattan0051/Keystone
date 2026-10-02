// MenuBarContent.swift — the MenuBarExtra's menu body.

import SwiftUI
import AppKit
import KeystoneEngine
import KeystoneInput

struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Toggle("Gõ tiếng Việt", isOn: $model.enabled)
                .disabled(!model.accessibilityTrusted)

            Picker("Kiểu gõ", selection: $model.inputMethod) {
                ForEach(InputMethod.allCases) { Text($0.displayName).tag($0) }
            }

            Divider()

            // Live status so you can confirm the tap is actually running.
            if model.accessibilityTrusted {
                Label("Accessibility: đã cấp", systemImage: "checkmark.seal.fill")
                if model.tapRunning {
                    if model.secureInputActive {
                        // The tap is blind while Secure Input is on, so the
                        // usual "Đang gõ…" line would be misleading.
                        Label(SecureInputTracker.statusMessage(holder: model.secureInputHolder),
                              systemImage: "lock.fill")
                    } else {
                        Label(model.enabled ? "Đang gõ tiếng Việt" : "Đang tạm tắt (EN)",
                              systemImage: model.enabled ? "keyboard.fill" : "keyboard")
                    }
                } else if model.needsRelaunch {
                    Label("Cần khởi động lại để nhận quyền", systemImage: "exclamationmark.triangle.fill")
                    Button("Khởi động lại Keystone") { model.relaunch() }
                } else {
                    Label("Đang khởi động bộ gõ…", systemImage: "hourglass")
                }
            } else {
                Text("Chưa cấp quyền Accessibility")
                Button("Cấp quyền Accessibility…") { model.requestAccessibility() }
            }

            Divider()

            Button("Bảng điều khiển…") { open(WindowID.controlPanel) }
            Button("Công cụ chuyển mã…") { open(WindowID.convert) }
            Button("Gõ tắt…") { open(WindowID.macros) }
            Button("Hướng dẫn cấp quyền…") { open(WindowID.onboarding) }

            Divider()

            Button("Thoát Keystone") { model.quit() }
                .keyboardShortcut("q")
        }
        .onAppear {
            // Registered here (not in AppDelegate/bootstrap()) because
            // `openWindow` only exists inside the SwiftUI environment. This
            // view is the MenuBarExtra's content, so its `onAppear` is the
            // first point after the scene exists where we can wire it up.
            model.openWindowRequest = { id in openWindow(id: id) }
            model.performLaunchOpenIfNeeded()
        }
    }

    /// An `.accessory` app can't reliably bring a window forward without
    /// self-activating first (design spec Part C §2.3).
    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
