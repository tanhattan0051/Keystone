# Keystone — Bộ gõ tiếng Việt cho macOS · Tài liệu thiết kế (Design Spec)

- **Trạng thái:** Bản nháp để duyệt (v0.1)
- **Ngày:** 2026-09-16
- **Chủ sở hữu:** cá nhân (bản quyền riêng — engine viết mới hoàn toàn, không dùng mã GPL của OpenKey)
- **Ngôn ngữ tài liệu:** Phần 0–2 (quyết định & bố cục) viết bằng tiếng Việt; các Phần A–D (kỹ thuật chi tiết) viết bằng tiếng Anh để tiện tra cứu khi code.

> Tài liệu này là kết quả tổng hợp: phần lõi kỹ thuật (A–D) do các agent chuyên trách soạn song song, phần định hướng & quyết định (0–2, và mục cuối) do người thiết kế chốt. Đọc Phần 0 trước để nắm các quyết định; Phần 2 là bố cục giao diện **chuẩn** (mirror OpenKey theo yêu cầu); các Phần A–D là chi tiết triển khai.

---

## 0. Quyết định sản phẩm (Product decisions)

| Hạng mục | Quyết định |
|---|---|
| **Tên** | **Keystone** · bundle id `com.tanta.keystone` (đổi được) |
| **Bản quyền** | Của riêng bạn, tuỳ chọn giấy phép. Engine tiếng Việt **viết mới từ đầu (clean-room)** — không đọc/không chép mã GPL của OpenKey. |
| **Ngôn ngữ** | **Swift thuần** cho toàn bộ (engine + tầng nhập + UI) |
| **Giao diện** | **SwiftUI**, phong cách macOS 27 (Liquid Glass), app menu-bar (LSUIElement) |
| **Target** | **macOS 26.0+** (phát triển trên macOS 27) — *xác nhận lại theo SDK cài đặt* |
| **Cơ chế nhập v1** | **CGEventTap làm đúng cách** (tương thích mọi app). InputMethodKit là hướng thay thế tương lai, không thuộc v1. |
| **Phân phối** | Developer ID + notarize + **DMG** (app dạng event-tap **không** lên Mac App Store được vì sandbox). Cập nhật: Sparkle (Phase 5). |
| **Chính tả mặc định** | **Kiểu mới (oà, uý)**; kiểu cũ (òa, úy) là tuỳ chọn. *(Ghi chú 2026-10-17: bản đã phát hành mặc định là òa, úy; oà, uý bật bằng tuỳ chọn "Đặt dấu oà, uý". Tên enum trong code `.modern`/`.classic` bị đặt ngược quy ước — xem DECISIONS.md "Orthography default".)* |
| **Bộ tính năng** | Ngang bằng OpenKey (xem Phần 2) |

### Lỗi của OpenKey mà Keystone phải diệt tận gốc (không được lặp lại)
1. **Tap bị tắt không bật lại** — OpenKey không xử lý `kCGEventTapDisabledByTimeout` / `kCGEventTapDisabledByUserInput` → gõ đang ngon tự nhiên mất tiếng Việt. Keystone: xử lý ngay trong callback **+** watchdog định kỳ (Phần B).
2. **Việc nặng trên hot path** — OpenKey gọi `CGWindowListCopyWindowInfo`/`frontmostApplication`/`TIS…` **mỗi phím** → chạm ngưỡng watchdog → macOS tắt tap. Keystone: **không làm gì nặng trong callback**; cache cập nhật qua notification đổi app (Phần B).
3. **Lỗi bộ nhớ CoreFoundation** — over-release/rò rỉ trong nhánh "ngôn ngữ khác". Keystone: dùng bridging CoreFoundation an toàn của Swift (Phần B).

---

## 1. Kiến trúc tổng thể (module map)

Ba module, phụ thuộc một chiều (`app → input → engine`); **engine không phụ thuộc gì** nên test được 100%.

```
KeystoneEngine   (Swift, thuần, không phụ thuộc macOS/UI)
     ▲              Syllable · Telex/VNI parser · TonePlacer · SpellChecker · Encoder(5 bảng mã) · diff
     │              Vào: KeyInput + EngineConfig   →   Ra: EngineResult{ backspaceCount, outputText }
KeystoneInput    (Swift, macOS)  — CGEventTap + watchdog + cache + thực thi EngineResult (backspace + gõ Unicode)
     ▲
Keystone (app)   (SwiftUI)  — MenuBarExtra, Bảng điều khiển, Gõ tắt, Công cụ chuyển mã, Onboarding cấp quyền
```

**Nguyên tắc cốt lõi:** engine trả về chỉ thị *"xoá lùi N ký tự, gõ chuỗi X"*; tầng nhập chỉ thực thi. Nhờ vậy mọi hành vi khó (đặt lại dấu, khôi phục dấu sau khi xoá, đổi bảng mã, khôi phục khi sai) đều là *re-render một giá trị*, và toàn bộ engine kiểm thử được bằng hàng nghìn ca mà không cần chạy app.

---

## 2. Giao diện — bố cục CHUẨN (mirror OpenKey) 🎯

> **Đây là bố cục quy chuẩn theo yêu cầu ("giữ cách sắp xếp như OpenKey").** Phần C (thiết kế SwiftUI chi tiết) phải tuân theo bố cục này; chỗ nào Phần C khác đi thì lấy Phần 2 làm chuẩn. Nhãn dùng đúng nguyên văn OpenKey.

### 2.1 Menu thanh trạng thái (MenuBarExtra)
`Bật Tiếng Việt` · `Kiểu gõ ▸` (Telex / VNI / Simple Telex 1 / Simple Telex 2) · `Unicode dựng sẵn` · `TCVN3 (ABC)` · `VNI Windows` · `Bảng mã khác ▸` (Unicode tổ hợp / Vietnamese Locale CP 1258) · `Công cụ chuyển mã…` · `Chuyển mã nhanh` · `Bảng điều khiển…` · `Gõ tắt…` · `Giới thiệu` · `Thoát`.
Icon menu-bar đổi trạng thái **VN ⇄ EN** (template, hợp light/dark).

### 2.2 Bảng điều khiển — 4 tab
**Tab "Cơ bản":**
- `Kiểu gõ:` (popup) · `Bảng mã:` (popup) · trạng thái quyền (OK / cảnh báo + nút thử lại) · chế độ Việt/Anh
- `Kiểm tra chính tả`
- `Tự khôi phục phím với từ sai`
- `Đặt dấu oà, uý (thay vì òa, úy)`  *(chính tả mới)*
- `Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th)`
- `Gõ tắt phụ âm đầu: f→ph, j→gi, w→qu`
- `Gõ tắt phụ âm cuối: g→ng, h→nh, k→ch`
- `Viết Hoa chữ cái đầu câu`
- `Sửa lỗi gợi ý (trình duyệt, Excel,...)`
- `Cho phép bỏ dấu tự do`
- `Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh`
- `Chuyển chế độ thông minh`  *(smart switch)*
- `Tự ghi nhớ bảng mã theo ứng dụng`
- `Tạm tắt chính tả bằng phím ⌃` · `Tạm tắt OpenKey bằng phím ⌘`  *(đổi tên "OpenKey"→"Keystone")*
- `Tương thích Telex trên các Layout khác (Dvorak, Colemak, ...)`
- `Phím chuyển:` (⌃ ⌥ ⌘ ⇧ + phím) · `Kêu beep`
- `Gửi từng phím (bật nếu bị lỗi)`

**Tab "Gõ tắt":**
- `Cho phép gõ tắt` · `Gõ tắt cả khi tắt gõ tiếng Việt` · `Tự động viết hoa theo phím tắt`
- Nút mở **Thiết lập gõ tắt** (bảng danh sách: từ gõ tắt → nội dung, thêm/sửa/xoá, nhập/xuất)

**Tab "Hệ thống":**
- `Khởi động cùng macOS` · `Bật bảng này khi khởi động`
- `Kiểm tra bản mới khi khởi động`
- Icon xám/đen-trắng · `Hiện icon trên Dock`
- Nút `Mặc định` (đặt lại cấu hình)

**Tab "Thông tin":**
- Phiên bản / ngày cập nhật · nút kiểm tra bản mới · liên kết trang chủ

### 2.3 Công cụ chuyển mã (cửa sổ riêng)
`Bảng mã nguồn` → `Bảng mã đích` · `Chuyển sang chữ HOA` / `chữ thường` · `Đặt chữ Hoa đầu câu` / `Hoa Sau Mỗi Từ` · `Loại bỏ dấu câu` · `Thông báo khi chuyển xong` · nút `Chuyển mã` / `Chuyển mã trong Clipboard` (có phím tắt nhanh).

> **Bắt buộc:** Công cụ chuyển mã và bộ mã hoá của engine phải dùng **chung một module bảng mã** để gõ trực tiếp và chuyển clipboard không bao giờ lệch nhau từng byte.

---
---

# Phần E — Danh mục lỗi OpenKey → cách Keystone phòng tránh 🛡️

> Tổng hợp từ (1) phân tích mã nguồn OpenKey, (2) CHANGELOG, và (3) **các issue thật trên GitHub `tuyenvm/OpenKey`** (số `#` để tra cứu). Mỗi lỗi: triệu chứng → nguyên nhân gốc → **cách Keystone chặn** (trỏ tới phần thiết kế). Đây là checklist bắt buộc: mỗi mục phải có test/kiểm chứng trước khi phát hành.

## E.1 ⭐ "Đang gõ tự nhiên mất tiếng Việt" / thường xuyên không gõ được
**Issue:** #193 (M1 "thường xuyên không gõ được"), #226 (chết sau update 12.5.1), #264, #257, #247, #201.
**Nguyên nhân gốc:** callback CGEventTap **bị macOS tắt** (do timeout watchdog hoặc user-input) và OpenKey **không bao giờ bật lại** (`OpenKeyCallback` không xử lý `kCGEventTapDisabledByTimeout/UserInput`; cả app chỉ gọi `CGEventTapEnable` đúng 1 lần). Càng nặng máy / macOS mới siết watchdog càng dễ bung.
**Keystone chặn:** (a) trong callback, gặp 2 sự kiện disabled đó → **bật lại tap ngay**; (b) **watchdog định kỳ** kiểm `CGEventTapIsEnabled` và bật lại nếu tắt; (c) **không làm gì nặng trong callback** để không chạm watchdog. → Phần B §2, §3. **Đây là lỗi số 1 phải diệt.**

## E.2 Đúp chữ / double char (đặc biệt Spotlight)
**Issue:** #315, #270, #255, #237, #246 (không gõ được `w` trên Spotlight).
**Nguyên nhân gốc:** cơ chế "sửa lỗi gợi ý" gửi ký tự rỗng + backspace thừa, cộng việc dò Spotlight bằng `CGWindowListCopyWindowInfo` **mỗi phím** → chậm + đua sự kiện → chèn/đúp ký tự; thứ tự "gửi ký tự tổng hợp rồi thả phím vật lý" bị lệch.
**Keystone chặn:** mặc định **Unicode NFC dựng sẵn** + thuật toán diff xoá-lùi chính xác theo code-unit (Phần A §7) để không cần chèn ký tự rỗng; **bỏ dò Spotlight khỏi hot path** (cache hoặc bỏ hẳn — Phần B §3 + Open Q); xử lý chặn keyDown vật lý nhất quán (Phần B §1). Tất cả ca Spotlight/đúp chữ đưa vào test tương thích.

## E.3 Tương thích ứng dụng: Terminal / Electron / VSCode / Telegram / Firefox / Google Docs / Photoshop
**Issue:** #319 (Terminal + Claude Code), #277 (terminal mac), #276 (Firefox), #261/#159/#161 (Telegram), #171 (Google Docs/Sheets), #152/#214 (VSCode Markdown), #123 (Google Slides), #117/#283 (Photoshop/Illustrator), #165 (Coda delay).
**Nguyên nhân gốc:** mỗi app xử lý `CGEventKeyboardSetUnicodeString` nhiều ký tự / chuỗi tổ hợp khác nhau; app dựa Electron/web tự autocomplete; một số app xoá nguyên cụm grapheme mỗi lần Delete, số khác xoá từng mark.
**Keystone chặn:** NFC precomposed mặc định (1 unit = 1 grapheme → xoá lùi đúng ở mọi app); **bảng quirk theo bundle id** + fallback **gõ từng grapheme** cho app khó (Phần A §7, Phần B Open Q). Ghi rõ: InputMethodKit (tương lai) sẽ loại bỏ phần lớn lớp lỗi này — cân nhắc cho v2.

## E.4 Crash / không phản hồi
**Issue:** #278 (Not responding), #258 (không phản hồi), #108 (check bản mới làm treo).
**Nguyên nhân gốc:** lỗi bộ nhớ CoreFoundation (over-release `CFRelease(langRef)` + rò rỉ `TISInputSource` ở nhánh "ngôn ngữ khác"); và thao tác mạng/đồng bộ chặn luồng.
**Keystone chặn:** dùng **bridging CoreFoundation an toàn của Swift** (`takeRetainedValue`/`takeUnretainedValue`) — không tay-quản-lý retain/release (Phần B §4); mọi việc mạng/kiểm cập nhật chạy **bất đồng bộ**, không bao giờ trong callback.

## E.5 Engine — tự viết hoa sai với nguyên âm có dấu
**Issue:** #320, #285 (uppercase khi bỏ dấu), #259, #233, #136 (in hoa với Shift).
**Nguyên nhân gốc:** trạng thái hoa/thường bị trộn với việc phát lại ký tự có dấu trong buffer thô.
**Keystone chặn:** hoa/thường là **thuộc tính của từng phím trong `KeyInput`** (shift/caps) và của `Vowel`; chuỗi ra được **re-render từ cấu trúc**, không phát lại thủ công → không lệch hoa/thường (Phần A §1). Các ca này thành test corpus.

## E.6 Engine — ghép nguyên âm / double-strike / khôi phục sai
**Issue:** #312 (`chưa`+`a` → `chưâ` thay vì `chưaa`), #114 (`hồng` → `hoồng`), #229 (không gõ được `huơ`/`khuơ`), #275 (`huychj` → `huỵch`), #119 (không khôi phục `nẽt`), #135 (lỗi `Ê`/`Đ`), #151 (lỗi phím `d`), #313 (`w`→`ư` gõ tắt không nhận).
**Nguyên nhân gốc:** OpenKey rà lại mảng ký tự thô → quyết định đặt dấu/ghép âm mong manh; double-strike và literal fall-through không nhất quán.
**Keystone chặn:** mô hình **`Syllable` có cấu trúc** + luật **double-strike & literal fall-through tường minh** (Phần A §2.4: `aa`→â, `aaa`→`aa`…) + **kiểm tra ngữ âm** loại rime bất hợp lệ như `ưâ` và **khôi phục về phím thô** (Phần A §5). Ví dụ `chưa`+`a`: `ưâ` không hợp lệ → không ép thành `chưâ`. **Mọi từ trong các issue trên trở thành ca test bắt buộc.**

## E.7 Smart-switch / đổi app
**Issue:** #155 (Command+Tab tự đổi ngôn ngữ), #272 (không nhớ bảng mã với Alfred), #240/#236 (không đổi VN/Eng khi dùng Microsoft IME tiếng Nhật).
**Nguyên nhân gốc:** phát hiện đổi app + xử lý cờ modifier + đọc input source đồng bộ trên hot path.
**Keystone chặn:** smart-switch chạy theo **notification đổi app** (không trên hot path), khoá theo bundle id, lưu ổn định (Phần B, Phần C); phím chuyển gộp trong tap, tránh nhầm với Command+Tab (Phần C Open Q).

