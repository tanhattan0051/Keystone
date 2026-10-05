# Keystone — HANDOFF / Ghi chú bàn giao

> Đọc file này trước khi code tiếp (kể cả khi mở bằng Claude Desktop). Toàn bộ thiết kế nằm trong `docs/superpowers/specs/2026-09-16-keystone-design.md`.

## Keystone là gì
App **bộ gõ tiếng Việt mới hoàn toàn cho macOS 26/27**, thay thế OpenKey, nhằm **diệt tận gốc lỗi "đang gõ tự nhiên mất tiếng Việt"** và có giao diện đẹp hợp macOS 27. Đây là **dự án của riêng bạn** (Hướng B).

## Các quyết định đã chốt
- **Hướng B:** engine tiếng Việt **viết mới từ đầu (clean-room)** — KHÔNG đọc/chép mã của OpenKey (OpenKey là GPLv3). Nhờ vậy app **thuộc bản quyền của bạn**, tự do chọn giấy phép (kể cả đóng/độc quyền).
- **Tên:** **Keystone** · bundle id `com.tanta.keystone` (đổi được).
- **Công nghệ:** **Swift thuần** cho tất cả (engine + tầng nhập + UI) · **SwiftUI** (phong cách macOS 27, Liquid Glass) · app menu-bar (LSUIElement) · target **macOS 26.0+** (dev trên 27).
- **Cơ chế nhập (v1):** **CGEventTap làm đúng cách** (tương thích mọi app). InputMethodKit để dành v2.
- **Chính tả mặc định:** kiểu mới (oà, uý); kiểu cũ là tuỳ chọn.
- **Phân phối:** Developer ID + notarize + DMG (không lên App Store được vì cần quyền Accessibility). Cập nhật: Sparkle (Phase 5).
- **Giao diện:** **mirror đúng bố cục OpenKey** (menu + Bảng điều khiển 4 tab: Cơ bản / Gõ tắt / Hệ thống / Thông tin) — xem Phần 2 của spec.

## ⚠️ Lỗi phải diệt (quan trọng nhất — xem Phần E của spec)
1. **E.1 — Mất tiếng Việt khi đang gõ (lỗi số 1):** OpenKey không bật lại event tap khi macOS tắt nó + làm việc nặng trên hot path. **Keystone:** xử lý `kCGEventTapDisabledByTimeout/UserInput` ngay trong callback + **watchdog** định kỳ + **không làm gì nặng trong callback** (cache qua notification đổi app).
2. **E.4 — Crash/không phản hồi:** lỗi bộ nhớ CoreFoundation. **Keystone:** dùng bridging CF an toàn của Swift.
3. **E.2/E.3/E.5/E.6…** đúp chữ (Spotlight), kén app (Terminal/Electron), sai hoa/thường, ghép âm sai. Mỗi lỗi đã ánh xạ tới phần thiết kế + phải có test. Danh sách issue thật của OpenKey đã dẫn số `#` trong Phần E.

## Cấu trúc repo
```
docs/superpowers/specs/2026-09-16-keystone-design.md   ← SPEC ĐẦY ĐỦ (đọc cái này)
Design/icons/*.svg                                      ← 5 concept icon + glyph menu-bar
Design/icons/concepts.json                              ← mô tả/palette từng concept
Design/icon-showcase.html                              ← trang xem icon (đã publish)
HANDOFF.md (file này) · README.md
```
Mã nguồn OpenKey để tham chiếu (đọc để hiểu lỗi, KHÔNG chép): `../OpenKey`.

## Icon — ĐÃ CHỐT ✅
- **Đã chọn: "Gilded K with Coral Wedge"** (`monogram-k`) — chữ K vàng + nêm keystone coral + dấu mũ.
- SVG gốc: `Design/icons/AppIcon.svg` · master PNG: `Design/icons/AppIcon-1024.png`
- **`Design/AppIcon.appiconset/`** — đủ 10 kích cỡ + `Contents.json`, kéo thẳng vào `Assets.xcassets` của Xcode.
- Glyph menu-bar (template, đơn sắc): `Design/menubar/menubarTemplate.png` (18px) + `@2x` (36px). Đặt "Render As: Template Image".
- Trang so sánh 5 hướng (tham khảo): https://claude.ai/artifact/PvMAVx1Q5xZRUSEGBiDx8i
- Muốn tinh chỉnh thêm (màu/độ dày nét/bo góc) cứ bảo mình.

