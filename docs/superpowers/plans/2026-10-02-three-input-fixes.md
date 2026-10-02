# Three input fixes — cancel keeps the literal, auto-capitalize forgets after edits, Secure Input awareness

Approved by Tân Tạ on 2026-10-02 ("oke em làm cả 3 luôn đi"). No separate spec file: the binding
requirements are this plan's Global Constraints plus each task's "Required behavior". The evidence
behind each task is summarized in its "Why" paragraph.

> **Outcome (2026-10-02):** Tasks 2 and 3 shipped on this branch. Task 1 was implemented, then
> REVERTED (commit ccee5a9) after the final whole-branch review. On real English prose it dropped a
> letter from correctly typed words the lexicon lacks (messages→mesages, processing→procesing,
> diff→dif; about 1 word in 160). The "0 of 210,773" sweep could not see this, because it only typed
> words already in the lexicon. A redesign follows in its own plan. Its acceptance bar: natural-typing
> accuracy on a real-prose corpus ≥ main, and OpenKey-habit accuracy > main.

## Global Constraints

- Swift 6 package at the repo root. Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`,
  `#expect`), never XCTest. Full suite: `swift test` from the repo root. Every existing test must keep
  passing. Two "known issues" (`withKnownIssue`) already exist and are expected.
- **TDD is mandatory** (Tân's rule): write the new tests first, run them and SEE them fail for the
  right reason, then implement, then run the full suite.
- Business logic lives in PURE code: `Sources/KeystoneEngine` (no AppKit) or pure types in
  `Sources/KeystoneInput`. `App/` stays thin glue, and there is no app test target.
- Match the surrounding style. Doc comments explain WHY, not what. User-facing strings are
  Vietnamese. Add no new dependencies and no abstractions beyond what a task asks for.
- Change only what the task asks. A refactor outside the task's scope is a defect.
- Never swallow errors silently. Log state TRANSITIONS only (`os.Logger`, subsystem
  `com.tanta.keystone`), never per keystroke, and never on the CGEventTap hot path.
- Docs are part of the task. Add or adjust the relevant `DECISIONS.md` section and the `README.md`
  feature text whenever behavior changes.
- Commit on the current branch (`claude/three-fixes`) with a clear message. End every commit message
  with this exact line:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Never push, merge, or touch `/Applications/Keystone.app`.

---

## Task 1: After a Telex/VNI cancel, keep the cancelled literal (OpenKey parity)

**Why.** Tân types English inside Vietnamese Telex with OpenKey muscle memory. He sees a tone appear
(`s u s` → `sú`) and presses the key again to cancel it. Keystone's eager restore (`spellCheck`) then
renders the RAW keystrokes, cancel key included, so the screen shows `suss`, then `susspend`.
- `suspend` is in the dictionary, so it is fixed only at the space.
- `unsuspend` is not, so it commits as `unssuspend`.

OpenKey's `checkRestoreIfWrongSpelling` (`~/Downloads/OpenKey/Sources/OpenKey/engine/Engine.cpp`,
~line 1204) restores raw keys ONLY while some vowel still carries a tone or quality mark. After a
cancel has stripped them, it leaves the on-screen word alone. A prototype of the rule below changed
the final output of 0 of 210,773 naturally-typed dictionary words.

**Files**
- `Sources/KeystoneEngine/Telex.swift`
  - Add `var cancelled: Bool = false` to `struct Composition`, with a doc comment.
  - In `Telex.fold`, return `Composition(cells: cells, tone: tone, cancelled: cancelled)`. The existing
    local `cancelled` only becomes true when `literalAfterCancel` is on; keep it that way.
- `Sources/KeystoneEngine/VNI.swift`: the same in `VNI.fold`.
- `Sources/KeystoneEngine/Lexicon.swift`: add a pure decision to `RestoreDecision`, with a doc comment:
  `public static func chooseAfterCancel(raw: String, lexicon: Lexicon) -> RestoreChoice`.
  It returns `.raw` iff `lexicon.contains(raw)`, else `.composed`.
- `Sources/KeystoneEngine/Engine.swift`
  - Add a private helper `keepsCancelledLiteral(_ comp: Composition) -> Bool`. It is true iff ALL of:
    - `config.literalAfterCancel`
    - `lexicon != nil`
    - `comp.cancelled`
    - `comp.tone == .ngang`
    - every vowel cell has `mark == .none`
    (Consonant cells, including a `dStroke` đ, are ignored, exactly like OpenKey.)
  - `rerender()`: the eager-restore branch becomes
    `config.spellCheck && isUnrecoverable(comp) && !keepsCancelledLiteral(comp)`.
    Otherwise render `encode(comp, table:)` as today.
  - `finalize(boundary:)`: inside the existing restore branch
    (`config.restoreIfInvalid && !rawKeys.isEmpty && !isValid(comp) && compHasVowel`), check FIRST:
    if `keepsCancelledLiteral(comp)`, pick between `revertToRawUnits()` and
    `encode(capitalized(comp, if: shouldCapitalize), table: table)` with
    `RestoreDecision.chooseAfterCancel(raw: rawWord, lexicon: lexicon!)`. The force-unwrap is
    justified by the helper's `lexicon != nil` clause; a `guard let` / `if let` binding is fine too.
    Otherwise run the existing `RestoreDecision.choose` logic, unchanged. The force-English branch
    before it stays first and unchanged.