## E.8 Đa người dùng / khởi động cùng máy / mất con trỏ
**Issue:** #302, #235 (chỉ chạy 1 tài khoản), #243 (đổi kiểu gõ mất con trỏ chuột), #298 (không tự khởi động).
**Keystone chặn:** kiểm tra single-instance **theo từng user (UID)** như bản OpenKey mới (an toàn Fast User Switching); **SMAppService** thay `SMLoginItemSetEnabled` (Phần C §8, Phần D); không đụng con trỏ khi đổi cấu hình.

## E.9 Gõ tắt (macro)
**Issue:** #284 (đôi khi không hoạt động), #279 (auto-complete khi kết thúc chuỗi không cần space), #106.
**Keystone chặn:** định nghĩa rõ **macro kích hoạt ở đâu trong pipeline** so với commit & restore-if-invalid (Phần A Open Q #9); test riêng cho macro.

## E.10 Phân phối / notarize / cảnh báo bảo mật
**Issue:** #274 ("Apple could not verify… malware"), #248 (Security & Privacy), #105 ("no mountable file system"), #304 (cài qua terminal macOS 26 Tahoe).
**Keystone chặn:** **Developer ID + hardened runtime + notarize + staple**, đóng **DMG** đúng chuẩn (Phần D §3). Không để người dùng phải bypass Gatekeeper thủ công.

---

### Bảng đối chiếu nhanh (lỗi lớn → nơi đã xử lý)
| Lỗi OpenKey | Keystone xử lý ở |
|---|---|
| Mất tiếng Việt khi đang gõ (E.1) | Phần B §2 (re-enable + watchdog) |
| Việc nặng làm tap timeout (E.1) | Phần B §3 (không việc nặng trên hot path) |
| Đúp chữ / Spotlight (E.2) | Phần A §7 + Phần B §3 |
| Kén app Terminal/Electron… (E.3) | Phần A §7 + Phần B (quirk table) |
| Crash do CF memory (E.4) | Phần B §4 (Swift CF bridging) |
| Sai hoa/thường, ghép âm (E.5, E.6) | Phần A §1, §2.4, §5 + test corpus |
| Smart-switch, đa user (E.7, E.8) | Phần B, Phần C §8, Phần D |
| Notarize / Gatekeeper (E.10) | Phần D §3 |
---

## Quyết định đã chốt & câu hỏi còn mở (Resolved decisions)

Tổng hợp các "Open questions" từ Phần A–D, kèm quyết định để bản triển khai không bị mắc kẹt. Chỗ nào cần đo trên macOS 27 thật thì ghi rõ **[VERIFY]**.

### Đã chốt
1. **Chính tả mặc định:** kiểu mới (oà, uý). Kiểu cũ là tuỳ chọn.
2. **`z` / VNI `0`:** mặc định "chỉ xoá dấu thanh". `zAlsoStripsDiacritics` mặc định **tắt**. VNI `0` = xoá thanh, **bật**.
3. **Simple Telex 1/2:** dùng định nghĩa clean-room của Keystone (Phần A §2.5) làm chuẩn, đối chiếu OpenKey bằng test hộp-đen; **không** chép mã.
4. **Khôi phục khi sai (restore-if-invalid):** trả về **đúng chuỗi phím gõ thô** (không phải trạng thái hợp lệ gần nhất). Một luật duy nhất, ghim bằng test.
5. **Ranh giới commit buffer:** khoảng trắng · dấu câu/ký tự không phải chữ · phím điều hướng (mũi tên, Home/End/PageUp/Down, Esc) · **click chuột** · **đổi app/focus** · phím không thể mở rộng âm tiết hợp lệ. (Phần A §8)
6. **Bảng mã:** **NFC dựng sẵn** là dạng nội bộ + mặc định khi gõ trực tiếp (1 code unit = 1 grapheme, mọi app xoá lùi đúng). Bảng cũ (TCVN3/VNI-Win/CP1258/Unicode tổ hợp) chỉ kết xuất ở mốc commit hoặc trong Công cụ chuyển mã; nếu phải sửa trực tiếp ở dạng tổ hợp thì fallback "xoá cả âm tiết + gõ lại".
7. **Phím tắt toàn cục** (chuyển ngôn ngữ, chuyển mã nhanh, tạm tắt): **gộp vào chính CGEventTap** (đã xử lý `flagsChanged`), hỗ trợ tổ hợp chỉ-modifier (vd ⌃⌘). Không cần monitor riêng.
8. **Smart-switch** khoá theo **bundle id** (chấp nhận hạn chế với app Electron dùng chung bundle id). Lưu ở UserDefaults suite riêng.
9. **Cập nhật:** Sparkle 2.x (EdDSA, hợp DMG notarized) — thuộc **Phase 5**, không chặn v1.
10. **Đổi chữ "OpenKey"** trong nhãn "Tạm tắt OpenKey bằng ⌘" → **"Tạm tắt Keystone bằng ⌘"**.

### [VERIFY] — phải đo trên macOS 27 thật (Phase 2)
- **Quyền:** Accessibility là bắt buộc cho event tap. **Có cần thêm Input Monitoring** cho một session tap *biến đổi* (transform) trên macOS 26/27 không? → quyết định onboarding hiện **1 hay 2 thẻ quyền**. Thiết kế onboarding hỗ trợ cả hai, tự dò lúc chạy.
- **Cấp quyền xong có cần khởi động lại app** để tap hoạt động không? Nếu có → onboarding có bước "khởi động lại" mượt.
- **App xử lý sai chuỗi Unicode nhiều ký tự** (terminal, Electron, JetBrains…): lập bảng quirk per-app, fallback gõ từng grapheme.
- **Toolchain/SDK:** xác nhận sàn triển khai macOS 26 với SDK đang cài (một agent thấy toolchain nhắm macOS mới hơn — cần kiểm).
- **Bảng byte bảng mã cũ:** tự soạn & kiểm chứng TCVN3 (ABC), VNI-Windows, CP1258 (đặc biệt các ca hoa có dấu 2 byte) từ nguồn tham chiếu chuẩn; lưu thành dữ liệu của mình.

### Còn để ngỏ (quyết định khi vào phần liên quan)
- Chuẩn hoá `y`↔`i` (Mỹ/Mĩ, lý/lí): có làm không, mặc định? (tách khỏi toggle dấu cũ/mới)
- `gi`/`qu` các ca hiếm/loan-word và khi người dùng chủ ý gõ tiếng Anh "gi…".
- Chính sách tự hoàn thành `ươ` khi thêm horn vào `uo` (chạm-1-chữ hay cả cụm).
- UX khi áp thanh không hợp lệ lên âm tiết đóng bằng phụ âm tắc (từ chối im lặng / giữ chờ / nhả literal).
- Macro/gõ tắt kích hoạt ở đâu trong pipeline (trước/sau restore-if-invalid).

---

## Lộ trình triển khai (tóm tắt — chi tiết ở Phần D)
- **Phase 1 — Engine + bộ test:** Telex + Unicode NFC + đặt dấu (kiểu mới), khung `Syllable`, corpus test xanh.
- **Phase 2 — Tầng nhập + bản vá diệt lỗi:** CGEventTap đúng cách (re-enable + watchdog + cache), menu-bar tối thiểu, đo các mục **[VERIFY]**.
- **Phase 3 — Đủ kiểu gõ & bảng mã:** VNI, Simple Telex 1/2, Quick Telex; TCVN3/VNI-Win/Unicode tổ hợp/CP1258.
- **Phase 4 — Tính năng & UI đầy đủ:** gõ tắt, smart-switch, công cụ chuyển mã, Bảng điều khiển 4 tab, onboarding.
- **Phase 5 — Ký & phân phối:** Developer ID, hardened runtime, notarize, DMG, Sparkle.

---

## Phụ lục kỹ thuật (do agent chuyên trách soạn)

> Bốn phần dưới đây là thiết kế chi tiết, viết bằng tiếng Anh, dùng làm tài liệu tham chiếu khi code. Bố cục UI ở **Phần C** tuân theo **Phần 2** ở trên.
# Engine — Vietnamese Linguistic Core & Algorithms

This is the correctness-critical heart of Keystone. The engine is pure and platform-agnostic: it consumes one `KeyInput` plus an `EngineConfig` and returns an `EngineResult { backspaceCount, outputText }`. Everything below is deterministic and side-effect free, which makes it fully unit-testable in isolation from the macOS event layer.

The single most important design decision: **the engine models a Vietnamese *syllable*, not a char array.** OpenKey mutated a raw buffer of typed characters and re-scanned it on every key. That approach makes tone placement, "restore-if-invalid", and the modern/old orthography toggle fragile, because the tone's *position* is entangled with byte offsets. In Keystone the tone and diacritics are **attributes of a structured syllable**; the rendered string is *derived* from that structure on every keystroke. Re-placing a tone after the nucleus changes, restoring a diacritic after a backspace, and switching output tables all become a re-render of a value, not a surgical edit of a buffer.

---

## 1. The Syllable data model

A Vietnamese syllable has the maximal shape **`(C1)(w)V(V)(V)(C2) + tone`**:

- **C1** — initial consonant / cluster (optional): `b, c, ch, d, đ, g, gh, gi, h, k, kh, l, m, n, ng, ngh, nh, p, ph, qu, r, s, t, th, tr, v, x`.
- **w** — medial glide `/w/`, written `o` (hoa, khỏe) or `u` (huy, quả, tuần). Part of the onset, *not* tone-bearing in the modern-open cases except by the toggle rule.
- **V(V)(V)** — nucleus: monophthong, diphthong, or triphthong.
- **C2** — final consonant / offglide (optional): stops `p t c ch`, nasals `m n ng nh`, semivowels `i/y`, `o/u`.
- **tone** — one of 6.

```swift
enum Tone: UInt8 {                 // thanh điệu
    case ngang = 0                 // level, no mark
    case huyen                     // ` grave  (à)
    case sac                       // ´ acute  (á)
    case hoi                       // ̉ hook   (ả)
    case nga                       // ˜ tilde  (ã)
    case nang                      // ̣ dot below (ạ)
}

/// A single "letter slot" in the nucleus: a base vowel plus an optional quality mark.
/// The tone is NOT stored here — it belongs to the syllable and is *placed* at render time.
enum BaseVowel: UInt8 { case a, e, i, o, u, y }

enum VowelMark: UInt8 {            // dấu phụ nguyên âm
    case none
    case circumflex                // ˆ : a→â, e→ê, o→ô
    case breve                     // ˘ : a→ă
    case horn                      // ̛ : o→ơ, u→ư
}

struct Vowel: Equatable {
    var base: BaseVowel
    var mark: VowelMark = .none    // legal combos only: â ê ô ă ơ ư
}

/// Onset. `dStroke` records the đ (d with stroke) form; qu/gi are their own cases
/// because their trailing u/i are glides/graphemic, not nucleus vowels.
struct Onset: Equatable {
    var letters: [Character]       // canonical onset spelling, e.g. ["t","h"], ["q","u"]
    var dStroke: Bool = false      // đ
}

struct Syllable: Equatable {
    var onset: Onset?              // C1 (+ medial glide folded in for qu/gi)
    var glide: Bool = false        // medial o/u glide present (hoa, huy) when onset is a normal consonant
    var nucleus: [Vowel]           // 1–3 vowels, in written order
    var coda: [Character]          // C2 spelling: [], ["n"], ["n","g"], ["c","h"], offglide ["i"], ["u"]…
    var tone: Tone = .ngang

    /// Raw key intent history for the *current word*, used for backspace re-derivation and
    /// literal fall-through. This is what makes "restore diacritic after delete" trivial.
    var intent: [KeyIntent] = []
}
```

`KeyIntent` is the abstract action a key produced (add base letter, apply mark, apply tone, undo), stored so a backspace can pop the last intent and the syllable can be **re-derived from scratch** — never edited in place.

**Why this beats a char array:** tone and quality marks are attributes, so (a) tone re-placement when the nucleus grows/shrinks is automatic, (b) switching output code tables is a pure re-render, (c) validation ("is this a legal Vietnamese syllable?") runs on structure, not on a scan-and-guess over bytes, and (d) the modern↔old toggle is one branch in the placement function instead of a positional hack.

---

## 2. Complete Telex rules

### 2.1 Quality-mark & đ transforms

| Keys | Result | Notes |
|------|--------|-------|
| `a`+`a` | â | circumflex on a |
| `a`+`w` | ă | breve on a |
| `e`+`e` | ê | |
| `o`+`o` | ô | |
| `o`+`w` / `[` | ơ | `[` is the direct-key shortcut |
| `u`+`w` / `w` / `]` | ư | bare `w` → ư when no `a`/`o` is pending to modify |
| `d`+`d` | đ | |

Auto-`ươ`: typing `uow` or applying `w` to a `uo` nucleus produces **ươ** (both horns), e.g. `nuwowc`/`nuoc`+`w` → `nước` base `nươc`. `w` applied to a pending `u` alone → `ư`; applied to `o` alone → `ơ`; applied to `a` → `ă`. The disambiguation is contextual on the current nucleus.

### 2.2 Tone keys

`s`→sắc, `f`→huyền, `r`→hỏi, `x`→ngã, `j`→nặng, `z`→remove tone.

Tone keys are **positionally free**: they may be typed anywhere after the nucleus vowel exists (`tieengs` and `tiengs` and `tiesng` all → `tiếng`) because the tone is a syllable attribute placed by the algorithm in §4.

### 2.3 `z` semantics — exact order

1. If `tone != .ngang` → set `tone = .ngang`, consume the key (no literal emitted).
2. Else if `EngineConfig.zAlsoStripsDiacritics` (default **off**) and the nucleus has any `VowelMark != .none` → remove the **most recently applied** mark (tracked via `intent`).
3. Else → `z` is not a Vietnamese action here: emit literal `z`, commit/continue the buffer as English.

Default keeps `z` = "remove tone only" (Unikey-compatible). The diacritic-stripping behavior is opt-in.

### 2.4 Double-strike & literal fall-through

Rule: **re-pressing the same transform/tone key that produced the current state undoes it and emits the key as a literal**, provided no *other* state-changing key intervened.

- Tone: `as`→`á`, `ass`→`as` (2nd `s` clears sắc *and* appends literal `s`). `belief`-style words survive.
- Quality: `aa`→`â`, `aaa`→`aa` (3rd `a`: undo circumflex, emit literal `a` → the two plain letters `aa`). `oo`→`ô`, `ooo`→`oo`. `dd`→`đ`, `ddd`→`dd`.
- Horn: `w` toggling — `uw`→`ư`, `uww`→`uw` (undo, literal `w`).
- Applying a *different* tone replaces (does not stack): `as`→`á`, then `f` → `à`.

Formally, each transform records in `intent` the `(key, targetSlot, priorState)`. If the incoming key equals the last intent's key **and** targets the same slot **and** nothing between them changed that slot, execute the inverse and append the literal character.

### 2.5 Simple Telex 1 vs Simple Telex 2

These are reduced-collision Telex variants. Keystone defines them canonically (clean-room; we do not read OpenKey source — see Open Questions for parity validation):

- **Simple Telex 1** — Telex minus the overloaded bare `w`:
  - `w` is **only** `ư` (never `ă`); `ă` requires the explicit `aw`. `[`→`ơ`, `]`→`ư` direct keys enabled. Everything else identical to full Telex. Goal: `w` never surprises English typists mid-word.
- **Simple Telex 2** — Simple Telex 1 plus **single-key vowel marks that don't require doubling** in the common cases: `[`→`ơ`, `]`→`ư`, `w`→`ư`, and the circumflex is still `aa/ee/oo` (kept, because single-key `^` has no clean Telex letter). The practical difference from #1 is that #2 additionally treats a trailing `w` on `o`/`u` inside an existing nucleus as horn without needing the base letter re-typed.

Because we don't reuse GPL code, we treat our definitions as authoritative and validate parity by user testing against real OpenKey behavior.

### 2.6 Quick Telex

Consonant-cluster shortcuts layered on top of Telex, applied at the **onset/coda** position (not the nucleus):

| Keys | Expands to |
|------|-----------|
| `cc` | ch |
| `gg` | gi |
| `kk` | kh |
| `nn` | ng |
| `qq` | qu |
| `pp` | ph |
| `tt` | th |
| `dd` | đ (unchanged — đ takes precedence over any "dh") |
| `w` | ư |

Quick Telex expansions fire only where a consonant cluster is legal (word-initial for onsets; `nn`→`ng` also valid as a coda). All §2.1–2.4 tone/quality/double-strike rules still apply on top.

---

## 3. Complete VNI rules

Digit keys act as marks on the current syllable:

| Key | Action |
|-----|--------|
| `1` | sắc  (´) |
| `2` | huyền (`) |
| `3` | hỏi  (̉) |
| `4` | ngã  (˜) |
| `5` | nặng (̣) |
| `6` | circumflex → â / ê / ô (chooses base a/e/o in nucleus) |
| `7` | horn → ơ / ư (chooses base o/u) |
| `8` | breve → ă |
| `9` | đ |
| `0` | remove tone (same semantics as Telex `z`, §2.3) — *optional, config* |