## Việc tiếp theo (lộ trình — chi tiết ở Phần D của spec)
- ✅ **Phase 1 — XONG:** module `KeystoneEngine` (Swift thuần) + **bộ test corpus**. Đã có: Telex đầy đủ, Unicode NFC, đặt dấu kiểu mới **và** cũ (Phần A §4), `Syllable` fold (re-derive mỗi phím), restore-if-invalid 2 lớp, backspace khôi phục dấu (Phần A §8). Test Swift Testing **xanh**: 153 ca corpus + 12 property. Các quyết định engine (bao gồm giải Open Questions) ghi ở `DECISIONS.md`. CI: `.github/workflows/ci.yml`.
  - Cấu trúc: `Sources/KeystoneEngine/{Model,NFC,TonePlacement,Phonology,Telex,Engine}.swift`; test + corpus JSON ở `Tests/KeystoneEngineTests/`.
  - Đã diệt tại engine (có regression test): E.5 (hoa/thường theo cấu trúc, `VIEEJT`→`VIỆT`), E.6 (`chưa`+`a`→`chưaa` không ép `chưâ`; `hồng` không `hoồng`; `huơ`/`khuơ`/`thuở` gõ được qua phím `[`; `gì`/`gìn`), và bảo vệ từ tiếng Anh (`wrong`,`coins`,`ruins`…).
  - Còn nợ (Phase 3): bảng rime §5.3 mới ở mức luật offglide (đủ cho v1, nên nâng thành bảng đầy đủ sau); VNI/Simple/Quick Telex; 4 bảng mã cũ (TCVN3/VNI-Win/tổ hợp/CP1258).
- ✅ **Phase 2 — XONG (cần nghiệm thu máy thật):** `KeystoneInput` + app menu-bar.
  - `Sources/KeystoneInput/`: `EventTapController` (tap trên thread riêng + run loop; **Layer A** re-enable ngay trong callback khi `.tapDisabledByTimeout/UserInput`; **Layer B** watchdog `DispatchSourceTimer` 1.5s; **self-tag** (`eventSourceUserData` = "KSTONE") chống xử lý lại event của chính mình; **không việc nặng** trên hot path), `EngineController` (bọc `Engine` an toàn thread bằng `OSAllocatedUnfairLock`), `KeyTranslator` (keycode/flags → quyết định), `KeystrokeExecutor` + `EventSink`, `Permissions` (AX + Input Monitoring), `SystemStateCache`.
  - `App/`: SwiftUI `MenuBarExtra` tối thiểu (`.accessory` — không icon Dock): bật/tắt tiếng Việt, trạng thái + nút cấp quyền Accessibility, Thoát. Chạy: `swift run Keystone`.
  - Test: 22 unit test cho translator/executor/EngineController (tap sống không test được headless — đúng như spec).
  - **Cách nghiệm thu:** `swift run Keystone` → cấp quyền Accessibility khi macOS hỏi → gõ thử ở TextEdit/Notes/Safari/Terminal.
- ✅ **Phase 3 — XONG:**
  - ✅ **VNI** — `Sources/KeystoneEngine/VNI.swift` (digit 1-5 thanh, 6/7/8 dấu, 9 đ, 0 xoá thanh, double-strike undo). Dùng chung `SyllableOps.swift` (5 helper tách từ Telex) + đặt dấu/validity/restore của engine. Engine dispatch theo `config.inputMethod`. `isWordChar` cho digit qua fold khi VNI. Test: 33 ca `vni.json` + 8 cặp `DifferentialTests` (Telex↔VNI ra cùng từ).
  - ✅ Quick Telex (toggle), Simple Telex → dispatch Telex, 5 bảng mã (Unicode dựng sẵn/tổ hợp, TCVN3, VNI-Windows, CP1258) qua `OutputTable` + `Converter`.
  - ⬜ Còn nợ nhỏ: nâng bảng rime §5.3 từ luật offglide lên bảng đầy đủ (đủ cho v1).