- New test file `Tests/KeystoneEngineTests/CancelKeepsLiteralTests.swift`. Copy the
  `typeThroughEngine` / `typeStepwise` helper pattern from `EagerRestoreTests.swift` (file-private
  there).
- `DECISIONS.md`: a new section "Huỷ dấu xong giữ nguyên chữ đã huỷ (OpenKey checkRestoreIfWrongSpelling)".
  Also update the "OpenKey-compatible literal-after-cancel (Phase 6)" and "Eager restore" sections
  wherever they now say otherwise.
- `README.md`: extend the "Huỷ dấu xong thì gõ tiếp chữ thường (kiểu OpenKey)" bullet.

**Required behavior.** Telex. Config `on` = `EngineConfig(inputMethod: .telex, restoreIfInvalid: true,
allowFreeToneMark: true, freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)`.
Lexicon `lex` = `Lexicon(["suspend", "class", "pass", "message", "task"])`. Trailing space = commit.

| # | Keys | Config / lexicon | Expected |
|---|------|------------------|----------|
| 1 | `susspend` stepwise | on / lex | `["s","su","sú","sus","susp","suspe","suspen","suspend"]` |
| 2 | `susspend ` | on / lex | `"suspend "` |
| 3 | `unssuspend ` | on / lex (no "unsuspend") | `"unsuspend "` |
| 4 | `unssuspend` stepwise, 4th entry | on / lex | `"uns"` |
| 5 | `classs ` | on / lex | `"class "` |
| 6 | `class ` (natural double) | on / lex | `"class "` |
| 7 | `class` stepwise, last entry | on / lex | `"clas"` (accepted trade-off, pin it) |
| 8 | `messsage ` and `message ` | on / lex | both `"message "` |
| 9 | `tassk ` | on / lex | `"task "` |
| 10 | `messi ` (non-dictionary natural double) | on / lex | `"mesi "` (OpenKey parity, pin it) |
| 11 | `unssuspend ` | literalAfterCancel **false**, rest as on / lex | same as BEFORE the change (`"unssuspend "`) |
| 12 | `unssuspend ` and its stepwise trace | on / lexicon **nil** | same as BEFORE the change |
| 13 | a cancel that leaves a quality mark, e.g. `vieetss ` | on / lex | same as BEFORE the change |
| 14 | `unssuspend ` with `autoCapitalize: true` on a fresh engine | on+autoCap / lex | `"Unsuspend "` |
| 15 | VNI `a11 ` | VNI equivalent of on / lex | `"a1 "` |

For rows 11, 12, 13 and 15, establish the "before" output by running the test BEFORE changing
`Engine.swift`. Assert the exact string in the final test. Row 15 has no prior pin: assert `"a1 "`
only if VNI's cancel really sets `cancelled`; otherwise report back.

---

## Task 2: Auto-capitalize forgets the sentence position after a passthrough Backspace or a caret move

**Why.** Tân has `autoCapitalize` on. Typing `xong.`, Backspace, then `, các` produces `xong, Các`.
The engine never sees what a passthrough Backspace deleted or where an arrow key moved the caret, so
a stale "sentence start" survives. `DECISIONS.md` lists this under "Accepted limitations … awaiting
Tân's decision" (around lines 685–693). He has now decided.

The rule: when the engine cannot know what precedes the caret, it uses `.afterReset`. That means no
auto-capital by itself, but a freshly typed terminator plus whitespace still confirms.

**Files**
- `Sources/KeystoneEngine/Engine.swift`
  - `process(.backspace)` with `rawKeys.isEmpty`: set `sentencePosition = .afterReset`, then return
    `.none`. A Backspace inside a composing word is unchanged.
  - `processInactive(.backspace)` with `englishRawKeys.isEmpty`: set `sentencePosition = .afterReset`
    (the physical Delete still passes through, return `.none`). A Backspace with a non-empty English
    buffer is unchanged.
  - New `public func flushCaretMove() -> EngineResult`. It is `finalize(boundary: nil)`, then
    `sentencePosition = .afterReset`.
  - New `public func flushInactiveCaretMove() -> EngineResult`. It is `matchEnglishMacro(boundary: nil)`,
    then `sentencePosition = .afterReset`.
  - Give both a doc comment in the style of `flushNewline()`.