`6` and `7` resolve their target by the nucleus: `6` on `a`→â, on `e`→ê, on `o`→ô; `7` on `o`→ơ, on `u`→ư, and on a `uo` nucleus → **ươ** (both). Tone digits `1–5` place via the §4 algorithm.

**Double-strike undo:** pressing the same digit again removes/undoes that mark and emits the digit literally: `a1`→`á`, `a11`→`a1` (undo sắc, literal `1`); `a6`→`â`, `a66`→`a6`; `d9`→`đ`, `d99`→`d9`. Same `(key, slot, priorState)` inverse mechanism as Telex.

---

## 4. Exact tone-placement algorithm (modern **and** old orthography)

Tone position is computed fresh on every render from the structured syllable. Preprocessing: fold `qu`/`gi` into the onset (their `u`/`i` are glides, not nucleus vowels — see the `gi`/`qu` edge notes below), leaving a clean **nucleus vowel list** `V = [v0, v1, v2]` (length 1–3) and a boolean `hasCoda`.

### 4.1 Decision procedure

```
placeTone(nucleus V, hasCoda, style ∈ {modern, old}) -> index into V

// STEP A — quality-marked vowel always wins, in this priority order.
// (At most one applies; the priority resolves the only real collision, ươ.)
if 'ơ' in V: return index('ơ')        // ươ, uơ, ơ  →  ơ  (được, rượu, thuở)
if 'ê' in V: return index('ê')        // iê, yê, uyê, uê  (tiếng, nguyễn, huệ)
if 'ô' in V: return index('ô')        // uô, ô  (muốn, quốc)
if 'ă' in V: return index('ă')        // oă, ă  (quăng, ắt)
if 'â' in V: return index('â')        // uâ, â  (tuần, cấu)
if 'ư' in V: return index('ư')        // ưa, ưu, ưi, ư  (cửa, cứu, gửi)

// STEP B — no quality mark. Purely structural.
n = V.count
if n == 1: return 0

if hasCoda:                            // closed syllable: peak is the LAST nucleus vowel
    return n - 1                       // toán→a, hoàng→a, huỳnh→y

// open syllable, no mark:
if n == 3:                             // triphthong → MIDDLE vowel
    return 1                           // khuỷu→y, ngoẻo→e, khoái→a

// n == 2, open:
if V == [o,a] || V == [o,e] || V == [u,y]:   // the ONLY toggle-sensitive set
    return (style == modern) ? 0 : 1   // modern: glide letter; old: main vowel
else:
    return 0                           // falling diphthong, peak first: ai ao ay au eo oi ui iu ua ia…
```

### 4.2 Key principles encoded above

- **ê / ơ / ô (and ă, â, ư) always carry the tone** — Step A short-circuits everything. This is why `tiếng`, `muốn`, `được`, `tuần` never depend on style.
- **Closed vs open** — Step B splits on `hasCoda`. Closed syllables put the tone on the last nucleus vowel (the vowel before the coda); Vietnamese has no falling-diphthong-plus-coda syllables, so "last vowel" is always the phonetic peak.
- **The modern/old toggle affects exactly `{oa, oe, uy}` open, unmarked.** In every other case modern == old. Modern (kiểu mới) puts the mark on the *glide letter* (first); old (kiểu cũ) on the *main vowel* (second).
- **Triphthongs** are unambiguous → middle vowel, no toggle.

### 4.3 Worked examples (mark landing shown)

| Word | Nucleus | Coda? | Rule fired | Mark on | Result |
|------|---------|-------|-----------|---------|--------|
| hòa / hoà | o a | open | B toggle `oa` | modern→o / old→a | **hòa** / **hoà** |
| khỏe / khoẻ | o e | open | B toggle `oe` | modern→o / old→e | **khỏe** / **khoẻ** |
| thủy / thuỷ | u y | open | B toggle `uy` | modern→u / old→y | **thủy** / **thuỷ** |
| toán | o a | `n` | B closed → last | a | **toán** |
| tuần | u **â** | `n` | A (â) | â | **tuần** |
| tiếng | i **ê** | `ng` | A (ê) | ê | **tiếng** |
| muốn | u **ô** | `n` | A (ô) | ô | **muốn** |
| được | ư **ơ** | `c` | A (ơ, beats ư) | ơ | **được** |
| của | u a | open | B, not toggle set → first | u | **của** |
| mía | i a | open | B, not toggle set → first | i | **mía** |
| quả | (qu)+a | open | onset folds `qu`; n=1 | a | **quả** |
| giày | (gi)+a y | open | onset folds `gi`; `ay` → first | a | **giày** |
| khuỷu | u y u | open | B triphthong → middle | y | **khuỷu** |
| nguyễn | u y **ê** | `n` | A (ê) | ê | **nguyễn** |
| hoàng | o a | `ng` | B closed → last | a | **hoàng** |
| quốc | (qu)+**ô** | `c` | A (ô) | ô | **quốc** |

All sixteen land correctly under one procedure.

### 4.4 `gi` / `qu` edge handling

- **`qu`** → always onset `/kw/`; the `u` is a glide and never tone-bearing. `quả`→nucleus `a`, `quý`→nucleus `y`, `quốc`→ô wins.
- **`gi`** → onset **when followed by another vowel** (`giày`, `giếng`→ê, `giữ`→ư). But `gi` + coda/end means `g` is the onset and `i` is the nucleus: **`gì` = g + ì**, `gìn` (giữ gìn) = g + i + n. The engine tries the "`gi` is onset" parse first; if the remainder has no nucleus vowel, it re-parses `g` onset + `i` nucleus.

---

## 5. Phonotactic / spelling validation

Used by **restore-if-invalid** (if a completed syllable is not a legal Vietnamese word, drop the diacritics and emit the raw keystrokes) and to keep tone placement honest. Encode as static tables the engine checks in O(1).

### 5.1 Legal onsets

```
Singles:  b c d đ g h k l m n p q r s t v x
Digraphs: ch gh gi kh nh ng ph qu th tr
Trigraph: ngh
```

Orthographic selection rules (validator normalizes / rejects):

- **c / k / q:** `k` before front vowels `e ê i y`; `c` before `a ă â o ô ơ u ư`; `qu` before a glide nucleus. (`k`+`a` is invalid Vietnamese onset spelling.)
- **g / gh:** `gh` before `e ê i`; `g` elsewhere.
- **ng / ngh:** `ngh` before `e ê i`; `ng` elsewhere.

### 5.2 Legal codas

```
Stops:      p t c ch
Nasals:     m n ng nh
Semivowels: i/y  o/u   (offglides)
```

- `ch` / `nh` occur only after **front** nuclei (`i, ê, e`, and `a`→`anh`/`ach`, `ê`→`ênh`/`êch`). `c` / `ng` occur after back/central nuclei.
- Semivowel finals combine as falling diphthongs (`ai, ao, eo, oi, ui, ưu, …`) and cannot co-occur with a consonant coda.

### 5.3 Nucleus × coda legality

Maintain a table `legalRime[nucleus][coda] -> Bool`. This rejects impossible rimes (e.g. `*iên` is fine → `tiên`; `*inh` fine; `*ưnh` illegal; `*ơng` fine → `ương`). The table is finite (a few hundred entries) and enumerable from a standard Vietnamese rime inventory.

### 5.4 Tone restriction (checked/entering tones)

**Syllables closed by a stop coda (`p t c ch`) may bear only `sắc` or `nặng`.** All other tones on a stop-closed syllable are illegal.

```swift
func toneAllowed(_ tone: Tone, coda: [Character]) -> Bool {
    let stops: Set<String> = ["p", "t", "c", "ch"]
    if stops.contains(coda.map(String.init).joined()) {
        return tone == .sac || tone == .nang
    }
    return true
}
```

If the user types `f/r/x/z` (huyền/hỏi/ngã/ngang) on a stop-closed syllable, the engine refuses the tone (or, per config, holds it pending a coda change). This is a strong, cheap validity signal.

### 5.5 Restore-if-invalid

On syllable commit, run: legal onset? legal rime? tone permitted? If any fails → discard the derived Vietnamese spelling and emit the **raw literal keystrokes** instead (so `wrong` stays `wrong`, not `ưrong`). Because we keep `intent` (§1), the raw form is always recoverable without re-typing.

---

## 6. Encoder — rendering a `Syllable` to each output table

The encoder is a pure function `render(Syllable, OutputTable) -> [CodeUnit]`. Placement (§4) decides *which* vowel carries the tone; the encoder decides *how* that (base, quality mark, tone) triple is spelled in the target table.

```swift
protocol OutputTable {
    /// Returns the code units for one composed vowel (base + quality mark + tone).
    func units(base: BaseVowel, mark: VowelMark, tone: Tone) -> [UInt16 or UInt8]
    func dStroke(upper: Bool) -> [CodeUnit]         // đ / Đ
    var unitsPerToned: ClosedRange<Int> { get }      // 1 for NFC, up to 3 for combining/legacy
}
```

- **Unicode NFC (precomposed)** — table maps every legal `(base, mark, tone)` to a single precomposed scalar (`ấ` = U+1EA5, `ờ` = U+1EDD, `đ` = U+0111). **1 code unit per logical char.** This is the internal canonical form and the default output — always use it for diffing (§7).
- **Unicode combining / compound (tổ hợp)** — base letter + combining quality mark + combining tone, in canonical (NFD) order: base, then U+0302 circumflex / U+0306 breve / U+031B horn, then U+0300 huyền / U+0301 sắc / U+0309 hỏi / U+0303 ngã / U+0323 nặng. `đ` stays precomposed U+0111 (no combining stroke in common use). **1 logical char = 2–3 code units.**
- **TCVN3 (ABC)** — 8-bit font encoding. Most toned lowercase vowels occupy a single byte in `0xA0–0xFF`. The 256-slot space overflows, so **uppercase toned vowels and some forms are encoded as base byte + a separate tone-mark byte** → *one logical char = 2 bytes*. `đ`/`Đ` have dedicated bytes.
- **VNI-Windows** — 8-bit, encodes toned vowels as **base char byte + a separate combining-mark byte** for the tone (e.g. `á` = `a` + tone-mark byte), so many logical chars are **2 bytes**; quality marks likewise add a byte. Requires precise per-char byte tables.
- **CP1258 (Windows Vietnamese code page)** — has precomposed single bytes for the quality vowels (`â ă ê ô ơ ư đ`) but expresses **tones via combining marks** (grave/acute/hook/tilde/dot mapped into the page), so a toned vowel is base byte + combining tone byte.

**Tricky bit (all legacy/combining tables):** one logical Vietnamese character maps to **multiple code units**. Every downstream step — length, cursor math, and especially the backspace count in §7 — must operate on **code units of the active table**, never on Swift `Character`/grapheme counts. The encoder therefore exposes the unit count it emitted.

---

## 7. Backspace + retype diff algorithm

Goal: given the previously emitted output and the newly rendered output for the current syllable, produce `EngineResult { backspaceCount, outputText }` with minimal edits, correct even when logical chars span multiple code units.

Keep, per active table, the exact **code-unit array we previously sent** (`prevUnits`) — not the abstract syllable. Render the new syllable to the same table (`newUnits`). Diff on code units:

```
func diff(prevUnits: [CU], newUnits: [CU]) -> EngineResult {
    // longest common prefix, counted in CODE UNITS of the active table
    var i = 0
    let maxLen = min(prevUnits.count, newUnits.count)
    while i < maxLen && prevUnits[i] == newUnits[i] { i += 1 }

    let backspaceCount = prevUnits.count - i       // units to delete
    let outputUnits    = Array(newUnits[i...])     // units to type
    return EngineResult(backspaceCount: backspaceCount,
                        outputText: decode(outputUnits, table))
}
```

Because we count code units, a change to a 2-byte legacy char naturally yields the right backspace count (delete both bytes, retype both). Example (VNI-Windows, `á` = 2 bytes): `a`→`á` diffs from `[a]` to `[a, toneByte]` → common prefix `[a]`, backspaceCount 0, output `[toneByte]`; `á`→`à` diffs `[a,ácute]`→`[a, àgrave]` → backspace 1, output `[grave]`.

**The deletion-granularity caveat (real, must be handled in the input layer, surfaced by the engine):** a synthesized *Delete* keypress deletes what the *target app* treats as one deletable unit — for NFC precomposed that's 1 scalar = our 1 unit (clean), but for **combining sequences some apps delete the whole grapheme cluster with one Delete, others delete one combining mark at a time.** Mitigations, in order of preference:

1. **Default to NFC precomposed for on-the-fly editing** so backspaceCount == scalar count == graphemes == what every app deletes per Delete. Only convert to a legacy/combining table at *commit* boundaries where no further in-place editing happens, or in the clipboard-conversion tool (which replaces a whole selection, not incremental deletes).
2. For tables that must edit live in combining form, expose the table's `unitsPerToned` and let the input layer choose deletion strategy per app (a per-app quirk table), or fall back to "backspace the whole syllable and retype it" (`backspaceCount = prevGraphemes`, `outputText = whole new syllable`) — larger but always correct.

The engine returns unit-accurate counts; the input layer owns the app-specific deletion mapping. This split is exactly why the engine stays pure.

---

## 8. Buffer / session lifecycle

The **session buffer** holds the current word: the `intent` history and the derived `Syllable`. Everything is re-derived from `intent` on each keystroke — the buffer is a value, never surgically patched.

**What ends the current syllable (commit + reset):**

