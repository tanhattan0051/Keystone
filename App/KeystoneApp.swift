// KeystoneApp.swift — app entry point.
//
// A menu-bar-first ("agent") app: no main window, and no Dock icon unless the
// user opted into one ("Hiện icon trên Dock" — AppModel.showDockIcon). The
// activation policy is set as soon as the app finishes launching, and the
// entire UI lives in the MenuBarExtra's menu plus the Window scenes below.

import SwiftUI
import AppKit

/// Stable ids for the app's `Window` scenes, used with `openWindow(id:)`.
enum WindowID {
    static let controlPanel = "control-panel"
    static let convert = "convert"
    static let macros = "macros"
    static let onboarding = "onboarding"
}

@main
struct KeystoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @State private var macroStore = MacroStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        // Note: `.defaultLaunchBehavior(.suppressed)` (macOS 15+) would keep
        // these closed at launch, but the deployment target here is macOS 14,
        // so it's omitted — these windows simply aren't opened until the menu
        // bar asks for them, which has the same effect.

        Window("Bảng điều khiển", id: WindowID.controlPanel) {
            ControlPanel(model: model)
        }
        .windowResizability(.contentSize)

        Window("Chuyển mã", id: WindowID.convert) {
            ConvertView(model: model)
        }
        .windowResizability(.contentSize)

        Window("Gõ tắt", id: WindowID.macros) {
            MacrosView(store: macroStore)
        }
        .windowResizability(.contentSize)

        Window("Chào mừng", id: WindowID.onboarding) {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// The menu-bar icon. Unlike the menu's *content* (whose `onAppear` only
/// fires when the menu is first opened), the label is rendered at launch —
/// so it's the reliable point to register `openWindowRequest` and drive the
/// launch-open (onboarding on first run, else "Bật bảng này khi khởi động").
private struct MenuBarLabel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // "V" khi đang gõ tiếng Việt, "E" khi đang ở chế độ tiếng Anh — cho
        // thấy ngay chế độ hiện tại ngay trên menu bar. Khi macOS đang bật
        // nhập bảo mật (Secure Input) thì bộ gõ không nhận được phím nào, nên
        // hiện ổ khoá thay cho V/E. `.onAppear` gắn lên cả Group nên nhánh nào
        // hiện ra cũng có nó; hai việc bên trong đều chạy một-lần/idempotent
        // (performLaunchOpenIfNeeded có cờ didAttemptLaunchOpen).
        Group {
            if model.secureInputActive {
                Image(systemName: "lock.fill")
            } else {
                Text(model.enabled ? "V" : "E")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .onAppear {
            model.openWindowRequest = { id in openWindow(id: id) }
            model.performLaunchOpenIfNeeded()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // One Keystone per user — a second copy would double-tap every key.
        guard SingleInstance.acquire() else {
            let alert = NSAlert()
            alert.messageText = "Keystone đã đang chạy"
            alert.informativeText = "Đã có một bản Keystone đang chạy trên tài khoản này. "
                + "Bản vừa mở sẽ thoát để tránh gõ bị nhân đôi."
            alert.alertStyle = .warning
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        // Honor the saved "Hiện icon trên Dock" setting instead of always
        // hiding the Dock tile — see AppModel.showDockIcon.
        NSApp.setActivationPolicy(AppModel.shared.showDockIcon ? .regular : .accessory)
        AppModel.shared.bootstrap()
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}