- `Sources/KeystoneInput/Contracts.swift`: new `KeyDecision` case `commitCaretMove`, with a doc
  comment: "finalize like `.commitPassthrough`, pass the key through, AND forget the sentence
  position".
- `Sources/KeystoneInput/KeyTranslator.swift`
  - keyCodes 123, 124, 125, 126 (arrows), 115 (Home), 119 (End), 116 (PageUp) and 121 (PageDown)
    return `.commitCaretMove`.
  - 48 (Tab), 53 (Escape) and 117 (ForwardDelete) stay `.commitPassthrough`. The documented "Tab
    neither confirms nor cancels" stays, and ForwardDelete never changes what precedes the caret.
  - Update the header comment.
- `Sources/KeystoneInput/EngineController.swift`
  - Active branch: `case .commitCaretMove` calls `engine.flushCaretMove()` and returns
    `(false, noop ? nil : r, d)`, exactly like `.commitPassthrough`.
  - Inactive macro branch: `engine.flushInactiveCaretMove()`, mirroring `.commitPassthrough`.
  - grep the whole repo (Sources, App, Tests) for other exhaustive `switch`es over `KeyDecision` and
    handle the new case there with the same semantics.
- Tests
  - Engine level: new file `Tests/KeystoneEngineTests/AutoCapitalizeForgetsAfterEditTests.swift`.
    Use a screen simulator in which a Backspace the engine does NOT own (`!engine.isComposing` before
    `process(.backspace)`) deletes one on-screen character. That is what the real app does, since
    `EngineController` passes it through.
  - `Tests/KeystoneInputTests/TranslatorTests.swift`
  - `Tests/KeystoneInputTests/EngineControllerTests.swift`
- `DECISIONS.md`: new section "Auto-capitalize: quên vị trí câu sau Backspace / phím di chuyển con
  trỏ". Rewrite the two "Accepted limitations" sentences about passthrough Backspace and Tab/arrow, and
  the "arrows, Home/End, PageUp/PageDown … go through `flush()`" sentence near line 485, to match.
- `README.md`: the "Tự viết hoa đầu câu" bullet gets one sentence about this.

**Required behavior.** `on` = `EngineConfig(autoCapitalize: true)`. Call `engine.reset()` first to
simulate mid-document unless the row says fresh.

| # | Steps | Expected screen |
|---|-------|-----------------|
| 1 | `xong.`, BS(passthrough), `, cacs ` | `"xong, các "` |
| 2 | `xong. `, BS, BS, `, cacs ` | `"xong, các "` |
| 3 | `hoa`, `flushNewline()` (screen gets `"\n"`), BS (deletes the `\n`), ` lan ` | `"hoa lan "` |
| 4 | `heets. `, `flushCaretMove()`, `roofi ` | `"hết. rồi "` |
| 5 | `hoa.`, BS, `. lan ` (a re-typed terminator still confirms) | `"hoa. Lan "` |
| 6 | FRESH engine: `chaof. ban`, BS (engine-owned, inside the word), `nj ` | `"Chào. Bạn "` |
| 7 | Inactive: Backspace with an empty English buffer forgets a confirmed sentence start. Prove it with an English-mode macro + `macroAutoCapitalize` (reuse `typeInactiveWithReset` / the macro setup in `EngineTogglesTests.swift`). A macro trigger typed after `end. `, BS, `, ` must expand UNcapitalized. | as described |
| 8 | Translator: keyCodes 123–126, 115, 119, 116, 121 return `.commitCaretMove`; 48, 53, 117 return `.commitPassthrough`. | |
| 9 | EngineController, active: keys for `hoa. ` + Left arrow (keyCode 123) + `lan ` give a lowercase `lan`; the arrow is NOT suppressed. | |

All existing `AutoCapitalize*` tests must still pass unchanged, including the "Tab neither confirms
nor cancels" ones.

---

## Task 3: Secure Input awareness (design spec §7, never implemented until now)

**Why.** Confirmed on 2026-09-28: a Chrome tab (workplace.vietnix.vn) turned on macOS Secure Input
and kept it on while Tân was in Discord. macOS hides every keystroke from CGEventTaps while it is on,
so Vietnamese failed in every app. Keystone gave no feedback (menu bar still "V"). Keystone must NOT
try to bypass Secure Input, which is a macOS security feature. It must:
1. Show it.
2. Name the app that was frontmost when it began. `kCGSSessionSecureInputPID` always reports the
   CURRENT frontmost app, verified twice, so it is useless for attribution.
3. Reset the engine buffer.
4. Ignore keyboard switch-key toggles while on. A blind ⌃⇧ is what wrote "Chrome = English" into
   per-app memory.