- Whitespace: space, tab, return/enter.
- Punctuation and any non-letter, non-transform character (`. , ; ! ? ( ) " ' -` …).
- Navigation / focus changes: arrow keys, Home/End/PageUp/Down, Escape.
- **Mouse click** (caret may have moved — the input layer signals this).
- **App switch / focus change** (the input layer signals it).
- A keystroke that cannot extend the current parse into any legal Vietnamese syllable **and** is not a transform key → commit what we have (restore-if-invalid per §5.5), then start a fresh syllable with that key.

On reset: `intent = []`, `Syllable` cleared, no diacritic/tone memory carried across the boundary (each Vietnamese syllable is independent). Smart-switch-key state (Vietnamese/English + code table per app) lives *outside* the syllable buffer and is not touched by a reset.

**Backspace within a word — the "restore diacritic" model.** Backspace pops the **last `KeyIntent`** and re-derives the whole syllable, then diffs (§7). Because tone/marks are attributes recomputed by §4 on every derivation, removing a letter automatically re-places the tone:

- Word `tùy` (nucleus `u y`, huyền on `u` in modern style). User types `a` → nucleus becomes `u y a` (triphthong `uya`) → §4 triphthong rule moves the tone to the **middle** vowel → renders `tuỳa`. User presses **Backspace** → pop the `a` intent → nucleus back to `u y` → §4 re-places tone on `u` → renders **`tùy`**. The diacritic "restores" with zero special-case code: it is simply the re-render of the smaller syllable.

This is the payoff of the structured model from §1: buffer edits are *pops of intent + full re-derivation*, and every hard behavior (tone re-placement, diacritic restore, output-table switch, restore-if-invalid) falls out of re-rendering a value.

---

## Open questions

1. **Simple Telex 1 vs 2 exact parity.** Our definitions in §2.5 are clean-room and self-consistent, but OpenKey's precise behavior differs subtly and we cannot read its GPL source. Decide whether we (a) publish our own canonical spec and validate against OpenKey by black-box testing, or (b) match OpenKey bug-for-bug. Recommend (a).
2. **`z` / VNI `0` default.** Default is "remove tone only." Confirm whether `zAlsoStripsDiacritics` should default on for power users, and whether VNI `0` (remove tone) is enabled by default.
3. **Backspace deletion granularity per app** (§7). Needs an empirical per-app quirk table for combining/legacy output. Concrete question: which target apps delete a whole grapheme cluster vs one combining mark per Delete? Until mapped, non-NFC live editing falls back to whole-syllable retype.
4. **Legacy byte-table sources.** TCVN3 (ABC), VNI-Windows, and CP1258 need exact, verified code-unit tables (especially the 2-byte uppercase-toned cases). Source and license of these tables must be confirmed; they should be authored as our own data.
5. **`y` vs `i` normalization** (`Mỹ`/`Mĩ`, `lý`/`lí`, `hoà`/`hòa` already handled). Should Keystone offer an orthography normalizer for the `y↔i` single-vowel case, and if so is it on by default? This interacts with, but is separate from, the modern/old tone toggle.
6. **`gi`/`qu` deep edges.** `gìn`, `gịt`, `quốc` are handled, but confirm behavior for rare/loan forms and for a user typing `gi` intending literal English `gi...`. The reparse fallback (§4.4) needs test coverage.
7. **Auto-`ươ` completion policy.** When exactly should typing horn on `uo` promote *both* letters (`nước`) vs only the touched one? Define the trigger precisely (touched-letter-only vs nucleus-wide) and confirm against user expectation.
8. **Stop-coda tone conflict UX.** When a user applies an illegal tone to a stop-closed syllable (§5.4), do we silently refuse, hold pending, or emit literal? Pick one default.
9. **Macro / gõ tắt interaction.** Where in the pipeline do text-expansion macros fire relative to syllable commit — before restore-if-invalid, or after? This affects whether a macro key can appear mid-syllable.
10. **Modern vs old default.** Confirm Keystone ships **modern (kiểu mới)** as the default orthography (industry standard since Unicode era), with old (kiểu cũ) as an opt-in.# macOS Input Layer — CGEventTap, Robustness, Permissions

This layer is the only part of Keystone that touches macOS. It owns the event tap, feeds keystrokes into the pure engine, and executes the engine's `EngineResult` by synthesizing events. Everything OpenKey got wrong lived here, so the design below is organized around *never* letting the tap die silently and *never* letting the callback run slow.

## 1. Overall design

A single class, `KeyTapController`, owns the tap and its lifecycle. It runs the tap on a **dedicated thread with its own run loop**, not the main thread. Rationale: the tap callback must never be blocked by SwiftUI/AppKit work, and conversely notification handlers on the main thread must never stall the tap. The engine call itself is pure string manipulation and is safe to run inline on the tap thread.

```swift
final class KeyTapController {
    private var tapPort: CFMachPort?          // ARC-managed CFMachPort (owned)
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    private let engine: Engine                // pure, injected
    private let synthSource: CGEventSource     // private-state source (see §5)
    private let cache: SystemStateCache        // §3

    // magic tag written into every event we synthesize (§5)
    static let selfTag: Int64 = 0x4B_53_54_4F_4E_45 // "KSTONE"
}
```

Tap creation (called on the tap thread):

```swift
let mask: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue)   |
    (1 << CGEventType.flagsChanged.rawValue)
// mouse events are observed only to reset engine word-state on click; see note below.
    | (1 << CGEventType.leftMouseDown.rawValue)
    | (1 << CGEventType.rightMouseDown.rawValue)

guard let port = CGEvent.tapCreate(
    tap: .cgSessionEventTap,          // session-level: sees all apps in this login session
    place: .headInsertEventTap,       // in front of other taps so we transform first
    options: .defaultTap,             // NOT listenOnly — we must suppress & inject
    eventsOfInterest: mask,
    callback: tapCallback,            // bare C function, no captures
    userInfo: Unmanaged.passUnretained(self).toOpaque()
) else {
    // creation failed → almost always a permissions problem (§6)
    handleTapCreationFailure()
    return
}
self.tapPort = port

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    .takeRetainedValue()              // Get-rule creator → takeRetained (§4)
self.runLoopSource = source
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: port, enable: true)
```

The callback is a top-level function (C function pointers can't capture Swift context):

```swift
private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let me = Unmanaged<KeyTapController>.fromOpaque(refcon!).takeUnretainedValue()
    return me.handle(proxy: proxy, type: type, event: event)
}
```

`handle` is where the real logic sits (§2, §3, §5). For a keyDown that the engine transforms, we **suppress the original** (`return nil`) and post our own sequence; for anything we don't transform we `return Unmanaged.passUnretained(event)`.

**Executing an `EngineResult` = { backspaceCount, outputText }:**

```swift
func execute(_ result: EngineResult, proxy: CGEventTapProxy) {
    // 1. Backspaces: keycode 51 (kVK_Delete), down+up pairs.
    for _ in 0..<result.backspaceCount {
        postSynthetic(virtualKey: 51, keyDown: true,  proxy: proxy)
        postSynthetic(virtualKey: 51, keyDown: false, proxy: proxy)
    }
    // 2. Output text as a Unicode string carried on a synthetic key event.
    if !result.outputText.isEmpty {
        postUnicode(result.outputText, proxy: proxy)
    }
}

private func postSynthetic(virtualKey: CGKeyCode, keyDown: Bool, proxy: CGEventTapProxy) {
    guard let e = CGEvent(keyboardEventSource: synthSource,
                          virtualKey: virtualKey, keyDown: keyDown) else { return }
    e.flags = []                                        // don't inherit stray modifiers
    e.setIntegerValueField(.eventSourceUserData, value: Self.selfTag) // §5
    e.tapPostEvent(proxy)                               // ARC frees e (§4)
}

private func postUnicode(_ s: String, proxy: CGEventTapProxy) {
    guard let down = CGEvent(keyboardEventSource: synthSource, virtualKey: 0, keyDown: true),
          let up   = CGEvent(keyboardEventSource: synthSource, virtualKey: 0, keyDown: false)
    else { return }
    let utf16 = Array(s.utf16)
    utf16.withUnsafeBufferPointer { buf in
        down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
    }
    for e in [down, up] {
        e.flags = []
        e.setIntegerValueField(.eventSourceUserData, value: Self.selfTag)
        e.tapPostEvent(proxy)
    }
}
```

Notes on execution correctness:
- We post through the **proxy** (`tapPostEvent(_:)`), not `CGEvent.post(tap:)`. Posting through the proxy re-injects at the tap's own point in the stream, which is the documented path for a transforming tap and keeps ordering sane.
- The original keyUp for the physical key: when we suppress a keyDown we generally let the matching keyUp pass through untouched (it carries our `selfTag`? — no, it doesn't, it's the real key, so it re-enters and the engine must treat a bare keyUp as a no-op). Cleaner: the engine only acts on keyDown; keyUp/flagsChanged are used only for state (modifier tracking, word-break) and are always passed through.
- Mouse-down and flagsChanged are observed to tell the engine "the word buffer is broken" (user clicked elsewhere, pressed an arrow/modifier combo), then passed through unchanged. This replaces per-keystroke context probing.
- Edge case: a few apps (some terminals, certain Electron/Chromium text fields) mishandle a multi-character `keyboardSetUnicodeString` on one event. Fallback strategy (config-gated, per-app): emit one event per UTF-16 unit, or per grapheme. Keep this behind the smart-switch per-app store so we can quirk specific bundle ids without slowing the common path.

## 2. THE FIX for "typing suddenly stops" — two independent layers

macOS disables a tap and delivers a synthetic event of type `.tapDisabledByTimeout` (callback took too long, tripping the watchdog) or `.tapDisabledByUserInput` (user did something the system uses to defensively disable taps). OpenKey never handled these, so once disabled the tap stayed dead forever. We handle it in **two** places, and we need both.

**Layer A — re-enable inside the callback (instant, event-driven):**

```swift
func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = tapPort { CGEvent.tapEnable(tap: port, enable: true) }
        return nil
    }
    // ... normal handling ...
}
```

This fires the instant the system tells us it disabled the tap — as long as the tap thread's run loop is being serviced (it is, because the run loop delivered this very event).

**Layer B — periodic watchdog (backstop, poll-driven):**

A `DispatchSourceTimer` on a dedicated queue firing every ~1.5 s:

```swift
watchdog = DispatchSource.makeTimerSource(queue: watchdogQueue)
watchdog.schedule(deadline: .now() + 1.5, repeating: 1.5, leeway: .milliseconds(500))
watchdog.setEventHandler { [weak self] in
    guard let self, let port = self.tapPort else { return }
    if !CGEvent.tapIsEnabled(tap: port) {
        CGEvent.tapEnable(tap: port, enable: true)
    }
}
watchdog.resume()
```

**Why both are needed.** Layer A cannot cover every case: the disable event is only delivered if the run loop is actually being pumped, and there are situations where either no disable event is observed by us or the run loop was momentarily starved (heavy system load, a debugger pause, a thread that briefly blocked). There are also disables that don't originate a delivered `.tapDisabledBy*` event to *our* callback — e.g. a permissions or secure-input transition. Layer B guarantees eventual recovery within a couple of seconds no matter how the tap died, at negligible cost (one `CGEventTapIsEnabled` call per tick). Layer A gives sub-millisecond recovery in the common case so the user doesn't even notice a dropped keystroke; Layer B is the promise that it can never stay dead. `CGEvent.tapIsEnabled` returning false while re-enabling repeatedly is harmless.

## 3. Keeping the callback fast — no heavy work on the hot path

The watchdog timeout exists because the OS measures how long our callback takes. Every OpenKey slowdown was a *system query on the hot path*. Rule: **the callback may only touch the engine and a small in-memory cache.** No `CGWindowListCopyWindowInfo`, no `NSWorkspace.frontmostApplication`, no `TIS*`, no allocation-heavy work per keystroke.

`SystemStateCache` holds a small value snapshot, updated only by low-frequency events, read under a tiny lock:

```swift
struct SystemState {
    var frontAppBundleID: String?
    var keyboardLayoutID: String?     // from TIS, cached
    var spotlightLikelyVisible: Bool  // best-effort, see caveat
    var secureInputActive: Bool       // §7
}

final class SystemStateCache {
    private var state = SystemState()
    private var lock = os_unfair_lock()
    func snapshot() -> SystemState { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return state }
    func mutate(_ f: (inout SystemState) -> Void) { os_unfair_lock_lock(&lock); f(&state); os_unfair_lock_unlock(&lock) }
}
```

**Cache population / invalidation (all off the hot path):**
- `frontAppBundleID`: subscribe to `NSWorkspace.shared.notificationCenter` for `didActivateApplicationNotification`; read `note.userInfo[NSWorkspace.applicationUserInfoKey]?.bundleIdentifier` (or `NSWorkspace.shared.frontmostApplication`) *in the handler* and write into the cache. Never query in the callback. This is also exactly what drives smart-switch-key (Vietnamese/English + code table per app).
- `keyboardLayoutID`: read once at startup via `TISCopyCurrentKeyboardInputSource`, then refresh on the `kTISNotifySelectedKeyboardInputSourceChanged` distributed notification. Never call `TIS*` per keystroke (OpenKey did — this was a real cost).
- `secureInputActive`: poll `IsSecureEventInputEnabled()` in the same low-frequency watchdog/timer, plus refresh on app-activation (§7).
- `spotlightLikelyVisible`: **honest caveat** — there is no clean, cheap, public signal for "Spotlight is showing." OpenKey's per-keystroke `CGWindowListCopyWindowInfo` was the expensive mistake. Options, none perfect: (a) drop the special case entirely and treat Spotlight like any other app via bundle id where possible; (b) if a window-level check is truly required, run `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` at most once per activation change on a background queue and cache the boolean. I recommend starting with (a) and only adding (b) if field testing shows Spotlight needs special handling. Flagged in Open Questions.

Thread-safety: notifications arrive on the main thread; the callback reads on the tap thread. `os_unfair_lock` around a small struct copy is far cheaper than any system call and does not risk the watchdog.

## 4. Correct CoreFoundation memory management

OpenKey's crashes came from Get-rule vs Create/Copy-rule confusion in C: `CFRelease` on a pointer from `CFArrayGetValueAtIndex` (a *Get* — you don't own it → over-release), and a leaked `TISInputSource` on an early return (a *Copy* — you do own it → never released). In Swift these classes of bug are avoidable by using the bridging correctly and almost never calling `CFRelease` by hand.

Rules for this layer:
- **Swift-native CG constructors are ARC-managed.** `CGEvent(keyboardEventSource:…)`, `CGEventSource(stateID:)`, and `CGEvent.tapCreate(...)`'s returned `CFMachPort?` are all owned references managed by ARC. Do **not** call `CFRelease` on them; let them deinit. This alone kills the over-release bug.
- **`Unmanaged` only at the C boundary.** The refcon round-trip uses `Unmanaged.passUnretained(self).toOpaque()` / `.fromOpaque(_).takeUnretainedValue()` — unretained because the controller outlives the tap by construction. The callback's return uses `Unmanaged.passUnretained(event)` for pass-through (we don't own `event`, we're handing it back) and `nil` for suppression.
- **`CFMachPortCreateRunLoopSource` is a Create-rule function** → `.takeRetainedValue()` to take ownership into an ARC `CFRunLoopSource` (stored on `self`, removed with `CFRunLoopRemoveSource` on teardown).
- **Any `TIS*` copy must use `.takeRetainedValue()`.** `TISCopyCurrentKeyboardInputSource()` returns `Unmanaged<TISInputSource>!` → immediately `.takeRetainedValue()`; never keep the `Unmanaged` around, which is how OpenKey leaked on early return.
- **`kAXTrustedCheckOptionPrompt`** is a `CFString` global exposed as `Unmanaged` — use `.takeUnretainedValue()` (Get-rule constant).
- **Synthetic events we post**: `CGEvent(...)` returns an owned reference; after `tapPostEvent(proxy)` we simply let it go out of scope and ARC releases it. No manual release, no leak.
- If we ever drop to `CFArrayGetValueAtIndex` (e.g. the optional Spotlight window scan), the returned pointer is **Get-rule** → wrap as `Unmanaged.fromOpaque(ptr).takeUnretainedValue()`, never `takeRetainedValue`, never `CFRelease`.