- ✅ **Phase 4 — nối engine XONG (UI khung đã có từ trước):**
  - ✅ **Gõ tắt (macro)** — `Sources/KeystoneEngine/Macro.swift` (`MacroRule`/`MacroTable`), nổ trong `Engine.finalize` (nhánh bật tiếng Việt) + `processInactive`/`flushInactive` (nhánh tắt tiếng Việt, chỉ khi bật cả 2 cờ). `EngineConfig` thêm `macros` + 3 toggle (mặc định tắt). Import file macro OpenKey (`.txt`). Giải Open Q #9. Chi tiết ở `DECISIONS.md` mục "Macros / gõ tắt".
  - ✅ **Smart-switch** — `Sources/KeystoneInput/PerAppState.swift` (`AppInputState`/`PerAppStateStore`/`SmartSwitch.resolve`, thuần) + `App/PerAppStore.swift` (JSON ở App Support) + xử lý trong `AppModel.handleAppActivation` (save-on-leave / restore-on-enter theo notification đổi app, bỏ qua bundle của chính Keystone). 2 toggle độc lập: `smartSwitch` (VN/English) và `rememberCodePerApp` (bảng mã). Chi tiết ở `DECISIONS.md` mục "Smart-switch".
  - ✅ **Gõ tắt phụ âm + viết hoa đầu câu** — `Telex.fold` thêm 2 nhánh có cổng: start (`cells.isEmpty`: f→ph/j→gi/w→qu) và end (`cells.last.isVowel`: g→ng/h→nh/k→ch); `Engine.finalize` viết hoa chữ đầu câu (dùng lại `atSentenceStart`, cả nhánh restore). 3 cờ `EngineConfig` mặc định tắt. Xem `DECISIONS.md`.
  - ✅ **Toggle hệ thống** — `runAtLogin` (`SMAppService.mainApp` + reconcile khi khởi động + revert khi lỗi), `showDockIcon` (`setActivationPolicy`), `openControlPanelAtLaunch` (mở qua `openWindowRequest` đăng ký từ `MenuBarLabel`). `checkForUpdates` để dormant (Phase 5).
  - ✅ **Onboarding** — `App/OnboardingView.swift` (cửa sổ "Chào mừng", 2 thẻ quyền, dùng lại state + poll 1.5s của `AppModel`), tự mở khi `needsOnboarding`, mở lại từ menu "Hướng dẫn cấp quyền…". `Permissions` thêm request/mở-cài-đặt Input Monitoring.
  - ✅ **Phím chuyển** (`switchKeyModifier`) — tổ hợp phím (mặc định ⌃⇧, hoặc "Tắt") nhấn-thả sạch để bật/tắt tiếng Việt; `SwitchKeyDetector` thuần + NSEvent monitor **ngoài** hot-path tap. Chỉ báo **V/E** trên menu bar.
  - ✅ **Bỏ dấu tự do** (`allowFreeToneMark`) — cổng cho việc đặt dấu không sát chữ (mặc định BẬT = như cũ; TẮT = ép sát chữ).
  - ✅ **Gửi từng phím** (`sendEachKeystroke`) + **Sửa lỗi gợi ý** (`autoFixSuggestion`: gõ keyDown-only + `clearsInlineSuggestion` — ký tự đệm U+202F và Backspace thừa trước khi xoá, để gợi ý tự điền của omnibox không nuốt Backspace; tắt trong Terminal/Spotlight và không áp dụng khi phím Xoá lùi của người dùng chỉ xoá chữ (không đổi dấu); đánh đổi: ô tự xoá khoảng trắng có thể mất 1 chữ) — qua `InputBehavior` đẩy vào `EventTapController` (đọc snapshot 1 lần/edit). autoFixSuggestion mặc định TẮT (giữ nguyên hành vi tap, opt-in). [VERIFY] phần inline-autocomplete chưa thử trên Chrome thật.
  - ⬜ **Còn (không chặn — vẫn scaffolding):** `checkForUpdates` (bộ kiểm tra thật — Phase 5/Sparkle); `spellCheck` (trùng ý với `restoreIfInvalid` sẵn có — cần chốt ngữ nghĩa trước khi nối kẻo thành no-op).

## ⚠️ [VERIFY] Phase 2 — phải đo trên macOS thật (chưa test được ở đây)
1. **Cấp quyền xong có cần khởi động lại app?** Nếu `AXIsProcessTrusted()` = true nhưng `CGEvent.tapCreate` vẫn nil → cần relaunch. App hiện log lỗi + poll; nên thêm nút "Khởi động lại" nếu gặp.
2. **Đúp chữ (E.2/E.3):** `TapSink.postText` gắn chuỗi Unicode lên **cả keyDown và keyUp** (theo spec). Vài app (Terminal/Electron/VSCode) có thể chèn 2 lần → nếu bị, đổi sang chỉ gắn trên keyDown, hoặc fallback gõ từng grapheme (lập bảng quirk theo bundle id).
3. **keyUp không cặp keyDown (Open Q #6):** ta suppress keyDown vật lý nhưng keyUp vẫn lọt (không tap keyUp) → thử game/app theo dõi phím thô.
4. **Cần thêm Input Monitoring?** Đã có `Permissions.inputMonitoringGranted()` để dò; xác nhận macOS 27 có đòi không (onboarding 1 hay 2 thẻ quyền).
- **Phase 3:** VNI, Simple Telex 1/2, Quick Telex + đủ 5 bảng mã.
- **Phase 4:** gõ tắt, smart-switch, công cụ chuyển mã, Bảng điều khiển 4 tab, onboarding.
- **Phase 5:** ký, notarize, DMG, Sparkle.

## ⚠️ [VERIFY] — phải đo trên macOS 27 thật (trước/khi vào Phase 2)
- Event tap **biến đổi** trên macOS 26/27 cần **Accessibility là đủ**, hay **cần thêm Input Monitoring**? (quyết định onboarding 1 hay 2 thẻ quyền)
- Cấp quyền xong **có cần khởi động lại app** không?
- App nào xử lý sai chuỗi Unicode nhiều ký tự (terminal/Electron/JetBrains) → cần fallback gõ từng grapheme.
- Sàn triển khai macOS 26 với SDK đang cài (kiểm toolchain).
- Bảng byte chuẩn cho TCVN3 / VNI-Windows / CP1258 (tự soạn + kiểm chứng).

## Câu hỏi mở còn để ngỏ (xem cuối spec)
Chuẩn hoá y↔i (Mỹ/Mĩ), chính sách auto-`ươ`, UX thanh sai trên âm tiết đóng, macro fire ở đâu trong pipeline, mặc định `zAlsoStripsDiacritics`.
