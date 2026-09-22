// AppModel.swift — owns the engine controller and the live event tap, and is
// also the app's settings store: every user-facing preference from the
// Control Panel / menu bar lives here as a persisted `@Observable` property.
// Everything here runs on the main actor; the tap itself runs its own
// dedicated thread inside KeystoneInput.
//
// Two tiers of properties:
//  - The "mapped" group (inputMethod, codeTable, orthography, quickTelex,
//    restoreIfInvalid, macrosEnabled, macrosExpandWhenVietnameseOff,
//    macroAutoCapitalize, quickStartConsonant, quickEndConsonant,
//    autoCapitalize, allowFreeToneMark, freeMarkAcrossCoda,
//    literalAfterCancel) is pushed into
//    `EngineConfig` on every change and reaches the running tap via
//    `EngineController.updateConfig`.
//  - Everything else is scaffolding: real UI, real persistence, but no
//    engine behavior yet (`EngineConfig` doesn't have a field for it). Each
//    one is marked `// TODO: wire to engine`.
//  - `useLexicon` is neither: real engine behavior (gates
//    `EngineController.setLexicon`, alongside `restoreIfInvalid`), but
//    deliberately NOT pushed through `EngineConfig` — see `Engine.lexicon`'s
//    doc comment and DECISIONS.md for why.

import SwiftUI
import AppKit
import Observation
import os
import ServiceManagement
import KeystoneEngine
import KeystoneInput