## 5. Avoiding infinite recursion on our own output

Our synthetic backspaces and Unicode events flow back through `.cgSessionEventTap` and re-enter our own callback. Without a guard we'd reprocess our own output forever. Two mechanisms; we use both belt-and-suspenders but the userData tag is primary:

1. **Private event source + magic userData tag.** All synthetic events are created with a `CGEventSource(stateID: .privateState)` stored as `synthSource`, and each event gets `setIntegerValueField(.eventSourceUserData, value: Self.selfTag)`. At the very top of `handle`, before touching the engine:

```swift
if event.getIntegerValueField(.eventSourceUserData) == Self.selfTag {
    return Unmanaged.passUnretained(event)   // our own event → pass straight through
}
```

2. **Source-state check as secondary.** We can also compare `event.getIntegerValueField(.eventSourceStateID)` against `synthSource.sourceStateID`. This is what OpenKey keys off; the userData tag is more robust because it survives even if the OS coalesces or re-sources events, and it's a single 64-bit compare — trivial on the hot path.

The self-check is the first thing the callback does, so re-entrant synthetic events cost one integer read and a pass-through.

## 6. Permissions on macOS 26/27

**Accessibility is mandatory** for a `.defaultTap` session tap that transforms keyboard input. Check and prompt:

```swift
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(opts)
```

Behavior and handling:
- If not trusted, `CGEvent.tapCreate` returns `nil`. Treat a `nil` from `tapCreate` as "permission missing or revoked," surface a clear onboarding panel (open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`), and **do not retry in a tight loop.**
- **Re-checking after grant:** the system does not reliably notify us the instant the user flips the toggle, and historically a freshly granted Accessibility permission may only fully take effect for a relaunched process. Strategy: poll `AXIsProcessTrusted()` (the no-prompt variant) on a low-frequency timer while the onboarding panel is up; when it flips to true, attempt `tapCreate`. If tap creation still fails immediately after grant, offer a one-click relaunch. Flagged in Open Questions because the "grant takes effect without relaunch" behavior has historically been version-dependent and I can't assert macOS 27's exact behavior.
- **Input Monitoring (TCC "ListenEvent"):** whether a keyboard `CGEventTap` additionally trips the Input Monitoring prompt has been inconsistent across releases and tap types (listen-only HID monitoring definitely needs it; a transforming session tap has historically been gated on Accessibility). I will **not** assert what macOS 27 does. Defensive design: probe both. Query `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`; if it returns `kIOHIDAccessTypeDenied`/`Unknown`, guide the user to Input Monitoring as well (`…Privacy_ListenEvent`). Request with `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`. Never block startup on Input Monitoring if the tap creates successfully with Accessibility alone — only escalate if `tapCreate` fails despite Accessibility being granted.
- **Runtime revocation:** if the user revokes Accessibility while running, the tap stops delivering and/or `tapIsEnabled` reads false while re-enable fails, and a rebuild's `tapCreate` returns `nil`. The watchdog (§2 Layer B) already detects a dead tap; when re-enable/rebuild fails, transition to a "permission lost" UI state (menu-bar icon change + panel) rather than spinning. Re-arm the low-frequency grant poll to recover automatically when permission returns.

## 7. Secure input mode

When a password field (or any app) calls `EnableSecureEventInput`, the system routes key events through a secure path and a session event tap may stop seeing keystrokes. This is by design and must not be fought.

- Detect with `IsSecureEventInputEnabled()` (HIToolbox/Carbon). Refresh this in the low-frequency timer and on app activation; store in the cache (`secureInputActive`).
- When active: **degrade gracefully** — stop attempting transforms (the engine won't get keys anyway), reset the engine's in-progress word buffer (so we don't emit a stale composition when secure input ends), and show a subtle menu-bar indicator that input is paused. Do not warn aggressively; secure input is normal (login/password fields).
- When it clears, resume normally. No tap rebuild needed — the tap was never disabled, it just wasn't fed.

## 8. Sleep/wake and fast user switching

- **Sleep/wake:** subscribe to `NSWorkspace.shared.notificationCenter` `willSleepNotification` / `didWakeNotification`. On wake, proactively **rebuild the tap** (remove run-loop source, drop the `CFMachPort`, recreate) rather than trusting that it survived. Even though the §2 watchdog would eventually re-enable a merely-disabled tap, a full rebuild on wake covers the case where the mach port itself was invalidated across sleep. Cheap and belt-and-suspenders.
- **Fast user switching:** subscribe to `sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification` (NSWorkspace). On resign, disable the tap and pause the watchdog (our session isn't foreground). On become-active, re-enable/rebuild. This prevents a background session's tap from doing work and avoids fighting the foreground session.
- **Single instance per user:** the tap is session-scoped, so two Keystone processes in one login session would double-process every key. Enforce one instance per user: on launch, take an exclusive `flock` on a lock file in the app container (or check `NSRunningApplication.runningApplications(withBundleIdentifier: "com.tanta.keystone")` and bail if another instance is already active), and exit/hand off if the lock is held. This is per-user, so a second logged-in user running their own copy is fine and expected.

---

## Open questions

1. **Spotlight / overlay detection without per-keystroke cost.** Is a special case even needed on macOS 27, and if so what's the cheapest reliable signal? Current plan is to drop it and revisit only if field testing shows breakage. Needs empirical testing against Spotlight, Alfred/Raycast, and Mission Control.
2. **Accessibility grant taking effect without relaunch on macOS 27.** Historically flaky/version-dependent. Need to verify on-device whether `tapCreate` succeeds immediately after the user grants, or whether we must relaunch — this changes the onboarding UX.
3. **Does macOS 27 additionally require Input Monitoring for a transforming session tap?** Must be verified empirically; the defensive dual-probe (§6) works either way but the onboarding copy depends on the answer.
4. **Multi-character `keyboardSetUnicodeString` reliability across apps.** Which bundle ids need per-grapheme fallback (terminals, Electron, VS Code, some Java/JetBrains IDEs)? Build a quirks list keyed to the smart-switch per-app store; needs a compatibility test matrix.
5. **Tap thread vs main thread for the run loop.** Recommending a dedicated thread for isolation, but need to confirm no interaction issues with SwiftUI/AppKit notification delivery latency feeding the cache under sustained typing.
6. **Original keyUp handling after suppressing keyDown.** Confirm no apps end up with a "stuck key" perception when we swallow a keyDown but let the physical keyUp pass; test with games/apps that track key state directly.
7. **InputMethodKit alternative (post-v1).** IMK avoids most of §6/§7 (no Accessibility, no secure-input blindness) but changes the whole model. Worth a spike to quantify how much of this layer it would retire.
8. **Watchdog interval tuning.** 1.5 s is a starting guess balancing recovery latency vs. wakeups; validate against battery impact and worst-case perceived downtime.# App Shell & UI — SwiftUI for macOS 26/27

This section specifies the entire user-facing surface of Keystone: the process shape, the menu-bar surface, the Control Panel, the Macros and Convert tools, the onboarding/permissions flow, the design system (Liquid Glass), and how UI state is bound to the pure engine. All UI is SwiftUI; only three thin `NSViewRepresentable`/AppKit escape hatches are needed (hotkey capture, menu-bar template rendering, and the System Settings deep-link), called out explicitly.

Everything below assumes the engine is a pure value-type module (`KeystoneEngine`) and that a separate `InputController` (event-tap owner) consumes an `EngineConfig`. The UI never talks to the event tap directly — it mutates a single observable settings store, and the input layer observes that store.

---

## 1. App shape

### 1.1 Process type — agent app, no Dock icon by default

Keystone is an `LSUIElement` agent. This is set in `Info.plist` (not via runtime `setActivationPolicy` as the baseline), so the app never bounces in the Dock at launch and has no Dock icon by default.

```xml
<!-- Info.plist -->
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>CFBundleIdentifier</key><string>com.tanta.keystone</string>
<!-- We DO NOT declare NSAppleEventsUsageDescription etc. we don't use. -->
```

The optional "Show Dock icon" toggle flips activation policy at runtime — this is the one legitimate runtime use:

```swift
// DockIconController.swift
@MainActor
enum DockIconController {
    static func apply(showDock: Bool) {
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        // .accessory keeps menu-bar + windows but no Dock tile;
        // .regular adds the Dock tile and app menu.
    }
}
```

> Edge case: an `.accessory` app cannot make a window key/main via normal ordering; when we open the Control Panel we must call `NSApp.activate(ignoringOtherApps: true)` first, otherwise the window opens behind the frontmost app and can't receive focus. See §2.3.

### 1.2 App entry point & scenes

```swift
@main
struct KeystoneApp: App {
    // The single source of truth for all user-visible options.
    @State private var store = SettingsStore.shared
    // Owns the CGEventTap; created once, observes `store`.
    @State private var input = InputController.shared
    @State private var permissions = PermissionsModel()

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // --- Primary surface: the menu-bar item ---
        MenuBarExtra {
            MenuBarContent()
                .environment(store)
                .environment(permissions)
        } label: {
            MenuBarLabel(state: store.menuBarState)   // VN/EN template icon
        }
        .menuBarExtraStyle(.menu)   // native pull-down menu (see §1.3 for .window variant)

        // --- Control Panel (main settings window) ---
        Window("Keystone", id: WindowID.controlPanel) {
            ControlPanelView()
                .environment(store)
                .environment(permissions)
                .frame(minWidth: 680, minHeight: 460)
        }
        .windowResizability(.contentSize)
        .windowStyle(.automatic)      // gets the standard title bar; Liquid Glass sidebar inside
        .defaultLaunchBehavior(.suppressed)  // never auto-open at launch

        // --- Onboarding / permissions (first run) ---
        Window("Welcome to Keystone", id: WindowID.onboarding) {
            OnboardingView()
                .environment(permissions)
                .frame(width: 560, height: 620)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // --- Macros editor ---
        Window("Macros", id: WindowID.macros) {
            MacrosView().environment(store).frame(minWidth: 620, minHeight: 440)
        }

        // --- Convert tool ---
        Window("Convert", id: WindowID.convert) {
            ConvertView().environment(store).frame(minWidth: 620, minHeight: 520)
        }
    }
}

enum WindowID {
    static let controlPanel = "control-panel"
    static let onboarding   = "onboarding"
    static let macros       = "macros"
    static let convert      = "convert"
}
```

Notes:
- We use explicit `Window` scenes rather than the `Settings` scene because (a) an agent app can't reliably present the `Settings` scene without extra activation dances, and (b) we want a bespoke Liquid Glass layout, not the system preferences chrome. Each is a singleton `Window` (not `WindowGroup`) so re-opening focuses the existing one.
- `.defaultLaunchBehavior(.suppressed)` (macOS 15+) keeps these windows closed at launch; the menu-bar item is the only thing that appears.
- First-run logic: in an `.task` on `MenuBarContent` (or an `onAppear` of a tiny bootstrap), check `permissions.needsOnboarding` and call `openWindow(id: .onboarding)` + `NSApp.activate(...)`.

### 1.3 The menu-bar menu

Two viable styles; we ship `.menu` for v1 (fastest, most native, keyboard-navigable, matches OpenKey muscle memory), and keep `.window` as a documented alternative for a richer popover later.

The label reflects **enabled + VN/EN** state at a glance:

```swift
struct MenuBarLabel: View {
    let state: MenuBarState  // .vietnamese, .english, .disabled
    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(for: state))
            .accessibilityLabel(state.accessibilityLabel)
    }
}
```

Menu contents, in order (matches the required feature list):

```swift
struct MenuBarContent: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = store

        // 1) Enable/disable Vietnamese — with checkmark + hotkey hint
        Toggle(isOn: $store.vietnameseEnabled) {
            Label(store.vietnameseEnabled ? "Vietnamese (VN)" : "English (EN)",
                  systemImage: store.vietnameseEnabled ? "character.bubble" : "a.circle")
        }
        .keyboardShortcut(store.switchLanguageShortcut)   // shows accessory glyph in menu

        Divider()

        // 2) Input method
        Picker("Input Method", selection: $store.inputMethod) {
            Text("Telex").tag(InputMethod.telex)
            Text("VNI").tag(InputMethod.vni)
            Text("Simple Telex 1").tag(InputMethod.simpleTelex1)
            Text("Simple Telex 2").tag(InputMethod.simpleTelex2)
        }
        .pickerStyle(.menu)   // becomes a submenu inside the menu-bar menu

        // 3) Code table (output charset)
        Picker("Code Table", selection: $store.codeTable) {
            Text("Unicode").tag(CodeTable.unicode)
            Text("TCVN3 (ABC)").tag(CodeTable.tcvn3)
            Text("VNI Windows").tag(CodeTable.vniWindows)
            Text("Unicode Compound").tag(CodeTable.unicodeCompound)
            Text("Vietnamese CP1258").tag(CodeTable.cp1258)
        }
        .pickerStyle(.menu)

        Divider()

        Button("Control Panel…") { open(.controlPanel) }
            .keyboardShortcut(",", modifiers: .command)
        Button("Macros…")        { open(.macros) }
        Button("Convert Tool…")  { open(.convert) }

        Divider()

        Toggle("Temporarily Off", isOn: $store.temporarilyOff)
        Button("About Keystone") { open(.controlPanel, tab: .about) }
        Button("Quit Keystone") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func open(_ id: String, tab: ControlPanelTab? = nil) {
        if let tab { store.selectedTab = tab }
        NSApp.activate(ignoringOtherApps: true)   // agent app must self-activate
        openWindow(id: id)
    }
}
```

Design details:
- `Toggle` and `Picker` render with the native checkmark/submenu affordances inside `MenuBarExtra(.menu)`. No custom drawing needed.
- The enable/disable Toggle **is the same state** the hotkey and event tap read; toggling here is instant.
- Showing `store.switchLanguageShortcut` as the Toggle's `keyboardShortcut` gives the menu a right-aligned glyph hint (⌃⌘ etc.) for free, but the actual global hotkey is handled by the input layer (a menu shortcut only fires when a Keystone window is key). Document this: the menu glyph is informational.

---

## 2. Control Panel window

A `NavigationSplitView` with a Liquid Glass sidebar (source list) and a detail pane. This reads as a modern macOS 26 settings window rather than the old tab strip, scales to many sections, and localizes cleanly.

### 2.1 Tab/section taxonomy

```swift
enum ControlPanelTab: String, CaseIterable, Identifiable {
    case general      // input method, code table, run at login, dock icon, updates
    case typing       // spelling, orthography, quick telex, restore-if-invalid,
                       // z/f/w/j, quick start/end consonant, uppercase-first-letter
    case perApp       // remember code per app, smart switch
    case shortcuts    // temp-off hotkey, switch-language hotkey, convert-clipboard hotkey
    case macros       // (embeds MacrosView, or a "Open Macros" launcher)
    case about        // version, license, credits, check for updates
    var id: String { rawValue }
}
```

Rationale for grouping (7 sections keeps each pane short and scannable):

| Section | Contents |
|---|---|
| **General** | Input method, Code table, Run at login, Show Dock icon, Automatically check for updates |
| **Typing** | Spelling check (restore-if-invalid), Modern vs old orthography (òa/oà), Quick Telex, Allow `z f w j` as consonants, Quick start-consonant / Quick end-consonant, Auto-capitalize first letter of sentence |
| **Per-App** | Remember input state per app, Remember code table per app (smart switch), the learned-apps list with reset |
| **Shortcuts** | Switch-language hotkey, Temporarily-off hotkey, Quick-convert-clipboard hotkey |
| **Macros** | Launches / embeds the Macros editor (§3) |
| **About** | Icon, version, build, license, homepage, "Check for Updates now" |

### 2.2 Structure

```swift
struct ControlPanelView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(ControlPanelTab.allCases, selection: $store.selectedTab) { tab in
                Label(tab.title, systemImage: tab.symbol)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
            .listStyle(.sidebar)   // gets Liquid Glass sidebar material automatically on 26
        } detail: {
            Group {
                switch store.selectedTab {
                case .general:   GeneralPane()
                case .typing:    TypingPane()
                case .perApp:    PerAppPane()
                case .shortcuts: ShortcutsPane()
                case .macros:    MacrosLauncherPane()
                case .about:     AboutPane()
                case nil:        GeneralPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
        }
    }
}
```

Panes use `Form { Section {...} }` with `.formStyle(.grouped)` — this is the canonical macOS settings look and on macOS 26 the grouped rows sit on Liquid Glass surfaces automatically.

```swift
struct TypingPane: View {
    @Environment(SettingsStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section("Spelling") {
                Toggle("Check spelling", isOn: $store.spellCheck)
                Toggle("Restore keystrokes if word is invalid",
                       isOn: $store.restoreIfInvalid)
                    .disabled(!store.spellCheck)
                    .help("If a word can't be a valid Vietnamese syllable, "
                          + "put back the raw keys you typed.")
            }
            Section("Orthography") {
                Picker("Tone mark placement", selection: $store.orthography) {
                    Text("Modern (hòa)").tag(Orthography.modern)
                    Text("Classic (hoà)").tag(Orthography.classic)
                }
            }
            Section("Telex options") {
                Toggle("Quick Telex (cc→ch, gg→gi…)", isOn: $store.quickTelex)
                Toggle("Allow z, f, w, j as consonants", isOn: $store.allowZFWJ)
                Toggle("Quick start consonant (f→ph, …)", isOn: $store.quickStartConsonant)
                Toggle("Quick end consonant (g→ng, …)", isOn: $store.quickEndConsonant)
            }
            Section("Capitalization") {
                Toggle("Auto-capitalize first letter of a sentence",
                       isOn: $store.autoCapitalize)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Typing")
    }
}
```

### 2.3 Opening from an agent app

Any command that opens a Control Panel window must self-activate first (`NSApp.activate(ignoringOtherApps: true)`), then `openWindow(id:)`. When the last window closes we do **not** terminate (agent app persists in the menu bar); this is the default for a non-`WindowGroup` menu-bar app, but be explicit: do not adopt `.terminateAfterLastWindowClosed` behavior.

---

## 3. Macros editor (gõ tắt)

A two-column layout: a searchable `Table` of macros on the left/top, an inline editor. Macros are `trigger → replacement` with per-macro flags.

```swift
struct Macro: Identifiable, Codable, Hashable {
    var id = UUID()
    var trigger: String        // e.g. "vn"
    var replacement: String    // e.g. "Việt Nam"
    var expandInEnglishMode: Bool = false
    var autoCapitalize: Bool = false   // honor sentence-initial caps of trigger
    var enabled: Bool = true
}

@Observable @MainActor
final class MacroStore {
    var macros: [Macro] = []
    // Persisted separately from SettingsStore (can be large); JSON file in App Support.
    func add(); func delete(_ ids: Set<Macro.ID>)
    func importFile(_ url: URL) throws   // .json and legacy tab-separated .txt
    func exportFile(to url: URL) throws
}
```

```swift
struct MacrosView: View {
    @Environment(MacroStore.self) private var macros
    @State private var selection: Set<Macro.ID> = []
    @State private var query = ""