5. Not learn per-app V/E while on.

Spec text: `docs/superpowers/specs/2026-09-16-keystone-design.md` §7 ("Secure input mode").

**Files**
- New pure file `Sources/KeystoneInput/SecureInputTracker.swift`:
  - `public struct SecureInputTracker: Sendable, Equatable` with:
    - `public private(set) var isActive: Bool` (initially false)
    - `public private(set) var holder: String?`
    - `public init()`
    - `public enum Change: Equatable, Sendable { case began(holder: String?), ended }`
    - `public mutating func update(isEnabled: Bool, frontmostAppName: String?) -> Change?`
  - Semantics of `update`:
    - OFF→ON sets `isActive`, captures `holder = frontmostAppName`, returns `.began`.
    - While ON, `holder` is NOT updated (attribution happens only at the transition).
    - ON→OFF clears both and returns `.ended`.
    - No transition returns nil.
  - `public static func statusMessage(holder: String?) -> String`:
    - holder present: `"<holder> đang bật nhập bảo mật (ô mật khẩu) — thoát ô/tab đó để gõ tiếp tiếng Việt"`
    - holder nil: `"Một ứng dụng đang bật nhập bảo mật (ô mật khẩu) — thoát ô/tab đó để gõ tiếp tiếng Việt"`
  - Doc comments carry the WHY (attribution caveat, no bypass).
- `App/AppModel.swift`
  - Add `import Carbon.HIToolbox` for `IsSecureEventInputEnabled()`.
  - Add `private var secureInputTracker = SecureInputTracker()`, plus observable read-only
    `private(set) var secureInputActive = false` and `private(set) var secureInputHolder: String?`
    for the UI.
  - Add `private func refreshSecureInput()`:
    - Call `update(isEnabled: IsSecureEventInputEnabled(), frontmostAppName: NSWorkspace.shared.frontmostApplication?.localizedName)`.
    - On `.began`: `controller.resetBuffer()`, mirror the observable properties, and
      `Self.log.info("Secure Input began (frontmost: …)")`.
    - On `.ended`: mirror, log.
  - Call `refreshSecureInput()` at the top of `refresh()` (the existing 1.5 s status poll) and at the
    top of `handleAppActivation`.
  - `toggleVietnameseFromHotKey()`: when `secureInputActive`, log once per press at info level and
    return without toggling. This covers both the modifier-only detector and the Carbon hot-key path.
    The menu's "Gõ tiếng Việt" Toggle is a deliberate mouse action and stays working.
  - `persistPerAppStateIfNeeded()`: add `!secureInputActive` to its guard.
  - `handleAppActivation`: skip the `PerAppStore.shared.remember(currentInputState, for: oldBundleID)`
    save while `secureInputActive`. Still update `currentBundleID` and still RESTORE the entered app's
    remembered state.
- `App/KeystoneApp.swift`, `MenuBarLabel`: when `model.secureInputActive`, show
  `Image(systemName: "lock.fill")` instead of the V/E text. Keep the `.onAppear` wiring intact. Use one
  view whose content switches, so `onAppear` is not lost.
- `App/MenuBarContent.swift`: in the status block (`accessibilityTrusted && tapRunning`), when
  `model.secureInputActive`, show
  `Label(SecureInputTracker.statusMessage(holder: model.secureInputHolder), systemImage: "lock.fill")`
  instead of the "Đang gõ tiếng Việt / Đang tạm tắt (EN)" label.
- Tests: new `Tests/KeystoneInputTests/SecureInputTrackerTests.swift`, covering:
  - initial state
  - OFF→ON with a name, and with nil
  - holder kept while ON even when `frontmostAppName` changes
  - ON→OFF clears both
  - repeated identical samples return nil
  - ON→OFF→ON re-attributes to the new frontmost
  - both `statusMessage` strings, exactly
- `DECISIONS.md`: new section "Secure Input: phát hiện và báo (spec §7)". Cover:
  - the 2026-09-28 evidence (WindowServer `CPS: Denying … secureTextInput is active`; Chrome held it
    while Discord had keyboard focus 13:03:45–13:04:44)
  - the attribution caveat
  - why there is no toggle: a passive status plus safety guard with nothing to configure
  - why this lives in AppModel and not the tap's `SystemStateCache`: the tap receives no keystrokes
    while Secure Input is on
  - that `SystemState.secureInputActive` in `Contracts.swift` stays as pre-existing unused scaffolding
- `README.md`: a short user-facing bullet (menu bar shows 🔒 plus the app name, and what to do), and
  a troubleshooting note under "Cấp quyền hệ thống" or a fitting section.
- Do NOT touch `Sources/KeystoneInput/Contracts.swift`'s `SystemState` / `SystemStateCache`.