private extension ModifierSet {
    /// Maps AppKit's modifier flags to the platform-neutral `ModifierSet`
    /// that `SwitchKeyDetector` (KeystoneInput) works with.
    init(nsEventFlags flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    private static let log = Logger(subsystem: "com.tanta.keystone", category: "AppModel")

    // MARK: - Enable / input method (existing, tap-wired)

    var enabled = true {
        didSet {
            controller.setActive(enabled)
            persistPerAppStateIfNeeded()
        }
    }
    var inputMethod: InputMethod = AppModel.loadRaw(Keys.inputMethod, default: .telex) {
        didSet {
            UserDefaults.standard.set(inputMethod.rawValue, forKey: Keys.inputMethod)
            pushConfig()
        }
    }

    // MARK: - Mapped group — pushed into EngineConfig

    /// Output code table. App default is **Unicode dựng sẵn** (`.unicode`, NFC
    /// precomposed): 1 code-unit per grapheme, so the tap's `backspaceCount`
    /// (counted in code units) always matches how apps delete a grapheme per
    /// Delete — the double-char/backspace-safe choice across apps (design spec
    /// E.2/E.3).
    ///
    /// `.unicodeCompound` ("Unicode tổ hợp", combining diacritics) spells one
    /// grapheme as base + combining mark(s) — 2-3 code units — so on a restore
    /// or diacritic edit the code-unit backspace count can under- or over-delete
    /// in apps that delete a whole grapheme per Delete, dropping or duplicating
    /// a character. It stays available in the Control Panel for legacy software
    /// that needs decomposed Unicode, but must NOT be the default.
    /// See DECISIONS.md "Bảng mã".
    var codeTable: CodeTable = AppModel.loadRaw(Keys.codeTable, default: .unicode) {
        didSet {
            // Persist to the GLOBAL default only on a real (manual) change, not
            // while applying a per-app restore — otherwise a remembered per-app
            // table silently overwrites the user's chosen startup default (the
            // leak path that let a transient default stick across launches).
            // Per-app values live in appstates.json via persistPerAppStateIfNeeded,
            // which is guarded by the same flag. pushConfig always runs so the
            // engine reflects the (restored or manual) table immediately.
            if !applyingPerAppState {
                UserDefaults.standard.set(codeTable.rawValue, forKey: Keys.codeTable)
            }
            pushConfig()
            persistPerAppStateIfNeeded()
        }
    }

    var orthography: Orthography = AppModel.loadRaw(Keys.orthography, default: .modern) {
        didSet {
            UserDefaults.standard.set(orthography.rawValue, forKey: Keys.orthography)
            pushConfig()
        }
    }

    /// UI-facing toggle for "Đặt dấu oà, uý (thay vì òa, úy)" — ON means
    /// classic tone placement. `orthography` stays the single source of
    /// truth; this just gives Control Panel a plain Bool to bind to.
    var useClassicToneMarks: Bool {
        get { orthography == .classic }
        set { orthography = newValue ? .classic : .modern }
    }

    /// "Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th)"
    var quickTelex: Bool = AppModel.loadBool(Keys.quickTelex, default: false) {
        didSet {
            UserDefaults.standard.set(quickTelex, forKey: Keys.quickTelex)
            pushConfig()
        }
    }

    /// "Tự khôi phục phím với từ sai" — default ON: at commit, a composed word
    /// that is not a legal Vietnamese syllable reverts to its raw keystrokes.
    /// This is the "auto-drop the diacritic when the word doesn't need one"
    /// behavior: an English/informal word transformed by Telex (`hehe`→hêh,
    /// `task`→ták) is invalid, so it reverts to the literal `hehe`/`task`. It
    /// was briefly defaulted OFF while an event-tap duplicate-key-down bug made
    /// the revert edits corrupt (`task`→`tassk`); that bug is fixed (synthetic
    /// events now post via `CGEventPost`, see `TapSink`), so restore is back on.
    var restoreIfInvalid: Bool = AppModel.loadBool(Keys.restoreIfInvalid, default: true) {
        didSet {
            UserDefaults.standard.set(restoreIfInvalid, forKey: Keys.restoreIfInvalid)
            pushConfig()
            updateLexiconLoaded()
        }
    }

    /// "Giữ từ tiếng Anh đang hiển thị (dùng từ điển)" — kill switch for the
    /// lexicon-aware restore feature (see DECISIONS.md "Restore chooses the
    /// composed word when it is the real one"). Default ON. Only meaningful
    /// while `restoreIfInvalid` is also on — the Control Panel greys it out
    /// otherwise (`BasicPane`, mirroring how `macrosExpandWhenVietnameseOff`
    /// is greyed out under `macrosEnabled`). The lexicon (~236k words, see
    /// `updateLexiconLoaded`) is resident ONLY while both this and
    /// `restoreIfInvalid` are on; turning either off frees it.
    var useLexicon: Bool = AppModel.loadBool(Keys.useLexicon, default: true) {
        didSet {
            UserDefaults.standard.set(useLexicon, forKey: Keys.useLexicon)
            updateLexiconLoaded()
        }
    }

    /// "Cho phép bỏ dấu tự do" (design spec Part A §4 — free tone-mark
    /// placement). Gates the engine's non-adjacent quality-mark/đ placement
    /// (see DECISIONS.md "Positional (non-adjacent) marks"). Defaults to true
    /// to preserve the engine's existing behavior for users upgrading in.
    var allowFreeToneMark: Bool = AppModel.loadBool(Keys.allowFreeToneMark, default: true) {
        didSet {
            UserDefaults.standard.set(allowFreeToneMark, forKey: Keys.allowFreeToneMark)
            pushConfig()
        }
    }

    /// "Bỏ dấu ở cuối từ (kể cả sau phụ âm)" (Phase 4) — extends
    /// `allowFreeToneMark` so a Telex quality mark (circumflex/horn/breve) can
    /// land across a consonant coda onto an earlier vowel, and Telex/VNI đ can
    /// stroke a still-open syllable's onset d (see DECISIONS.md
    /// "Bỏ dấu ở cuối từ / freeMarkAcrossCoda (Phase 4)").
    ///
    /// Default **ON** (the author's "bỏ dấu ở cuối" input style — `tana`→tân,
    /// `dadng`→đang): a quality mark (circumflex/horn/breve) may land across a
    /// consonant coda onto an earlier vowel. Accepted tradeoff: an English/
    /// informal word with the same V-C-V shape also transforms (`hehe`→hêh,
    /// `mama`→mâm) — the engine cannot tell it apart from `tana`→tân without a
    /// dictionary. The clean way to keep BOTH (free-mark style AND `hehe`
    /// literal) is to re-enable `restoreIfInvalid`, which reverts the invalid
    /// `hêh` back to raw `hehe`; that path is currently off pending the
    /// event-tap duplicate-keydown fix (see DECISIONS.md). `EngineConfig`
    /// still defaults it false so the corpus keeps the English-safe behavior.
    var freeMarkAcrossCoda: Bool = AppModel.loadBool(Keys.freeMarkAcrossCoda, default: true) {
        didSet {
            UserDefaults.standard.set(freeMarkAcrossCoda, forKey: Keys.freeMarkAcrossCoda)
            pushConfig()
        }
    }

    /// "Huỷ dấu xong thì gõ tiếp chữ thường" (Phase 6, OpenKey-compatible
    /// cancel semantics) — see DECISIONS.md "OpenKey-compatible
    /// literal-after-cancel (Phase 6)". Once the standard Telex/VNI same-key
    /// double-strike CANCELS a tone/mark, every later key of that word types
    /// literally instead of toggling the transform back on.
    ///
    /// Default **ON**: matches the author's OpenKey habit (press the tone/
    /// mark key twice to cancel, then keep typing — `classs`→class,
    /// `tassk`→task). `EngineConfig` still defaults it false so the engine/
    /// test level stays untouched until the app turns it on, same pattern as
    /// `freeMarkAcrossCoda`.
    var literalAfterCancel: Bool = AppModel.loadBool(Keys.literalAfterCancel, default: true) {
        didSet {
            UserDefaults.standard.set(literalAfterCancel, forKey: Keys.literalAfterCancel)
            pushConfig()
        }
    }

    /// "Kiểm tra chính tả" (Phase 7, eager restore) — see DECISIONS.md
    /// "Eager restore (spellCheck / Phase 7)". While typing, as soon as the
    /// composing word becomes a Vietnamese syllable that can NEVER become
    /// valid again (dead, not merely "currently invalid" — see `Engine`'s
    /// private `isUnrecoverable(_:)`), the raw keystrokes render literally
    /// instead of flashing pseudo-Vietnamese: `docker`/`vmware`/`faster` show
    /// as themselves as you type, not only at the word boundary.
    ///
    /// Default **ON**: an earlier, stricter companion to `restoreIfInvalid`'s
    /// existing word-boundary revert. `EngineConfig` still defaults it false
    /// so the engine/test level stays untouched until the app turns it on,
    /// same pattern as `freeMarkAcrossCoda`/`literalAfterCancel`.
    var spellCheck: Bool = AppModel.loadBool(Keys.spellCheck, default: true) {
        didSet {
            UserDefaults.standard.set(spellCheck, forKey: Keys.spellCheck)
            pushConfig()
        }
    }

    // MARK: - Scaffolding — persisted, displayed, not yet in EngineConfig

    /// "Viết Hoa chữ cái đầu câu". Default OFF — sentence-start detection in
    /// a system-wide IME is unreliable (see DECISIONS.md "Quick consonants &
    /// auto-capitalize"), so this ships dormant like the other Phase 4 flags.
    var autoCapitalize: Bool = AppModel.loadBool(Keys.autoCapitalize, default: false) {
        didSet {
            UserDefaults.standard.set(autoCapitalize, forKey: Keys.autoCapitalize)
            pushConfig()
        }
    }

    /// "Gõ tắt phụ âm đầu: f→ph, j→gi, w→qu"
    var quickStartConsonant: Bool = AppModel.loadBool(Keys.quickStartConsonant, default: false) {
        didSet {
            UserDefaults.standard.set(quickStartConsonant, forKey: Keys.quickStartConsonant)
            pushConfig()
        }
    }

    /// "Gõ tắt phụ âm cuối: g→ng, h→nh, k→ch"
    var quickEndConsonant: Bool = AppModel.loadBool(Keys.quickEndConsonant, default: false) {
        didSet {
            UserDefaults.standard.set(quickEndConsonant, forKey: Keys.quickEndConsonant)
            pushConfig()
        }
    }

    /// "Chuyển chế độ thông minh" (smart switch on app change)
    // TODO: wire to engine/input layer (design spec Part B/C, E.7).
    var smartSwitch: Bool = AppModel.loadBool(Keys.smartSwitch, default: true) {
        didSet { UserDefaults.standard.set(smartSwitch, forKey: Keys.smartSwitch) }
    }

    /// "Tự ghi nhớ bảng mã theo ứng dụng"
    // TODO: wire to engine/input layer (per-bundle-id remembered code table).
    var rememberCodePerApp: Bool = AppModel.loadBool(Keys.rememberCodePerApp, default: true) {
        didSet { UserDefaults.standard.set(rememberCodePerApp, forKey: Keys.rememberCodePerApp) }
    }

    /// "Sửa lỗi gợi ý (trình duyệt, Excel,...)" — when ON, posts the composed
    /// Unicode string on the synthetic keyDown only (the anti-double-char
    /// remedy for browsers/Excel). Default OFF: both keyDown+keyUp carry the
    /// string, unchanged from the tap's original behavior (design spec E.2/E.3).
    var autoFixSuggestion: Bool = AppModel.loadBool(Keys.autoFixSuggestion, default: false) {
        didSet {
            UserDefaults.standard.set(autoFixSuggestion, forKey: Keys.autoFixSuggestion)
            pushInputBehavior()
        }
    }

    /// "Gửi từng phím (bật nếu bị lỗi)" — per-grapheme send fallback for apps
    /// that mishandle multi-char Unicode insertions (design spec E.3).
    var sendEachKeystroke: Bool = AppModel.loadBool(Keys.sendEachKeystroke, default: false) {
        didSet {
            UserDefaults.standard.set(sendEachKeystroke, forKey: Keys.sendEachKeystroke)
            pushInputBehavior()
        }
    }

    /// "Phím chuyển" — the recorded combo itself (modifiers, optionally plus
    /// one key). JSON-encoded under a NEW UserDefaults key; on first launch
    /// after upgrading (that key absent) this and `switchKeyEnabled` are both
    /// seeded from the legacy `SwitchKeyModifier` raw string via
    /// `SwitchHotKey.migrateLegacy`. See `AppModel.loadSwitchHotKeyState()`.
    var switchHotKey: SwitchHotKey = AppModel.loadSwitchHotKeyState().hotKey {
        didSet {
            // Persisting happens inside `applySwitchHotKeyRegistration()`
            // itself, ONLY once a combo is actually applied (valid, and —
            // for a modifier+key combo — successfully registered with
            // Carbon). An in-progress invalid or unregistrable draft must
            // never overwrite the last combo that really works, or a
            // relaunch mid-edit would lose it. See DECISIONS.md.
            applySwitchHotKeyRegistration()
        }
    }

    /// "Bật phím chuyển" — master on/off, independent of the SwitchKeyModifier
    /// enum's old `.off` case (which conflated "off" with "which combo to
    /// remember for next time").
    var switchKeyEnabled: Bool = AppModel.loadSwitchHotKeyState().isEnabled {
        didSet {
            UserDefaults.standard.set(switchKeyEnabled, forKey: Keys.switchKeyEnabled)
            applySwitchHotKeyRegistration()
        }
    }

    /// "Kêu bíp khi chuyển" — default OFF (silent toggle, matching the
    /// feature's original behavior; this is purely an opt-in audible cue).
    var switchKeyBeep: Bool = AppModel.loadBool(Keys.switchKeyBeep, default: false) {
        didSet { UserDefaults.standard.set(switchKeyBeep, forKey: Keys.switchKeyBeep) }
    }

    /// Vietnamese message for the red caption in the Control Panel: either
    /// `switchHotKey.validationError` (an illegal combo — nothing was
    /// applied) or a Carbon `RegisterEventHotKey` failure (a legal combo the
    /// OS/another app already claimed). `nil` once the live combo matches
    /// `switchHotKey`/`switchKeyEnabled` with no error. Set only from
    /// `applySwitchHotKeyRegistration()`.
    private(set) var switchKeyError: String?

    /// The combo actually live right now — set only when
    /// `applySwitchHotKeyRegistration()` successfully applies `switchHotKey`
    /// (modifier-only, or a Carbon-registered modifier+key combo); `nil`
    /// while disabled. Distinct from `switchHotKey` itself, which is the
    /// in-progress draft the Control Panel edits and may be temporarily
    /// invalid or fail to register — read by its "Tổ hợp hiện tại" caption so
    /// a bad draft never hides a hot key that is still actually live.
    private(set) var appliedSwitchHotKey: SwitchHotKey?

    /// "Cho phép gõ tắt" (Gõ tắt tab)
    var macrosEnabled: Bool = AppModel.loadBool(Keys.macrosEnabled, default: false) {
        didSet {
            UserDefaults.standard.set(macrosEnabled, forKey: Keys.macrosEnabled)
            pushConfig()
        }
    }

    /// "Gõ tắt cả khi tắt tiếng Việt"
    var macrosExpandWhenVietnameseOff: Bool = AppModel.loadBool(Keys.macrosExpandWhenVietnameseOff, default: false) {
        didSet {
            UserDefaults.standard.set(macrosExpandWhenVietnameseOff, forKey: Keys.macrosExpandWhenVietnameseOff)
            pushConfig()
        }
    }

    /// "Tự động viết hoa" (macro-triggered capitalization, Gõ tắt tab)
    var macroAutoCapitalize: Bool = AppModel.loadBool(Keys.macroAutoCapitalize, default: true) {
        didSet {
            UserDefaults.standard.set(macroAutoCapitalize, forKey: Keys.macroAutoCapitalize)
            pushConfig()
        }
    }

    /// "Khởi động cùng macOS" — backed by `SMAppService.mainApp`. `didSet`
    /// registers/unregisters the login item; `isSyncingLoginItem` guards the
    /// revert-on-failure and launch-time reconciliation below from re-entering
    /// this same `didSet` and issuing a redundant register/unregister call.
    var runAtLogin: Bool = AppModel.loadBool(Keys.runAtLogin, default: false) {
        didSet {
            UserDefaults.standard.set(runAtLogin, forKey: Keys.runAtLogin)
            guard !isSyncingLoginItem else { return }
            do {
                if runAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Self.log.error("SMAppService \(self.runAtLogin ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                // The OS call failed, so the toggle would otherwise misreport
                // reality — revert it. Guard re-entrancy so this assignment
                // doesn't loop back into another register/unregister attempt.
                isSyncingLoginItem = true
                runAtLogin.toggle()
                isSyncingLoginItem = false
            }
        }
    }

    /// "Bật bảng này khi khởi động" — open the Control Panel at launch. The
    /// actual opening happens via `openControlPanelRequest`, set once the
    /// SwiftUI scene exists (see `performLaunchOpenIfNeeded()`); `openWindow`
    /// isn't available from `AppDelegate`/`bootstrap()`.
    var openControlPanelAtLaunch: Bool = AppModel.loadBool(Keys.openControlPanelAtLaunch, default: false) {
        didSet { UserDefaults.standard.set(openControlPanelAtLaunch, forKey: Keys.openControlPanelAtLaunch) }
    }

    /// Whether the onboarding window has already been dismissed once (via its
    /// footer button, "Bắt đầu gõ"/"Để sau") — either way counts as finished,
    /// per the spec's "never trap the user". Drives `needsOnboarding` below so
    /// the window only auto-opens at launch until the user has seen it once.
    var didFinishOnboarding: Bool = AppModel.loadBool(Keys.didFinishOnboarding, default: false) {
        didSet { UserDefaults.standard.set(didFinishOnboarding, forKey: Keys.didFinishOnboarding) }
    }

    /// "Kiểm tra bản mới khi khởi động"
    var checkForUpdates: Bool = AppModel.loadBool(Keys.checkForUpdates, default: true) {
        didSet { UserDefaults.standard.set(checkForUpdates, forKey: Keys.checkForUpdates) }
    }

    /// "Hiện icon trên Dock"
    var showDockIcon: Bool = AppModel.loadBool(Keys.showDockIcon, default: false) {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: Keys.showDockIcon)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
            if showDockIcon {
                // Without this, turning the toggle on leaves the new Dock
                // tile present but unfocused until the user clicks something.
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Closure the SwiftUI layer registers once the `MenuBarExtra` scene
    /// exists, since `openWindow` is only available in that environment (not
    /// in `AppDelegate`/`bootstrap()`). Takes a `WindowID` string. Invoked by
    /// `performLaunchOpenIfNeeded()`.
    var openWindowRequest: ((String) -> Void)?

    // MARK: - Permission / tap status (existing)

    private(set) var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private(set) var inputMonitoring = Permissions.inputMonitoringGranted()
    private(set) var tapRunning = false
    /// Trusted + we tried to start the tap, but it isn't live — macOS often
    /// only honors a fresh Accessibility grant after the process relaunches.
    private(set) var needsRelaunch = false

    /// True until Accessibility is trusted (the hard requirement for the tap)
    /// or the user has explicitly finished/dismissed onboarding once — drives
    /// the auto-open-at-launch behavior in `performLaunchOpenIfNeeded()`.
    var needsOnboarding: Bool { !accessibilityTrusted && !didFinishOnboarding }

    private let controller: EngineController
    private let tap: EventTapController
    private var statusTimer: Timer?
    private var tapStarted = false
    private var startAttempts = 0
    private var appSwitchObserver: NSObjectProtocol?

    // MARK: - Phím chuyển (switch-language hot key, Phase 4/7)

    /// Pure modifier-only chord detector — fed by the `NSEvent` monitors
    /// below, deliberately off the CGEventTap hot path (see DECISIONS.md).
    /// Live only while `switchHotKey.key == nil` (modifier-only combo); a
    /// modifier+key combo goes through `hotKeyRegistrar` instead.
    private var switchDetector = SwitchKeyDetector()
    private var switchKeyGlobalMonitor: Any?
    private var switchKeyLocalMonitor: Any?
    /// Carbon `RegisterEventHotKey` wrapper for the modifier+key path — see
    /// `App/SwitchHotKeyRegistrar.swift` and DECISIONS.md "Phím chuyển".
    private let hotKeyRegistrar = SwitchHotKeyRegistrar()

    // MARK: - System toggle bookkeeping (Phase 4)

    /// Set while `runAtLogin` is being corrected programmatically (revert on
    /// register/unregister failure, or launch-time reconciliation against
    /// `SMAppService.mainApp.status`) so that reassignment doesn't re-enter
    /// the `didSet` and issue another register/unregister call.
    private var isSyncingLoginItem = false
    /// `performLaunchOpenIfNeeded()` should only ever act once per launch.
    private var didAttemptLaunchOpen = false

    // MARK: - Smart-switch (per-app state, design spec E.7 / Part C §7)

    /// Bundle id of the app Keystone currently considers "frontmost", tracked
    /// independently of whether smart-switch is on, so turning a toggle on
    /// mid-session immediately has a `currentBundleID` to persist against.
    private var currentBundleID: String?
    /// Set while restoring a remembered state onto `enabled`/`codeTable`, so
    /// the `didSet` persistence hook below doesn't re-learn the state it is
    /// itself in the middle of applying.
    private var applyingPerAppState = false

    /// Either per-app toggle being on means the app-activation handler needs
    /// to track per-app state at all (E.7 covers both independently).
    private var perAppTrackingOn: Bool { smartSwitch || rememberCodePerApp }

    /// The engine-facing state as it stands right now, in the shape
    /// `PerAppStore`/`SmartSwitch` deal in.
    private var currentInputState: AppInputState {
        AppInputState(vietnameseEnabled: enabled, codeTable: codeTable)
    }

    private init() {
        controller = EngineController(config: EngineConfig())
        tap = EventTapController(engine: controller)
        pushConfig()   // push whatever was loaded from UserDefaults above
        updateLexiconLoaded()
    }

    /// A monotonically increasing tag for the most recently REQUESTED
    /// lexicon load — lets a load that finishes after the gate has since
    /// changed again recognize it is stale and discard itself instead of
    /// clobbering newer state (see `updateLexiconLoaded`).
    private var lexiconLoadGeneration = 0

    /// Kill switch + lazy load: the lexicon `restoreIfInvalid`
    /// consults to prefer the composed word over raw keystrokes when it's
    /// the real one (see DECISIONS.md "Restore chooses the composed word
    /// when it is the real one") is resident ONLY while BOTH
    /// `restoreIfInvalid` AND `useLexicon` are on — either one turning off
    /// calls `EngineController.setLexicon(nil)` so the ~236k-entry `Set` can
    /// be freed. Called once at startup and again from both toggles'
    /// `didSet`.
    ///
    /// Loading reads `/usr/share/dict/words` (~236k lines, ~30 MB resident
    /// once built), so it always runs off the MAIN thread
    /// (must never block startup or the UI) and off the TAP thread (
    /// `EngineController.setLexicon` takes the same lock as every keystroke
    /// and must not be held for a file read). The generation check on the
    /// hop back to the main actor discards a load whose gate has since
    /// flipped off again (or on, then off, then on) while it was running.
    private func updateLexiconLoaded() {
        lexiconLoadGeneration += 1
        let generation = lexiconLoadGeneration
        guard restoreIfInvalid && useLexicon else {
            controller.setLexicon(nil)
            return
        }
        let controller = self.controller
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let lexicon = LexiconLoader.load()
            Task { @MainActor [weak self] in
                guard let self, self.lexiconLoadGeneration == generation else { return }
                controller.setLexicon(lexicon)
            }
        }
    }

    func bootstrap() {
        pushInputBehavior()   // push whatever was loaded from UserDefaults above
        reconcileLoginItemStatus()
        hotKeyRegistrar.onHotKeyPressed = { [weak self] in
            // Carbon delivers this on the main run loop, but the closure
            // itself isn't statically @MainActor-isolated — hop the same way
            // the app-activation observer below does, rather than assuming.
            Task { @MainActor in self?.toggleVietnameseFromHotKey() }
        }
        applySwitchHotKeyRegistration()
        installSwitchKeyMonitors()
        // Re-push EngineConfig whenever macros are added/edited/imported, so
        // the running tap picks up the new rules without a restart.
        MacroStore.shared.onChange = { [weak self] in self?.pushConfig() }
        // Reset the composing buffer when the frontmost app changes, and (when
        // smart-switch and/or per-app code table is on) learn/restore that
        // app's input state — all off the hot path (E.7 / §7.1), since this
        // notification observer runs independently of the CGEventTap callback.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Pull the bundle id out here (NSRunningApplication/Notification
            // aren't Sendable) so only a plain String? crosses into the Task.
            let newBundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in self?.handleAppActivation(newBundleID: newBundleID) }
        }
        if !accessibilityTrusted { Permissions.promptAccessibility() }
        refresh()
        // A light status poll: reflects grant + tap health in the menu, and
        // starts the tap the moment Accessibility is granted. Cheap; runs only
        // while the app is up.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // "Kiểm tra bản mới khi khởi động" — a silent background check, off
        // the launch path (never blocks bootstrap()). Errors/no-update cases
        // stay silent; only an actual newer release prompts the user.
        if checkForUpdates {
            Task { @MainActor in Updater.shared.checkForUpdates(userInitiated: false) }
        }
    }