    var body: some View {
        @Bindable var macros = macros
        VStack(spacing: 0) {
            Table(filtered, selection: $selection) {
                TableColumn("On") { m in Toggle("", isOn: bind(m, \.enabled)).labelsHidden() }
                    .width(36)
                TableColumn("Trigger", value: \.trigger)
                TableColumn("Replacement", value: \.replacement)
                TableColumn("EN") { m in
                    Image(systemName: m.expandInEnglishMode ? "checkmark" : "")
                }.width(36)
            }
            .searchable(text: $query)

            Divider()
            // Inline editor for the single selected macro
            if let id = selection.first, let m = binding(for: id) {
                MacroEditor(macro: m)
                    .padding()
                    .background(.regularMaterial)   // Liquid Glass footer editor
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { macros.add() } label: { Image(systemName: "plus") }
                Button { macros.delete(selection) } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                Spacer()
                Menu {
                    Button("Import…") { importPanel() }
                    Button("Export…") { exportPanel() }
                } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .navigationTitle("Macros")
    }
}
```

Behavior contract for the engine/input layer (UI just stores it):
- **`expandInEnglishMode`** — when Vietnamese is off, only macros with this flag expand.
- **`autoCapitalize`** — if the trigger is typed at a sentence start, capitalize the first letter of the replacement.
- Import supports legacy OpenKey macro format (tab-separated) plus native JSON. Export writes JSON (round-trips flags).
- Triggers are matched by the engine's word-buffer logic; the UI must warn on duplicate triggers (inline validation, not a blocking modal).

---

## 4. Convert tool

Two-pane converter: source text on top, converted output below, with code-table + case transforms. Plus a headless "quick-convert clipboard" action bound to a hotkey.

```swift
struct ConvertView: View {
    @Environment(SettingsStore.self) private var store
    @State private var input = ""
    @State private var fromTable: CodeTable = .unicode
    @State private var toTable: CodeTable = .tcvn3
    @State private var caseTransform: CaseTransform = .none

    private var output: String {
        Converter.convert(input, from: fromTable, to: toTable, case: caseTransform)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("From", selection: $fromTable) { codeTableItems() }
                Image(systemName: "arrow.right")
                Picker("To", selection: $toTable) { codeTableItems() }
                Button { swap(&fromTable, &toTable) } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                Picker("Case", selection: $caseTransform) {
                    Text("As-is").tag(CaseTransform.none)
                    Text("lowercase").tag(CaseTransform.lower)
                    Text("UPPERCASE").tag(CaseTransform.upper)
                    Text("Title Case").tag(CaseTransform.title)
                    Text("Sentence case").tag(CaseTransform.sentence)
                }
            }
            TextEditor(text: $input)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            HStack {
                Button("Paste from Clipboard") { input = NSPasteboard.string() ?? input }
                Spacer()
                Button("Copy Result") { NSPasteboard.set(output) }
                    .buttonStyle(.glassProminent)   // macOS 26 prominent glass button
            }
            TextEditor(text: .constant(output))
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        .padding()
        .navigationTitle("Convert")
    }
}

enum CaseTransform { case none, lower, upper, title, sentence }
```

Quick-convert-clipboard: a global hotkey (owned by the input layer) reads the pasteboard, runs `Converter.convert` using the *current* code table settings (or a configured target), and rewrites the pasteboard, then posts a brief user notification / no UI. The Convert window is not needed for this path.

> Edge case: `Converter` must be a pure function shared with the engine's output stage, so window conversion and live typing produce identical bytes for a given code table. Do not fork the mapping tables.

---

## 5. Onboarding / permissions flow

A CGEventTap needs **Accessibility** (`AXIsProcessTrusted`); on some configurations the tap also benefits from **Input Monitoring** (`IOHIDCheckAccess(.listenEvent)`). We request/guide both, detect grant live, and never claim success we haven't verified.

### 5.1 Permissions model

```swift
@Observable @MainActor
final class PermissionsModel {
    private(set) var accessibility: Bool = AXIsProcessTrusted()
    private(set) var inputMonitoring: Bool = (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)

    var allGranted: Bool { accessibility && inputMonitoring }
    var needsOnboarding: Bool { !allGranted && !UserDefaults.standard.bool(forKey: "didFinishOnboarding") }

    private var timer: Timer?

    /// Poll while the onboarding window is visible. macOS does not push a
    /// notification when AX is granted, and the grant often requires an app
    /// relaunch — so we poll, and detect the "granted but not yet effective" case.
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Prompts (adds Keystone to the list) and opens the pane if needed.
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
    func requestInputMonitoring() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    func openSettings(_ pane: PrivacyPane) {
        NSWorkspace.shared.open(URL(string: pane.urlString)!)
    }
}

enum PrivacyPane {
    case accessibility, inputMonitoring
    var urlString: String {
        switch self {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
    }
}
```

### 5.2 The window

A friendly, single-column flow with two permission cards that update live from `PermissionsModel`. Uses Liquid Glass cards and SF Symbols.

```swift
struct OnboardingView: View {
    @Environment(PermissionsModel.self) private var perms
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image("MenuBarIconVN")   // app glyph, large
                    .resizable().frame(width: 72, height: 72)
                Text("Welcome to Keystone").font(.largeTitle.bold())
                Text("Type Vietnamese anywhere on your Mac.")
                    .foregroundStyle(.secondary)
            }

            PermissionCard(
                title: "Accessibility",
                detail: "Lets Keystone read and reshape your keystrokes into Vietnamese.",
                symbol: "accessibility",
                granted: perms.accessibility,
                primary: ("Grant Access", { perms.requestAccessibility() }),
                secondary: ("Open Settings", { perms.openSettings(.accessibility) })
            )

            PermissionCard(
                title: "Input Monitoring",
                detail: "Required so Keystone can observe keys system-wide.",
                symbol: "keyboard",
                granted: perms.inputMonitoring,
                primary: ("Grant Access", { perms.requestInputMonitoring() }),
                secondary: ("Open Settings", { perms.openSettings(.inputMonitoring) })
            )

            Spacer()

            Button(perms.allGranted ? "Start Typing" : "Continue Later") {
                UserDefaults.standard.set(true, forKey: "didFinishOnboarding")
                dismiss()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(false)   // never trap the user; they can defer
        }
        .padding(32)
        .background(.regularMaterial)
        .task { perms.startPolling() }
        .onDisappear { perms.stopPolling() }
        .onChange(of: perms.allGranted) { _, ok in
            if ok { InputController.shared.enableTap() }  // start tap the instant it's legal
        }
    }
}

struct PermissionCard: View {
    let title, detail, symbol: String
    let granted: Bool
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 28))
                .frame(width: 44)
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    if granted {
                        Label("Granted", systemImage: "checkmark.seal.fill")
                            .labelStyle(.iconOnly).foregroundStyle(.green)
                    }
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                VStack(spacing: 6) {
                    Button(primary.0, action: primary.1).buttonStyle(.glass)
                    Button(secondary.0, action: secondary.1).font(.caption)
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))   // macOS 26 Liquid Glass card
    }
}
```

Honesty / edge cases the flow must handle:
- **AX grant frequently requires a relaunch** for the trust to take effect for an already-running process. If `AXIsProcessTrusted()` stays false shortly after the user toggles Keystone on in Settings, show a "Restart Keystone" button (relaunch via a helper `Process`/`open` + `NSApp.terminate`). Do not spin forever.
- **Input Monitoring may not be strictly required** on all macOS 26/27 configs for a listen-only tap, but requesting it avoids the silent-drop failure mode; treat it as recommended and don't hard-block on it.
- We poll (1 s) only while the window is open, and stop on disappear — no background polling on the hot path.

---

## 6. Visual / design system

### 6.1 Liquid Glass adoption (macOS 26/27)

- **Sidebar & panes**: `List(.sidebar)` + `Form(.grouped)` pick up system glass automatically. Do not hand-roll blur.
- **Custom surfaces** (permission cards, macro editor footer, convert result box): `.glassEffect(.regular, in: .rect(cornerRadius:))`. Group adjacent glass elements in a `GlassEffectContainer` so their shapes merge/refract correctly:
  ```swift
  GlassEffectContainer(spacing: 16) {
      ForEach(cards) { PermissionCard(...) }
  }
  ```
- **Buttons**: `.buttonStyle(.glass)` for secondary, `.buttonStyle(.glassProminent)` for the primary CTA. Tint with `.glassEffect(.regular.tint(.accentColor).interactive())` when a control needs an accent.
- **Tinting/accent**: Use the system accent color; expose no custom theme in v1.
- Keep glass for chrome/controls, not for long text backgrounds (legibility). Body copy sits on `.regularMaterial` or the default window background.

### 6.2 Menu-bar icon (the important, subtle piece)

We need **template images** that adapt to light/dark menu bar AND encode VN/EN/disabled state. Approach:

- Render three states as `NSImage` from SF Symbols or bundled PDFs, marked `isTemplate = true` so macOS tints them for the current menu-bar appearance (works with the Liquid Glass / tinted menu bar). Template rendering means we ship **one** asset per state, not light+dark variants.
- State mapping: VN = filled/solid glyph; EN = outline glyph; disabled/temp-off = the glyph with a subtle slash or reduced weight.

```swift
enum MenuBarState { case vietnamese, english, disabled }

enum MenuBarIconRenderer {
    static func image(for state: MenuBarState) -> NSImage {
        let name: String
        switch state {
        case .vietnamese: name = "MenuVN"      // asset or SF Symbol config
        case .english:    name = "MenuEN"
        case .disabled:   name = "MenuOff"
        }
        let img = NSImage(named: name) ?? NSImage(systemSymbolName: "character.bubble",
                                                   accessibilityDescription: nil)!
        img.isTemplate = true       // <-- critical for light/dark tinting
        return img
    }
}
```

`SettingsStore.menuBarState` is derived: `temporarilyOff ? .disabled : (vietnameseEnabled ? .vietnamese : .english)`.

> Alternative: use SF Symbols directly in the `MenuBarExtra` label (`Image(systemName:)`), letting the system handle template tinting. We keep the `NSImage` renderer because we want a custom VN glyph that no SF Symbol matches, and a crisp slash overlay for the off state.

### 6.3 Accessibility & localization

- Every icon-only control gets `.accessibilityLabel`. The menu-bar item announces "Keystone — Vietnamese input on/off".
- Respect Dynamic Type (avoid fixed frames on text; use `minHeight` not `height`), Reduce Transparency (glass falls back to solid material — SwiftUI handles this, but verify permission cards remain legible), Increase Contrast, and full keyboard navigation (all panes are `Form`-based → focusable).
- **Localization: Vietnamese + English.** Use String Catalogs (`Localizable.xcstrings`). All UI strings are keys; ship `vi` and `en`. Default follows system language. Vietnamese is the flagship audience, so `vi` strings are first-class (reviewed, not machine-translated placeholders).
- Menu items, tab titles, permission copy, and macro/convert labels all localized. Code-table and input-method proper names (Telex, VNI, TCVN3, CP1258) stay untranslated.

---

## 7. Settings store & engine binding

The UI's entire job is to mutate **one** observable store; the input layer reads it. This is where OpenKey's per-keystroke queries are designed away: the input layer holds a plain-value `EngineConfig` snapshot and only rebuilds it when the store changes — never inside the tap callback.

```swift
@Observable @MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    // Persisted (each didSet writes to UserDefaults; see persistence note)
    var vietnameseEnabled = true
    var temporarilyOff = false
    var inputMethod: InputMethod = .telex
    var codeTable: CodeTable = .unicode
    var spellCheck = true
    var restoreIfInvalid = true
    var orthography: Orthography = .modern
    var quickTelex = false
    var allowZFWJ = false
    var quickStartConsonant = false
    var quickEndConsonant = false
    var autoCapitalize = false
    var rememberStatePerApp = true
    var smartSwitchCodeTable = true
    var runAtLogin = false
    var showDockIcon = false
    var checkForUpdates = true
    var switchLanguageShortcut: KeyboardShortcut? = .init("z", modifiers: [.control, .command])
    var tempOffShortcut: KeyCombo? = nil
    var quickConvertShortcut: KeyCombo? = nil

    // Transient UI state (not persisted)
    var selectedTab: ControlPanelTab? = .general

    var menuBarState: MenuBarState {
        temporarilyOff ? .disabled : (vietnameseEnabled ? .vietnamese : .english)
    }

    /// Pure snapshot the engine consumes. Rebuilt off the hot path.
    var engineConfig: EngineConfig {
        EngineConfig(inputMethod: inputMethod, codeTable: codeTable,
                     spellCheck: spellCheck, restoreIfInvalid: restoreIfInvalid,
                     orthography: orthography, quickTelex: quickTelex,
                     allowZFWJ: allowZFWJ, quickStartConsonant: quickStartConsonant,
                     quickEndConsonant: quickEndConsonant, autoCapitalize: autoCapitalize)
    }
}
```

### 7.1 How changes reach the running engine/input layer

The `InputController` observes the store with SwiftUI's `withObservationTracking` (works with `@Observable` outside a View) and pushes a fresh, immutable config to the tap's reader:

```swift
@MainActor
final class InputController {
    static let shared = InputController()
    private let store = SettingsStore.shared

    // The tap callback reads ONLY this atomic snapshot. No queries in the callback.
    private let liveConfig = ManagedAtomic<EngineConfig>(...)  // or os_unfair_lock-guarded box
    private var enabledSnapshot = ManagedAtomic<Bool>(true)

    func startObserving() { observeConfig(); observeEnabled() }

    private func observeConfig() {
        withObservationTracking {
            _ = store.engineConfig   // establish dependencies
        } onChange: {
            Task { @MainActor in
                self.liveConfig.store(self.store.engineConfig)
                self.observeConfig()  // re-arm (one-shot semantics)
            }
        }
    }
    private func observeEnabled() {
        withObservationTracking {
            _ = (store.vietnameseEnabled, store.temporarilyOff)
        } onChange: {
            Task { @MainActor in
                let active = store.vietnameseEnabled && !store.temporarilyOff
                self.enabledSnapshot.store(active)
                self.observeEnabled()
            }
        }
    }
}
```

Key discipline (directly answering the OpenKey failure list):
- The tap callback reads only atomic value snapshots (`enabledSnapshot`, `liveConfig`) — **no** `NSWorkspace`, `TISCopy…`, or `CGWindowList…` calls inside it.
- Per-app "smart switch" resolution (frontmost app → remembered state) is handled by a **workspace notification observer** (`NSWorkspace.didActivateApplicationNotification`), which updates a snapshot when the frontmost app changes — again, off the hot path. The UI toggle just enables/disables that observer.

### 7.2 Persistence

- Simple scalars persist via `UserDefaults` (`@AppStorage`-style, but through the store so the input layer sees one source of truth). Implement with a tiny `didSet`-per-property or a `defaults`-backed property wrapper; keep it explicit and testable.
- Macros persist as JSON in `~/Library/Application Support/com.tanta.keystone/macros.json` (can grow large; not appropriate for `UserDefaults`).
- Per-app remembered states persist as a small `[bundleID: AppState]` dictionary in defaults (or the JSON store). Provide a "Reset learned apps" button in the Per-App pane.

---

## 8. Login item via SMAppService

`SMLoginItemSetEnabled` is deprecated. Use `SMAppService.mainApp` for a menu-bar/agent app (no separate login-helper target needed — the main app registers itself):

```swift
import ServiceManagement

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Reflect the true system status back into the UI (user can revoke in System Settings).
    static func syncToStore(_ store: SettingsStore) {
        store.runAtLogin = (SMAppService.mainApp.status == .enabled)
    }
}
```

Wiring: the General pane's "Run at login" toggle calls `LoginItem.set(newValue)`; on failure it reverts the toggle and surfaces an inline error. On app launch we call `syncToStore` so the toggle reflects reality (the user may have disabled it under **System Settings → General → Login Items**, or macOS may show it there `.requiresApproval`). If `status == .requiresApproval`, show a hint linking to Login Items settings.

### 8.1 Menu-bar persistence

- The app stays resident because it's `LSUIElement` with a live `MenuBarExtra`; closing all windows does not quit it.
- Do not adopt "quit on last window closed." The only quit paths are the menu's **Quit** and standard termination.
- The menu-bar item survives across window open/close because `MenuBarExtra` is a top-level `Scene`, independent of the `Window` scenes.

---

## Open questions

1. **Menu style — `.menu` vs `.window`.** v1 ships `.menu` for native feel and keyboard nav. Do we also want a richer `.window` popover (live status, quick toggles, recent macros)? It's more work and needs custom Liquid Glass layout. Decision needed before locking the menu-bar UX.
2. **Input Monitoring necessity.** Is `IOHIDCheckAccess(.listenEvent)` actually required on macOS 26/27 for our listen-only-then-post tap, or is Accessibility alone sufficient? This changes whether onboarding shows one card or two. Needs empirical verification on target OS.
3. **AX-grant-requires-relaunch UX.** Confirm whether macOS 27 lets an already-running process become trusted without relaunch. If not, finalize the auto-relaunch flow (and whether to auto-relaunch or just prompt).
4. **Global hotkey mechanism.** Switch-language / temp-off / quick-convert hotkeys — implemented inside the existing CGEventTap (cleanest, one tap) vs a separate `NSEvent.addGlobalMonitorForEvents` vs Carbon `RegisterEventHotKey`. Recommend handling them in the tap to avoid a second monitor, but confirm modifier-only combos (e.g. double-Shift, Control+Shift) are expressible.
5. **`KeyboardShortcut`/`KeyCombo` model.** SwiftUI's `KeyboardShortcut` doesn't cover modifier-only or function-key combos well; we likely need our own `KeyCombo` type plus a `KeyCaptureView` (`NSViewRepresentable`) for the Shortcuts pane. Confirm scope (do we support modifier-only hotkeys like OpenKey's Control+Command?).
6. **Live code-table conversion parity.** Confirm the Convert tool and the engine's output stage share one `Converter`/mapping-table module so no byte-level divergence exists between conversion and live typing.
7. **Per-app smart-switch storage scope.** Keyed by bundle identifier — but some apps (Electron, web views) share a bundle ID across very different contexts. Acceptable for v1? Any need for finer granularity?
8. **Legacy macro import.** Do we need to import OpenKey's exact macro file format for migration, or is JSON-only acceptable with a documented manual migration? Affects onboarding friendliness for switching users.
9. **Updates mechanism.** "Check for updates" — Sparkle (mature, EdDSA-signed, works with Developer-ID/notarized DMG) vs a bespoke checker. Sparkle is the pragmatic choice for a self-distributed app; confirm licensing acceptability and whether it's in-scope for v1.
10. **Dark/tinted menu bar rendering of the custom VN glyph.** Template images tint mono; if we want the VN glyph to read clearly against the macOS 26 tinted/Liquid-Glass menu bar, verify a single template asset suffices or whether we need a non-template colored variant.# Project Structure, Testing Strategy, Build & Distribution

## 1. Repository & Module Layout

### Recommendation: SPM packages composed inside a thin Xcode app project

Use **Swift Package Manager for all logic** (`KeystoneEngine`, `KeystoneInput`) and a **minimal Xcode app target** only for the shippable `.app` bundle. This is the right split because:

- **The engine must be portable and CI-testable without a GUI.** An SPM library with zero Apple-UI dependencies builds and tests on any macOS runner (and even Linux) in seconds via `swift test`. Nothing about tone placement or code-table encoding needs AppKit.
- **The Xcode target owns only what SPM can't do well**: the app bundle, `Info.plist` (`LSUIElement`), entitlements, signing, the notarized/stapled artifact, and the SwiftUI menu-bar UI.
- Keeping `KeystoneInput` (CGEventTap layer) as its own SPM module forces a clean seam so the app target stays thin and the input layer can be exercised in isolation.

Concretely: one Swift package with three targets, referenced by an Xcode project that adds the app target on top.

```
Keystone/
├─ Keystone.xcodeproj/              # thin app wrapper only
├─ Package.swift                    # declares the 3 SPM targets + test targets
├─ Sources/
│  ├─ KeystoneEngine/               # PURE. No AppKit/CoreGraphics/Foundation-UI.
│  │  ├─ Model/
│  │  │  ├─ KeyInput.swift          # keycode/char + modifiers, agnostic
│  │  │  ├─ EngineConfig.swift      # method, codeTable, orthography, flags
│  │  │  ├─ EngineResult.swift      # { backspaceCount, outputText }
│  │  │  └─ InputMethod.swift       # .telex .vni .simpleTelex1 .simpleTelex2 .quickTelex
│  │  ├─ Syllable/
│  │  │  ├─ SyllableBuffer.swift    # in-progress word state (the composing buffer)
│  │  │  ├─ Phonology.swift         # onset/glide/nucleus/coda validity, VN syllable rules
│  │  │  ├─ TonePlacement.swift     # modern vs old orthography rule
│  │  │  └─ SpellChecker.swift      # restore-if-invalid decision
│  │  ├─ Methods/
│  │  │  ├─ TelexMapper.swift
│  │  │  ├─ VNIMapper.swift
│  │  │  ├─ SimpleTelexMapper.swift
│  │  │  └─ QuickTelexMapper.swift
│  │  ├─ Encoding/
│  │  │  ├─ CodeTable.swift         # protocol
│  │  │  ├─ UnicodeNFC.swift
│  │  │  ├─ UnicodeCompound.swift   # tổ hợp (combining diacritics)
│  │  │  ├─ TCVN3.swift             # ABC
│  │  │  ├─ VNIWindows.swift
│  │  │  └─ CP1258.swift            # Vietnamese locale codepage
│  │  ├─ Macros/
│  │  │  └─ MacroExpander.swift     # gõ tắt (pure lookup/replace)
│  │  └─ Engine.swift               # process(KeyInput, inout State, EngineConfig) -> EngineResult
│  │
│  ├─ KeystoneInput/                # macOS input layer. Depends on KeystoneEngine.
│  │  ├─ EventTapController.swift   # CGEventTap lifecycle + re-enable on disable events
│  │  ├─ KeystrokeExecutor.swift    # turns EngineResult into synthetic backspaces + text
│  │  ├─ FrontAppTracker.swift      # cached NSWorkspace observer (NOT polled per keystroke)
│  │  ├─ KeyboardLayoutCache.swift  # cached TIS source (refreshed on notification only)
│  │  └─ AccessibilityAuthorizer.swift # AXIsProcessTrusted checks + prompt
│  │
│  └─ (app sources live under the Xcode target, see below)
│
├─ App/                             # Xcode app target sources (SwiftUI)
│  ├─ KeystoneApp.swift             # @main, MenuBarExtra
│  ├─ MenuBarView.swift
│  ├─ Settings/                     # SwiftUI settings panes
│  ├─ Onboarding/                   # Accessibility-grant walkthrough
│  ├─ ConvertTool/                  # clipboard code-conversion UI
│  ├─ Info.plist                    # LSUIElement=true
│  └─ Keystone.entitlements
│
├─ Tests/
│  ├─ KeystoneEngineTests/          # Swift Testing. The corpus lives here.
│  │  ├─ Corpus/                    # data files (JSON/CSV) the parameterized tests load
│  │  ├─ TelexToneTests.swift
│  │  ├─ TonePlacementTests.swift
│  │  ├─ CodeTableTests.swift
│  │  ├─ RestoreInvalidTests.swift
│  │  └─ PropertyTests.swift
│  └─ KeystoneInputTests/           # thin; mostly executor logic + a fake event source
│
├─ Scripts/
│  ├─ sign.sh
│  ├─ notarize.sh
│  └─ make_dmg.sh
└─ .github/workflows/ci.yml
```

### Dependency direction (strict, one-way)

```
Keystone (app, SwiftUI)  ──▶  KeystoneInput (CGEventTap)  ──▶  KeystoneEngine (pure)
        │                                                              ▲
        └──────────────────────────────────────────────────────────────┘
           (app also talks to the engine directly, e.g. the convert tool)
```

- `KeystoneEngine` depends on **nothing** but the Swift standard library (not even `Foundation` if avoidable — keep `import Foundation` out of hot-path files; it is acceptable in `Encoding`/`Macros` for `String` niceties but avoid `NSString`).
- `KeystoneInput` depends on `KeystoneEngine` + `CoreGraphics`/`AppKit`/`Carbon` (for TIS). Never the reverse.
- The app depends on both. Enforce this in `Package.swift` `dependencies:` and never add a back-edge. A back-edge from engine → input is the single most important architectural rule to police in review, because it is what makes the engine untestable and unportable.

```swift
// Package.swift (sketch)
let package = Package(
    name: "Keystone",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KeystoneEngine", targets: ["KeystoneEngine"]),
        .library(name: "KeystoneInput", targets: ["KeystoneInput"]),
    ],
    targets: [
        .target(name: "KeystoneEngine"),                                   // no deps
        .target(name: "KeystoneInput", dependencies: ["KeystoneEngine"]),
        .testTarget(name: "KeystoneEngineTests", dependencies: ["KeystoneEngine"],
                    resources: [.copy("Corpus")]),
        .testTarget(name: "KeystoneInputTests", dependencies: ["KeystoneInput"]),
    ]
)
```

---

## 2. Testing — the safety net for a clean-room engine

The engine is written from scratch, so the corpus **is** the specification. Every rule about Vietnamese orthography that a human "just knows" must be pinned by a test, or a refactor will silently break it. Target: a green corpus is the definition of "the engine works," and CI blocks any red.

### Framework: Swift Testing (`@Test`, `@Suite`, `#expect`, `arguments:`)

Use Swift Testing (not XCTest). Its parameterized `@Test(arguments:)` maps perfectly onto a corpus of `(keystrokes, config) -> expected` rows, and each row reports as an individual test with its own name.

### The core corpus row type

```swift
struct CorpusCase: Codable, CustomTestStringConvertible {
    var name: String
    var keys: String          // raw keystrokes typed, e.g. "vieejt"
    var method: InputMethod   // .telex, .vni, ...
    var codeTable: CodeTable  // .unicodeNFC by default
    var orthography: Orthography = .modern
    var expected: String      // final committed text
    var testDescription: String { name }
}
```

Drive the engine by replaying `keys` one `KeyInput` at a time through `Engine.process`, applying each `EngineResult` (delete N, append text) to a mutable `String`, then comparing the accumulated result to `expected`.

```swift
@Test(arguments: try CorpusLoader.load("telex_tones.json"))
func telexTones(_ c: CorpusCase) {
    #expect(Replayer.run(c) == c.expected)
}
```

### Test categories, sample cases, and rough target counts

Counts are v1 floors; the corpus should grow monotonically (see "growing the corpus").