    func shutdown() {
        tap.stop()
        statusTimer?.invalidate()
        if let o = appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let m = switchKeyGlobalMonitor { NSEvent.removeMonitor(m) }
        if let m = switchKeyLocalMonitor { NSEvent.removeMonitor(m) }
        hotKeyRegistrar.unregister()
    }

    func requestAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
    }

    func requestInputMonitoring() {
        Permissions.requestInputMonitoring()
    }

    func openInputMonitoringSettings() {
        Permissions.openInputMonitoringSettings()
    }

    /// Marks onboarding as seen so it stops auto-opening at launch. The
    /// window itself closes via `dismiss()` right after calling this — never
    /// gated on any permission actually being granted (never trap the user).
    func finishOnboarding() {
        didFinishOnboarding = true
    }

    /// Reconciles the persisted `runAtLogin` toggle with `SMAppService`'s
    /// actual status once at launch — e.g. the user removed the login item
    /// via System Settings directly, or a previous register call silently
    /// didn't stick across an app move/reinstall.
    private func reconcileLoginItemStatus() {
        let status = SMAppService.mainApp.status
        let actual: Bool
        switch status {
        case .enabled:
            actual = true
        case .notRegistered, .notFound:
            actual = false
        case .requiresApproval:
            // Registered but pending the user's approval in System Settings —
            // leave the toggle as the user set it, just log for visibility.
            Self.log.info("SMAppService login item requires approval in System Settings")
            return
        @unknown default:
            Self.log.info("SMAppService.mainApp.status returned an unrecognized case: \(String(describing: status), privacy: .public)")
            return
        }
        guard actual != runAtLogin else { return }
        isSyncingLoginItem = true
        runAtLogin = actual
        isSyncingLoginItem = false
    }

    /// Opens onboarding or the Control Panel at launch, whichever applies.
    /// Must run after the SwiftUI scene has registered `openWindowRequest`
    /// (`openWindow` doesn't exist in `AppDelegate`/`bootstrap()`), and only
    /// once per launch. Onboarding takes priority: on a first run (or any run
    /// where Accessibility still isn't trusted and onboarding was never
    /// finished), it needs to be seen before "Bật bảng này khi khởi động"
    /// would otherwise open the Control Panel instead.
    func performLaunchOpenIfNeeded() {
        guard !didAttemptLaunchOpen else { return }
        didAttemptLaunchOpen = true
        if needsOnboarding {
            NSApp.activate(ignoringOtherApps: true)
            openWindowRequest?(WindowID.onboarding)
        } else if openControlPanelAtLaunch {
            NSApp.activate(ignoringOtherApps: true)
            openWindowRequest?(WindowID.controlPanel)
        }
    }

    /// Relaunch a fresh instance of Keystone and quit this one — the fix for the
    /// "granted but tap still won't create" case.
    func relaunch() {
        let path = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let proc = Process()
        proc.executableURL = path
        do {
            try proc.run()
        } catch {
            // Don't quit into nothing — if we can't spawn the replacement, tell
            // the user and stay running rather than silently disappearing.
            Self.log.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Không khởi động lại được Keystone"
            alert.informativeText = "Hãy thoát và mở lại thủ công. (\(error.localizedDescription))"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        shutdown()
        NSApp.terminate(nil)
    }

    func quit() { shutdown(); NSApp.terminate(nil) }

    /// "Mặc định" — reset every setting (mapped + scaffolding) to its default.
    func resetToDefaults() {
        inputMethod = .telex
        codeTable = .unicode
        orthography = .modern
        quickTelex = false
        restoreIfInvalid = true
        useLexicon = true

        spellCheck = true
        allowFreeToneMark = true
        freeMarkAcrossCoda = true
        literalAfterCancel = true
        autoCapitalize = false
        quickStartConsonant = false
        quickEndConsonant = false
        smartSwitch = true
        rememberCodePerApp = true
        autoFixSuggestion = false
        sendEachKeystroke = false
        switchHotKey = SwitchHotKey(modifiers: [.control, .shift])
        switchKeyEnabled = true
        switchKeyBeep = false
        macrosEnabled = false
        macrosExpandWhenVietnameseOff = false
        macroAutoCapitalize = true
        runAtLogin = false
        openControlPanelAtLaunch = false
        checkForUpdates = true
        showDockIcon = false
    }

    /// "Xoá ghi nhớ theo ứng dụng" — wipes every app Keystone has learned
    /// state for. Does NOT touch settings (`smartSwitch`/`rememberCodePerApp`
    /// stay whatever they were) — see `resetToDefaults()`.
    func resetLearnedApps() {
        PerAppStore.shared.reset()
    }

    /// Handles `NSWorkspace.didActivateApplicationNotification`: always
    /// resets the composing buffer, then — when the newly-activated app is a
    /// real other app (not `nil`, not Keystone's own windows) and at least
    /// one smart-switch toggle is on — saves the state we're leaving behind
    /// and restores whatever was learned for the app we're entering.
    private func handleAppActivation(newBundleID: String?) {
        controller.resetBuffer()

        guard
            let newBundleID,
            newBundleID != Bundle.main.bundleIdentifier
        else { return }

        guard perAppTrackingOn else {
            currentBundleID = newBundleID
            return
        }

        if let oldBundleID = currentBundleID {
            PerAppStore.shared.remember(currentInputState, for: oldBundleID)
        }
        currentBundleID = newBundleID

        guard let remembered = PerAppStore.shared.state(for: newBundleID) else { return }
        let resolved = SmartSwitch.resolve(
            remembered: remembered,
            current: currentInputState,
            smartSwitch: smartSwitch,
            rememberCodeTable: rememberCodePerApp
        )
        applyingPerAppState = true
        enabled = resolved.vietnameseEnabled
        codeTable = resolved.codeTable
        applyingPerAppState = false
    }

    /// Called from the `enabled`/`codeTable` `didSet`s: a manual change (not
    /// one we're applying ourselves via `handleAppActivation`) is learned for
    /// the current app immediately, not only on the next app switch.
    private func persistPerAppStateIfNeeded() {
        guard !applyingPerAppState, perAppTrackingOn, let bundleID = currentBundleID else { return }
        PerAppStore.shared.remember(currentInputState, for: bundleID)
    }

    /// Installs the GLOBAL + LOCAL `NSEvent` monitors behind "Phím chuyển".
    /// Deliberately AppKit monitors, not the CGEventTap: this hot key must
    /// stay off the tap's hot path (see DECISIONS.md). The global monitor
    /// needs Accessibility to observe other apps' events — already required
    /// for the tap itself — so if it isn't granted yet the hot key simply
    /// won't fire globally; nothing here crashes either way.
    /// Event types the switch-key monitors watch: modifier changes and real
    /// keys as before, PLUS mouse-down events. A modifier-only target can now
    /// be a single modifier (⇧, ⌥ or ⌘ alone — Phase 7), and a bare click
    /// while holding one of those is an everyday gesture (shift-click to
    /// extend a selection, ⌘-click to open in a new tab, ⌥-click). Without
    /// this, releasing the modifier after such a click looks exactly like a
    /// clean chord release and spuriously toggles Vietnamese. Feeding mouse
    /// events into `otherKeyPressed()` — same as a real keyDown — cancels
    /// that. See DECISIONS.md "Phím chuyển".
    private static let switchKeyMonitoredEvents: NSEvent.EventTypeMask = [
        .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]

    private func installSwitchKeyMonitors() {
        // These monitors are delivered on the main thread, so handle them
        // SYNCHRONOUSLY (assumeIsolated) rather than hopping through a Task:
        // `SwitchKeyDetector` is an ordered state machine, and a Task hop
        // could reorder a cancelling keyDown after the releasing flagsChanged
        // and fire a spurious toggle. NSEvent isn't Sendable, so pull the
        // plain data out before touching the main-actor detector.
        switchKeyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.switchKeyMonitoredEvents) { [weak self] event in
            let type = event.type
            let modifiers = ModifierSet(nsEventFlags: event.modifierFlags)
            MainActor.assumeIsolated { self?.handleSwitchKeyEvent(type: type, modifiers: modifiers) }
        }
        switchKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.switchKeyMonitoredEvents) { [weak self] event in
            let type = event.type
            let modifiers = ModifierSet(nsEventFlags: event.modifierFlags)
            MainActor.assumeIsolated { self?.handleSwitchKeyEvent(type: type, modifiers: modifiers) }
            return event
        }
    }

    /// Shared handler for both "Phím chuyển" monitors: feeds `switchDetector`
    /// and flips `enabled` on a clean chord press-then-release. A keyDown or
    /// a mouse-down both count as "something else happened during this hold"
    /// — see `Self.switchKeyMonitoredEvents`.
    @MainActor
    private func handleSwitchKeyEvent(type: NSEvent.EventType, modifiers: ModifierSet) {
        switch type {
        case .flagsChanged:
            if switchDetector.flagsChanged(active: modifiers) {
                toggleVietnameseFromHotKey()
            }
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            switchDetector.otherKeyPressed()
        default:
            break
        }
    }

    /// Flips `enabled` and, iff `switchKeyBeep` is on, plays the system
    /// beep — shared by both "Phím chuyển" firing paths (the
    /// `SwitchKeyDetector` chord above, and `hotKeyRegistrar`'s Carbon
    /// callback wired in `bootstrap()`).
    @MainActor
    private func toggleVietnameseFromHotKey() {
        enabled.toggle()
        if switchKeyBeep { NSSound.beep() }
    }

    /// Suspends the tap's Vietnamese engine WITHOUT touching `enabled` (the
    /// persisted, user-facing toggle) — call while the "Phím kèm:" recorder
    /// in the Control Panel is armed. With the engine active, a plain
    /// character key is unconditionally suppressed and re-synthesized on a
    /// NEW event with `virtualKey 0` (see `EngineController.handle`/
    /// `TapSink.postText`); the recorder's local monitor would then capture
    /// THAT synthetic event — keyCode 0, and a label built from whatever the
    /// engine transformed the key into — instead of the physical key the
    /// user actually pressed. Suspending the engine for the recorder's brief
    /// one-keystroke window makes every key pass through untouched, so the
    /// recorder always sees the real keyCode/characters. See DECISIONS.md
    /// "Phím chuyển".
    func beginSwitchKeyRecording() {
        controller.setActive(false)
    }

    /// Restores the engine to whatever `enabled` currently is (not
    /// unconditionally `true`) once the recorder has captured a key or been
    /// cancelled — pairs with `beginSwitchKeyRecording()`.
    func endSwitchKeyRecording() {
        controller.setActive(enabled)
    }

    /// Applies `switchHotKey`/`switchKeyEnabled` to whichever live mechanism
    /// the combo needs: a modifier-only combo arms `switchDetector`
    /// (NSEvent monitors, off the tap); a modifier+key combo registers a
    /// Carbon hot key instead (`hotKeyRegistrar`), since only Carbon can
    /// consume the key outright. Disabled → both are torn down, checked
    /// FIRST, before validation — turning "Bật phím chuyển" off must tear
    /// down whatever is live even while the in-progress draft is invalid
    /// (e.g. every modifier box unchecked mid-edit); otherwise the last valid
    /// combo would keep firing while the UI shows the feature off.
    ///
    /// An invalid combo (`switchHotKey.validationError != nil`) is never
    /// applied: this returns, leaving whichever mechanism (and
    /// `appliedSwitchHotKey`) was last successfully applied still running, so
    /// a bad in-progress edit in the Control Panel never drops a working hot
    /// key. The reason is surfaced via `switchKeyError` either way (the UI's
    /// red caption).
    ///
    /// `switchHotKey` is persisted (`AppModel.saveSwitchHotKey`) ONLY on the
    /// two success paths below — never for an invalid draft, and never for a
    /// key combo that failed to register — so a relaunch always finds the
    /// last combo that actually worked, not a half-finished edit. See
    /// DECISIONS.md "Phím chuyển".
    private func applySwitchHotKeyRegistration() {
        guard switchKeyEnabled else {
            switchKeyError = nil
            switchDetector.target = nil
            hotKeyRegistrar.unregister()
            appliedSwitchHotKey = nil
            return
        }
        if let error = switchHotKey.validationError {
            switchKeyError = error
            return
        }
        if let key = switchHotKey.key {
            do {
                // Register the NEW combo before touching `switchDetector`:
                // if this throws (e.g. `eventHotKeyExistsErr`), a hot key
                // that was live via the modifier-only path must stay live
                // rather than being cleared out from under a failed change.
                try hotKeyRegistrar.register(carbonModifiers: switchHotKey.modifiers.carbonModifierMask, keyCode: key.keyCode)
                switchDetector.target = nil
                switchKeyError = nil
                appliedSwitchHotKey = switchHotKey
                AppModel.saveSwitchHotKey(switchHotKey)
            } catch let error as SwitchHotKeyRegistrar.RegistrationError {
                Self.log.error("RegisterEventHotKey failed: OSStatus \(error.status, privacy: .public) for combo \(self.switchHotKey.displayString, privacy: .public)")
                switchKeyError = "Tổ hợp này đang được hệ thống hoặc app khác dùng"
            } catch {
                Self.log.error("RegisterEventHotKey failed: \(error.localizedDescription, privacy: .public)")
                switchKeyError = "Tổ hợp này đang được hệ thống hoặc app khác dùng"
            }
        } else {
            hotKeyRegistrar.unregister()
            switchDetector.target = switchHotKey.modifiers
            switchKeyError = nil
            appliedSwitchHotKey = switchHotKey
            AppModel.saveSwitchHotKey(switchHotKey)
        }
    }

    private func startTap() {
        guard !tapStarted else { return }
        tap.start()
        tapStarted = true
        startAttempts = 0
        controller.setActive(enabled)
    }

    private func pushConfig() {
        controller.updateConfig(EngineConfig(
            inputMethod: inputMethod,
            codeTable: codeTable,
            orthography: orthography,
            restoreIfInvalid: restoreIfInvalid,
            quickTelex: quickTelex,
            macrosEnabled: macrosEnabled,
            macrosExpandWhenVietnameseOff: macrosExpandWhenVietnameseOff,
            macroAutoCapitalize: macroAutoCapitalize,
            macros: MacroStore.shared.macros.map { $0.toRule() },
            quickStartConsonant: quickStartConsonant,
            quickEndConsonant: quickEndConsonant,
            autoCapitalize: autoCapitalize,
            allowFreeToneMark: allowFreeToneMark,
            freeMarkAcrossCoda: freeMarkAcrossCoda,
            literalAfterCancel: literalAfterCancel,
            spellCheck: spellCheck
        ))
    }

    /// Pushes `sendEachKeystroke`/`autoFixSuggestion` into the tap's
    /// `InputBehavior` snapshot (design spec E.2/E.3) — the input-layer
    /// counterpart to `pushConfig()` above.
    private func pushInputBehavior() {
        tap.updateBehavior(InputBehavior(sendEachKeystroke: sendEachKeystroke, textOnKeyDownOnly: autoFixSuggestion))
    }

    private func refresh() {
        accessibilityTrusted = Permissions.isAccessibilityTrusted()
        inputMonitoring = Permissions.inputMonitoringGranted()

        if accessibilityTrusted && !tapStarted {
            startTap()
        }
        tapRunning = tapStarted && tap.isRunning

        // If we're trusted and started but the tap still isn't live after a few
        // polls, the grant needs a relaunch to take effect.
        if accessibilityTrusted && tapStarted && !tap.isRunning {
            startAttempts += 1
            needsRelaunch = startAttempts >= 2
        } else {
            startAttempts = 0
            needsRelaunch = false
        }
    }

    // MARK: - UserDefaults persistence

    private enum Keys {
        static let inputMethod = "settings.inputMethod"
        static let codeTable = "settings.codeTable"
        static let orthography = "settings.orthography"
        static let quickTelex = "settings.quickTelex"
        static let restoreIfInvalid = "settings.restoreIfInvalid"
        static let useLexicon = "settings.useLexicon"
        static let spellCheck = "settings.spellCheck"
        static let allowFreeToneMark = "settings.allowFreeToneMark"
        static let freeMarkAcrossCoda = "settings.freeMarkAcrossCoda"
        static let literalAfterCancel = "settings.literalAfterCancel"
        static let autoCapitalize = "settings.autoCapitalize"
        static let quickStartConsonant = "settings.quickStartConsonant"
        static let quickEndConsonant = "settings.quickEndConsonant"
        static let smartSwitch = "settings.smartSwitch"
        static let rememberCodePerApp = "settings.rememberCodePerApp"
        static let autoFixSuggestion = "settings.autoFixSuggestion"
        static let sendEachKeystroke = "settings.sendEachKeystroke"
        /// Retired `SwitchKeyModifier` raw string — read-only now, only for
        /// `loadSwitchHotKeyState()`'s one-time migration. Never written.
        static let switchKeyModifierLegacy = "settings.switchKeyModifier"
        static let switchHotKey = "settings.switchHotKey"
        static let switchKeyEnabled = "settings.switchKeyEnabled"
        static let switchKeyBeep = "settings.switchKeyBeep"
        static let macrosEnabled = "settings.macrosEnabled"
        static let macrosExpandWhenVietnameseOff = "settings.macrosExpandWhenVietnameseOff"
        static let macroAutoCapitalize = "settings.macroAutoCapitalize"
        static let runAtLogin = "settings.runAtLogin"
        static let openControlPanelAtLaunch = "settings.openControlPanelAtLaunch"
        static let didFinishOnboarding = "settings.didFinishOnboarding"
        static let checkForUpdates = "settings.checkForUpdates"
        static let showDockIcon = "settings.showDockIcon"
    }

    private static func loadBool(_ key: String, default def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }

    private static func loadRaw<T: RawRepresentable>(_ key: String, default def: T) -> T where T.RawValue == String {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return def }
        return T(rawValue: raw) ?? def
    }

    /// Loads `(switchHotKey, switchKeyEnabled)`. The two halves are resolved
    /// INDEPENDENTLY, not as one all-or-nothing migration result — a legacy
    /// upgrade only ever produces both together, but `Keys.switchKeyEnabled`
    /// gets its own write on every toggle from then on (see
    /// `switchKeyEnabled`'s `didSet`), and it must win whenever it exists,
    /// regardless of which branch supplied the combo:
    ///   - `hotKey`: the NEW `Keys.switchHotKey` JSON if present and it
    ///     decodes to a *valid* combo; otherwise the legacy
    ///     `SwitchKeyModifier` raw string's migrated combo (⌃⇧ if that, too,
    ///     was never written).
    ///   - `isEnabled`: `Keys.switchKeyEnabled` if that key has EVER been
    ///     written (`UserDefaults.object(forKey:)`, not `bool(forKey:)`, so a
    ///     stored `false` isn't confused with "never written"); only when it
    ///     is truly absent does this fall back to the legacy raw string's
    ///     migrated `isEnabled`.
    /// Without this split, a user who only ever toggled "Bật phím chuyển"
    /// (never touched the combo, so `Keys.switchHotKey` stays unwritten)
    /// would have that on/off choice silently discarded on every relaunch —
    /// the migration branch used to return its own `isEnabled` unconditionally.
    /// Called twice at property-initializer time (once for each property);
    /// both reads are cheap and pure, so the duplication costs nothing worth
    /// caching.
    private static func loadSwitchHotKeyState() -> (hotKey: SwitchHotKey, isEnabled: Bool) {
        let defaults = UserDefaults.standard
        let legacyMigration = { SwitchHotKey.migrateLegacy(rawValue: defaults.string(forKey: Keys.switchKeyModifierLegacy)) }

        var hotKey = legacyMigration().hotKey
        if let data = defaults.data(forKey: Keys.switchHotKey) {
            do {
                let decoded = try JSONDecoder().decode(SwitchHotKey.self, from: data)
                if let error = decoded.validationError {
                    log.error("Saved switchHotKey is invalid (\(error, privacy: .public)); using the legacy/default combo")
                } else {
                    hotKey = decoded
                }
            } catch {
                log.error("Saved switchHotKey could not be decoded (\(error.localizedDescription, privacy: .public)); using the legacy/default combo")
            }
        }

        let isEnabled: Bool
        if let storedEnabled = defaults.object(forKey: Keys.switchKeyEnabled) as? Bool {
            isEnabled = storedEnabled
        } else {
            isEnabled = legacyMigration().isEnabled
        }

        return (hotKey, isEnabled)
    }

    private static func saveSwitchHotKey(_ hotKey: SwitchHotKey) {
        guard let data = try? JSONEncoder().encode(hotKey) else {
            // Should be unreachable (SwitchHotKey is a plain Codable value
            // type with no failable fields), but this is user-settings
            // persistence, not the tap hot path — log rather than crash or
            // silently drop.
            Self.log.error("Failed to JSON-encode switchHotKey for persistence")
            return
        }
        UserDefaults.standard.set(data, forKey: Keys.switchHotKey)
    }
}