| Category | What it locks down | Rough count (v1) |
|---|---|---|
| Basic Telex tone marks (all 6) | s/f/r/x/j → sắc/huyền/hỏi/ngã/nặng, plus level (no mark) | ~40 |
| Telex diacritics | aa→â, aw→ă, ee→ê, oo→ô, ow→ơ, w→ư, dd→đ | ~30 |
| VNI equivalents | 1–5 tones, 6/7/8/9 diacritics, mirror of Telex cases | ~50 |
| Simple Telex 1 & 2 | reduced key sets, method-specific w/uw behavior | ~30 |
| Quick Telex | shorthand rules (e.g. auto-doubling) | ~20 |
| Tone placement modern vs old | hòa/hoà, thủy/thuỷ, khỏe/khoẻ, qua/uy edge cases | ~40 |
| Closed vs open syllables | coda affecting tone target (tan/tang/tay) | ~30 |
| Medial glide (labiovelar /w/) | hoa, quả, huy, khuỷu, qu- vs o/u glide disambiguation | ~40 |
| Diphthongs / triphthongs | nguyễn, quốc, hoàng, khuỷu, yêu, ươu, uôi, iêu | ~50 |
| Delete/backspace + diacritic restore | backspace mid-word restores prior composed state | ~40 |
| Restore-if-invalid | invalid combo reverts to raw keystrokes (e.g. "dđ" cases) | ~30 |
| Code tables (×5) | same word encoded to each table's bytes/codepoints | ~60 (12×5) |
| Macros (gõ tắt) | trigger expansion, no-expand when disabled, partial-match | ~20 |
| Auto-capitalize | first letter after sentence terminator | ~10 |
| **Total v1 floor** | | **~500** |

### ~18 concrete sample cases

Assume `codeTable = Unicode NFC` and `orthography = modern` unless noted. "Keys" is the literal key sequence typed.

| # | Keys | Method / Config | Expected output |
|---|---|---|---|
| 1 | `as` | Telex | `á` |
| 2 | `af` | Telex | `à` |
| 3 | `ar` | Telex | `ả` |
| 4 | `ax` | Telex | `ã` |
| 5 | `aj` | Telex | `ạ` |
| 6 | `aa` | Telex | `â` |
| 7 | `aw` | Telex | `ă` |
| 8 | `dd` | Telex | `đ` |
| 9 | `vieejt` | Telex | `việt` |
| 10 | `Vieejt Nam` | Telex | `Việt Nam` |
| 11 | `hoaf` | Telex, modern | `hòa` |
| 12 | `hoaf` | Telex, **old** | `hoà` |
| 13 | `thuyr` | Telex, modern | `thủy` |
| 14 | `thuyr` | Telex, **old** | `thuỷ` |
| 15 | `nguyeexn` | Telex | `nguyễn` |
| 16 | `quoocs` | Telex | `quốc` |
| 17 | `khuyeur
u`→ `khuyeuru` | Telex | `khuỷu` |
| 18 | `a8` | VNI | `ă` |
| 19 | `a6` | VNI | `â` |
| 20 | `d9` | VNI | `đ` |
| 21 | `vie6t5` | VNI | `việt` |
| 22 | `as` then Backspace | Telex | `a` (tone removed, base restored) |
| 23 | `dd` then `d` | Telex, restore-if-invalid | `đd`? → see note; invalid trailing reverts |
| 24 | `caa` (no valid VN syllable "câ" alone at commit) | Telex | `câ` (valid partial) / test commit vs abort |
| 25 | `vieejt` | Telex, **TCVN3** | bytes: `v i Ö t` (TCVN3 mapping of ệ) |
| 26 | `vieejt` | Telex, **VNI-Windows** | `vie65t`-form glyph string per VNI table |
| 27 | `vieejt` | Telex, **Unicode compound** | `v i e◌̣◌̂ t` (base + combining U+0323 U+0302) |
| 28 | `vn` (macro → "Việt Nam") | Telex, macros on | `Việt Nam` |

Notes on the tricky rows: #23/#24 exercise **restore-if-invalid** and are exactly where the from-scratch engine will disagree with intuition — pin the *decided* behavior explicitly (see Open Questions). #25–#27 assert on the **encoded byte/codepoint sequence**, not the rendered glyph; write those `expected` values as explicit `\u{...}` escapes or hex byte arrays so the test is unambiguous and reviewable.

### Data-driven approach & growing the corpus

- Store cases as **JSON files under `Tests/.../Corpus/`**, one file per category, loaded by `@Test(arguments:)`. Non-programmers (or the author testing by hand) can add rows without touching Swift.
- **Every bug fix adds a regression row first** (TDD): reproduce as a failing corpus case, then fix. The corpus only grows.
- Add a **"harvest" workflow**: when a real word is reported as mistyped, drop it into a `regressions.json` with the observed-vs-expected pair.
- Consider seeding from a **frequency word list** (top few thousand Vietnamese syllables) generated once, each with its canonical Telex/VNI keystroke sequence, to get broad coverage cheaply.

### Property / differential tests

Put these in `PropertyTests.swift`; they catch classes of bugs the enumerated corpus misses:

1. **Round-trip (encode/decode):** for every codepoint the engine can emit, `decode(encode(x, table)) == x` for each of the 5 tables. Catches asymmetric table bugs.
2. **NFC idempotence:** the Unicode-NFC output is already normalized — `NFC(output) == output`. No stray decomposed forms leak.
3. **Method equivalence (differential):** for a shared word list, `render(telexKeys, .telex) == render(vniKeys, .vni)` when both encode the same target word. Any divergence is a bug in one mapper.
4. **Backspace inverse:** typing a word then pressing Backspace exactly (visible-length) times yields empty output — the delete accounting (`backspaceCount`) never drifts from reality.
5. **Prefix stability:** committing a syllable then continuing must never rewrite already-committed text beyond the declared `backspaceCount` (guards against runaway rewrites).
6. **Old⇄modern reversibility:** switching orthography and back on the same keys returns the original placement.

---

## 3. Build & Distribution

An event-tap IME **cannot** ship on the Mac App Store (the sandbox forbids the global event tap and synthetic event posting). Plan is **self-distribution via a signed, notarized DMG**.

### Signing

- **Certificate:** `Developer ID Application` (requires a paid Apple Developer Program membership and a Team ID). This is distinct from the App Store `Apple Distribution` cert.
- Sign the app **and every embedded dylib/framework** (including Sparkle if used), inside-out, with `--options runtime` (Hardened Runtime) and a valid `--timestamp`.

```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <Name> (<TEAMID>)" \
  --entitlements App/Keystone.entitlements \
  Keystone.app
codesign --verify --deep --strict --verbose=2 Keystone.app
```

### Entitlements & the accessibility grant

- **The CGEventTap needs no special entitlement.** There is no signing entitlement that unlocks event taps. What it needs is a **runtime TCC grant: Accessibility** (System Settings → Privacy & Security → Accessibility). The app must detect this with `AXIsProcessTrusted()`, prompt via `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`, and degrade gracefully (menu-bar shows "input disabled — grant Accessibility") when not granted.
- **App Sandbox: OFF.** Sandboxing is incompatible with a global event tap; and since we are not on the App Store, we don't need it.
- **Hardened Runtime: ON** (required for notarization). Keep the entitlements file **minimal**. Do *not* add sandbox. You likely need **none** of the sensitive entitlements; only add a hardened-runtime exception if a dependency forces it (e.g. `com.apple.security.cs.disable-library-validation` only if loading unsigned plug-ins — avoid). Input Monitoring may additionally be prompted by macOS depending on how the tap is created; treat it like Accessibility (runtime grant, not entitlement).
- Because Hardened Runtime + notarization are enough for Gatekeeper, no entitlements beyond an (empty or near-empty) hardened-runtime set are expected.

### Notarization + stapling

Use **notarytool** (the legacy `altool` path is dead). Store an App Store Connect API key or an app-specific-password keychain profile in CI secrets.

```bash
# 1. Zip or DMG the signed app, submit, wait
xcrun notarytool submit Keystone.dmg \
  --keychain-profile "KEYSTONE_NOTARY" --wait
# 2. Staple the ticket so it works offline
xcrun stapler staple Keystone.dmg
xcrun stapler validate Keystone.dmg
# 3. Gatekeeper assessment
spctl -a -vvv -t install Keystone.dmg   # or -t exec on the .app
```

Staple the **DMG** (and optionally the `.app` before packaging) so first-launch works without a network round-trip.

### Packaging: DMG

Produce a DMG containing the `.app` and an `/Applications` symlink (drag-to-install). `create-dmg` (Homebrew) or a scripted `hdiutil` in `Scripts/make_dmg.sh`. Sign the DMG's contents (the app) before creating the DMG; notarize the finished DMG.

### Self-update: **Sparkle**

For a non-App-Store macOS app, **Sparkle 2** is the standard and the recommendation over a custom updater:

- Mature, EdDSA-signed appcast, delta updates, handles Gatekeeper/quarantine correctly, actively maintained, MIT-licensed (license-compatible with any choice the user makes).
- Add it via SPM; **it must itself be signed** as part of your app (it ships an XPC/helper — sign those with the same Developer ID and Hardened Runtime, and Sparkle's docs list the specific hardened-runtime entitlements its XPC services need — this is the one place you may add narrow entitlements).
- Host a static **appcast.xml** + the notarized DMGs on any static host (GitHub Releases, S3, etc.). Sign each update with the Sparkle EdDSA private key (kept out of the repo).
- **Avoid a custom updater**: re-implementing signature verification, quarantine handling, and atomic replace correctly is exactly the kind of security-sensitive code not worth owning for v1.

### Requirements summary

Paid Apple Developer membership; a Team ID; a `Developer ID Application` cert + private key in the CI/keychain; a notary credential (API key or app-specific password); a Sparkle EdDSA keypair. None of these can be faked or skipped for a distributable build.

---

## 4. CI

Goal: **the engine corpus stays green on every push/PR.** Split fast pure tests from the slower signed build.

```yaml
# .github/workflows/ci.yml (sketch)
name: CI
on: [push, pull_request]
jobs:
  engine-tests:               # runs on every change, fast, no secrets
    runs-on: macos-26         # (or latest available image)
    steps:
      - uses: actions/checkout@v4
      - run: swift build
      - run: swift test --filter KeystoneEngineTests   # the corpus
  input-tests:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: swift test --filter KeystoneInputTests
```

- **`engine-tests` is a required status check** to merge — this is the safety net's teeth. It needs no secrets, no signing, and finishes in seconds.
- Keep signing/notarization in a **separate, tag-triggered `release` workflow** (guarded by secrets) so ordinary PRs never depend on certificates.
- Optionally publish the parameterized test count as a badge/artifact so corpus growth is visible.
- Note: the CGEventTap and Accessibility TCC grant cannot be exercised in headless CI; `KeystoneInputTests` must test the executor's *logic* against a fake event source, not a live tap.

---

## 5. Phased Delivery Roadmap

**Phase 1 — Engine core + corpus.** `KeystoneEngine` only: Telex method, Unicode NFC output, modern tone placement, syllable buffer, tone placement, restore-if-invalid, backspace/restore. Stand up Swift Testing corpus (categories: basic tones, diacritics, tone placement, backspace, restore-if-invalid) at the v1 floor. Wire CI green. *Deliverable: a proven pure engine, no UI.* This phase carries the most orthographic risk, so it goes first and gets the deepest test investment.

**Phase 2 — Input layer + minimal menu bar.** `KeystoneInput` with the robustness fixes baked in from day one: (a) the tap callback **handles `kCGEventTapDisabledByTimeout` and `kCGEventTapDisabledByUserInput` and re-enables the tap**; (b) **zero heavy work on the hot path** — front-app and keyboard-layout state come from cached observers/notifications, never per-keystroke queries; (c) careful CF memory ownership (no `CFRelease` on borrowed `CFArrayGetValueAtIndex` values; no leaked TIS sources on early return). Minimal `MenuBarExtra`: on/off toggle, Accessibility-grant prompt. *Deliverable: you can type Vietnamese anywhere, reliably, and it never silently dies.*

**Phase 3 — Full methods + all code tables.** Add VNI, Simple Telex 1/2, Quick Telex mappers; add TCVN3, VNI-Windows, Unicode-compound, CP1258 encoders; add old-orthography mode. Expand corpus to full v1 floor (VNI, Simple, Quick, code-table byte assertions, diphthong/triphthong/glide sets) + property tests. *Deliverable: feature-parity input core.*

**Phase 4 — Productivity features + UX.** Macros/gõ tắt, smart-switch-key (per-app remembered language + code table), clipboard convert tool, switch-language hotkey, temporarily-off, auto-capitalize, and the full SwiftUI settings + onboarding flow. *Deliverable: the daily-driver app.*

**Phase 5 — Release engineering.** Developer ID signing, Hardened Runtime, entitlements finalization, notarytool + stapling, DMG packaging, Sparkle integration + appcast + release CI. *Deliverable: a downloadable, auto-updating, notarized DMG.*

Phases 1–2 are the real spine (a trustworthy engine + a tap that never dies). Everything after is additive and independently shippable, so the roadmap tolerates slippage in 3–5 without blocking a usable early build.

---

## Open Questions

1. **Restore-if-invalid exact semantics.** When a sequence produces an invalid Vietnamese syllable (e.g. stray `dd`+`d`, or `w` in a context with no valid mapping), does the engine revert to *raw keystrokes*, to the *last valid composed state*, or pass the offending key through literally? This must be a single decided rule and pinned by tests (rows #23/#24) — it is the highest-ambiguity behavior.
2. **Commit boundary.** What events commit the composing buffer (space, punctuation, arrow keys, mouse click, focus change, tone/diacritic on a new syllable)? The executor's `backspaceCount` accounting depends entirely on knowing when the buffer resets. Needs an explicit event → action table.
3. **CP1258 fidelity.** CP1258 uses combining diacritics for some tones and precomposed for others; confirm the exact target byte sequences (and whether we target Windows-1258 as Microsoft defines it) before writing `expected` values.
4. **VNI-Windows / TCVN3 canonical byte references.** Need an authoritative reference mapping to assert against (there are minor real-world variants). Which reference is normative?
5. **`w` as `ư` vs standalone.** In Telex, bare `w` maps to `ư` in many implementations but users sometimes want a literal `w`. Is there a toggle, and how does it interact with Quick Telex?
6. **Input Monitoring vs Accessibility.** Depending on how the tap is constructed (`.cgSessionEventTap` + listen vs. default), macOS 26/27 may demand the **Input Monitoring** grant in addition to (or instead of) Accessibility. Verify on-device which TCC prompts actually fire and document both.
7. **Smart-switch persistence scope.** Is per-app language/code-table state keyed by bundle id only, or bundle id + window role? And where is it stored (UserDefaults suite vs. app-group file)?
8. **Sparkle hardened-runtime exceptions.** Confirm the exact entitlements Sparkle's XPC helpers require under Hardened Runtime for the current Sparkle 2.x, so the entitlements file stays as narrow as possible.
9. **macOS target floor.** Context says macOS 26+, but the local toolchain reports a macOS 28 target. Confirm the real minimum deployment target, since it affects available `MenuBarExtra`/SwiftUI APIs and CI image selection.
10. **InputMethodKit migration seam.** If IMK becomes v2, how much of `KeystoneInput` is replaced vs. reused? Worth confirming the engine/executor boundary is drawn so an IMK backend can drop in without touching `KeystoneEngine`.