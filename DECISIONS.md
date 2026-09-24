# Keystone — Resolved engine decisions (Phase 1)

This resolves the spec's Open Questions for the engine layer.

## Orthography default

Default `Orthography` is **modern** (kiểu mới: `hòa`, `thủy` — tone mark on
the first vowel letter of certain open unmarked diphthongs/triphthongs).
Classic placement (kiểu cũ: `hoà`, `thuỷ`) is opt-in via
`EngineConfig(orthography: .classic)`.

## `z` key semantics

`z` removes the tone only. It does not strip quality marks (circumflex,
breve, horn) by default. E.g. on `â`, `z` yields `a` with tone cleared, not a
plain `a` stripped of the circumflex — the circumflex must be undone by its
own key (double-strike toggle), not by `z`.

## Restore-if-invalid: two layers

1. **Per-key transform rejection (literal fall-through).** A tone or
   quality-mark key that would create an illegal vowel/mark combination is
   *not applied*; the key becomes a literal character appended to the word
   instead. This holds unconditionally, regardless of `restoreIfInvalid`. It
   guarantees, for example, that `chưa` + `a` → `chưaa`, never `chưâ`.

2. **Whole-word restore at commit.** When `restoreIfInvalid` is **on**
   (default) and the committed syllable is not a legal Vietnamese syllable,
   the entire word reverts to the raw keystrokes at commit time. This is what
   makes English words type correctly: `wrong` → `wrong`, `boss` → `boss`.

**Consequence:** the classic double-strike demonstrations `ass` → `as`,
`aaa` → `aa` hold only with `restoreIfInvalid` **off** — they isolate layer 1
in isolation. With `restoreIfInvalid` **on** (the default), those key
sequences revert at commit to the raw keys (`ass`, `aaa`), because the
intermediate form is not a valid syllable AND contains a vowel — a failed
*Vietnamese* syllable that must be protected as English (`ass`/`aaa` aren't
words, but the same rule is what protects `wrong`/`boss`/`coins`, which are).

`ddd` → `dd` and `ww` → `w`, however, hold even with `restoreIfInvalid`
**on** (the default) — a **no-vowel** composed result (`dd`, `w`, `tw`) is
never reverted, restore-on or off. The rule: restore-to-raw fires only when
the composed word contains a vowel; a no-vowel result is a deliberate
literal (standard Telex "double the transform key = one literal key"), not a
failed attempt at a Vietnamese syllable, so there is nothing to protect it
from — it is kept as composed. See `Engine.finalize`'s `compHasVowel` check.

**Doubled-w habit on restore.** Many typists carry over a habit of doubling
`w` to get a literal `w` (since `w`→`ư`, `ww`→`w` in Telex), and apply it to
whole English words: `win`→`wwin`, `swim`→`swwim`. When such a word reverts to
raw at commit, `Engine.collapseDoubledW` first collapses every consecutive
`ww` pair to a single `w`, so it restores to `win`/`swim` rather than keeping
both w's. This is safe because in Telex `w` is *always* the ư/horn key, so a
`ww` pair is always the escape for one literal `w` (never two intended w's);
it only runs on the restore path (invalid/English words), and words without a
`ww` pair (`boss`, `wrong`) are untouched.

## Positional (non-adjacent) marks

Diacritic mark keys may be typed away from their base letter — at the end of the
word or mid-word, the common "bỏ dấu ở cuối" style — not only immediately after
it. Tones are syllable-level (always positional). Quality marks (circumflex,
horn, breve) and đ now also apply to the nearest eligible earlier letter:
`roiof`→rồi, `toiws`→tới, `dangd`/`dadng`→đang, VNI `toi6`→tôi, `moi71`→mới.
A mark is applied non-adjacently only when treating the key as a new nucleus
vowel would form an illegal nucleus (gated by `isNucleusPrefix`), so real
triphthongs (`ngoaos`→ngoáo) and English words (`add`) are left alone. đ only
ever strokes an onset d. Implemented for Telex (aa/ee/oo, w, dd) and VNI (6/7/8/9).

`EngineConfig.allowFreeToneMark` ("Cho phép bỏ dấu tự do") gates this
non-adjacent placement specifically. **Default: `true`** — preserves the
above behavior and the full corpus. When `false`, a quality mark or đ applies
ONLY when adjacent to its target (the current/last nucleus vowel, or an
adjacent `dd`); the non-adjacent branches above don't fire, so the key falls
through to a literal append/restore exactly as it already does whenever a
non-adjacent application is rejected (e.g. `roiof`/`toiws`/`dangd` no longer
reach rồi/tới/đang — they revert to raw keystrokes via `restoreIfInvalid`
instead). Tones (Telex s/f/r/x/j, VNI 1-5/0) are syllable-level and are
never affected by this flag, on or off.

Bounds added to protect common English words (from the full Telex sweep):
- **Circumflex targets only the current (trailing) nucleus** — no consonant
  between the vowel and the buffer end — so `mama`/`nana`/`nono` stay literal
  while `roiof`→rồi, `toio`→tôi (mark within one vowel run) still work.
- **đ fires only on an adjacent `dd` or a closed syllable** (a coda already
  exists): `ddang`/`dangd`→đang, but `dad`/`did`/`deed` stay English. The
  rarer mid-word trigger `dadng` is dropped as the cost of that protection.
- Note: `w` after a vowel and adjacent `oo`→ô are standard Telex (Vietnamese
  keys), so `cow`→cơ, `moon`→môn are correct, not bugs.

## Bỏ dấu ở cuối từ / freeMarkAcrossCoda (Phase 4)

`EngineConfig.freeMarkAcrossCoda` ("Bỏ dấu ở cuối từ (kể cả sau phụ âm)") is a
NEW, separate opt-in flag — **default `false`** — that further EXTENDS the
non-adjacent placement `allowFreeToneMark` already gates. It does not replace
`allowFreeToneMark`; both flags are independent and a user can have either,
both, or neither on. `EngineConfig.freeMarkAcrossCoda` stays **`false`** by
default so the ~251-case corpus and the English-word protection described
under "Positional (non-adjacent) marks" above are completely untouched at the
engine/test level. **The app (`AppModel`), however, ships it ON by default**
(the author types this "bỏ dấu ở cuối" style: `tana→tân`, `dadng→đang`),
accepting the English-word tradeoff (`mama→mâm`); a user can turn it off in
the Control Panel. Keeping the two defaults split lets the corpus keep
exercising the English-safe behavior while the shipped app matches how the
author actually types.

**What it extends, when ON:**
- **Telex circumflex across a coda** (`Telex.swift` case 7): the existing
  non-adjacent search only looks within the trailing, uninterrupted vowel
  run (it breaks at the first consonant walking backward from the end) — so
  `trene` never finds the `e` in `tr` + `e` + `n` to circumflex, because a
  consonant (`n`) sits between them. With the flag on, a fallback search
  walks back across ALL cells (not stopping at a consonant) for the last
  vowel with the same base letter and no mark yet, but only when that vowel
  has at least one consonant between it and the end of the buffer (i.e.
  genuinely across a coda — this never overlaps the existing within-nucleus
  path, which already would have found it otherwise). `trene`→trên.
- **Telex/VNI đ into an open syllable** (`Telex.swift` case 6, `VNI.swift`
  case 9): both already stroke đ on an adjacent `dd`/`d9` or on a
  non-adjacent trigger once the syllable has CLOSED (a coda exists) — gated
  by `allowFreeToneMark`. With `freeMarkAcrossCoda` on, the non-adjacent
  trigger fires even while the syllable is still OPEN (no coda yet):
  `dadng`→đang (the second `d` strokes the onset immediately, before `ng` is
  even typed).

**Accepted English tradeoff, explicit and intentional.** Turning this on
means the same mechanism that enables `trene`→trên and `dadng`→đang also
turns some English words Vietnamese: `mama`→mâm (the across-coda circumflex
fallback) and `dad`→đa (the open-syllable đ extension). This is the
documented cost of the feature and is exactly why it ships OFF by default —
a user opts into it knowingly, the same way `allowFreeToneMark` already
documents its own, narrower version of this tradeoff.

**VNI circumflex-at-end already worked without this flag.** VNI's case 6
(circumflex) already searches across codas via `cells.lastIndex(where:)`
rather than breaking at the first consonant, so `allowFreeToneMark` alone was
already enough for VNI's circumflex-at-end (e.g. an end-of-word `a6` finds
its target across a coda) — there is no English-word ambiguity to gate there
because VNI's mark keys are digits, never letters, so a digit can never be
mistaken for part of an English word the way a repeated `a`/`e`/`o` can in
Telex. `freeMarkAcrossCoda` therefore did not need to change VNI's
circumflex (case 6) at all; it only had to bring **Telex** circumflex to the
same across-coda parity, and add the **đ-open-syllable** extension to both
Telex and VNI (case 9), since đ's onset-only, letter-triggered nature in
Telex has no VNI-digit equivalent that was already safe.

**Note on VNI's đ-open-syllable case in practice.** Because VNI's đ trigger
is a separate digit key (`9`), not the letter `d` itself, a sequence like
`dad9` still has a plain, unstruck `d` sitting in the buffer as a literal
consonant by the time `9` is pressed (VNI never gives `d` any special
onset/đ duty the way Telex's `d` key does). That literal `d` ends up parsed
as the syllable's coda, and `d` is not a legal Vietnamese coda
(`Phonology.codas`), so the whole word fails validation and reverts to raw
keystrokes at commit regardless of `freeMarkAcrossCoda` — verified by running
(`Tests/KeystoneEngineTests/FreeMarkAcrossCodaTests.swift`,
`vniDStrokeOnOpenSyllable`). The flag still correctly extends case 9's fire
condition for parity with Telex; it just cannot rescue this particular
key sequence, because VNI's đ trigger has no way to "consume" an intervening
literal letter the way Telex's letter-triggered đ does.

## Open ươ → uơ downgrade (spec Open Question #7)

An OPEN `ươ` (both horns, the u+o pair is the whole nucleus, nothing after the
o) is not a real Vietnamese nucleus, so at commit it downgrades to `uơ`,
letting `thuowr`→thuở, `huow`→huơ, `khuow`→khuơ be typed naturally with `w`.
Closed forms and offglide forms keep `ươ` (they never reach this shape):
`hương`, `nước`, `người`, `rượu`. The `[` direct key still works too.

## Tone placement

Tone placement follows spec Part A §4 exactly. The modern/classic toggle
affects only the open, unmarked diphthongs/triphthongs `{oa, oe, uy}` — all
other nucleus shapes place the tone identically under both orthographies.

## Stop-coda tone restriction

Syllables closed by a stop coda (`p`, `t`, `c`, `ch`) may carry only **sắc**
or **nặng** — the other four tones (ngang, huyền, hỏi, ngã) are not legal on
a stop-closed syllable and are rejected/restored accordingly.

## Auto-`ươ` policy (spec Open Question #7)

Typing `w` (or `uow`) on an adjacent bare `u`+`o` pair produces **`ươ`** (both
horns) — the common case (`nước`, `được`, `người`, `thương` …). The rare
`uơ` words (`thuở`, `huơ`, `khuơ`) are typed with the `[` direct key on the o
(`hu[` → `huơ`, `thu[r` → `thuở`). Exception: when the `u` is a **`qu`-glide**
(preceded by `q`), only the `o` is horned, since `qươ` is impossible spelling —
so `quow` → `quơ`, `quowr` → `quở`.

## Onset `g` before `i`

`g` needs `gh` before `e`/`ê`, but `g` + `i` is the standard collapsed `gi`
onset before `i` (`gì`, `gìn`, `gỉ`), distinct from `ghì`. The validator allows
`g` before every vowel except `e`/`ê`.

## Input methods (Phase 3)

- **Telex** and **VNI** are fully implemented and share one syllable core
  (`SyllableOps`), so both render byte-identical Vietnamese (pinned by the
  Telex↔VNI differential suite).
- **Quick Telex** (gõ nhanh) is a config toggle (`EngineConfig.quickTelex`, off
  by default) layered on Telex: `cc→ch, gg→gi, kk→kh, nn→ng, pp→ph, qq→qu,
  tt→th` at onset/coda; `dd→đ` is unchanged.
- **Simple Telex 1 / 2**: the spec's reduced-collision definitions (§2.5) are
  explicitly clean-room and unverified against OpenKey (Open Q #1). Until we can
  black-box test real OpenKey behavior, `.simpleTelex1`/`.simpleTelex2` dispatch
  to the full Telex interpreter (a safe superset — the `[`/`]` direct keys are
  already enabled). Revisit with parity testing before claiming distinct
  semantics.

## Macros / gõ tắt (Phase 4)

This resolves the spec's Open Question #9 (where macro expansion fires in the
pipeline).

**Firing point: word commit, against the RAW typed buffer.** A macro is
matched against `Engine.rawKeys` — the literal ASCII keys typed since the
last boundary — not against the rendered/folded Vietnamese text. Matching
happens at commit (a boundary character, or an explicit flush) and is
case-sensitive and exact (no prefix/fuzzy matching). A macro never fires
mid-syllable.

**Precedence: macros win over everything else.** Inside `Engine.finalize`,
the macro check runs first, BEFORE Vietnamese rendering and BEFORE
restore-if-invalid. If the raw word matches an enabled macro, the entire
on-screen composed word (`prevUnits.count` code units — not a diffed
prefix) is deleted and replaced by the macro's expansion; restore-if-invalid
never runs for a macro hit. This means a macro can override what would
otherwise be a perfectly valid Vietnamese syllable (e.g. a macro trigger
`as` beats Telex's `as` → `á`).

**Two-path model**, because Vietnamese rendering only happens while
Vietnamese input is active:
- **Vietnamese-mode**: inside `Engine.finalize(boundary:)`, gated by
  `EngineConfig.macrosEnabled`. On a hit, the boundary character (if any) is
  appended to the synthesized replacement text, since the whole edit
  (backspace + text) replaces everything, including the boundary, on screen.
- **English-mode** (Vietnamese input off): a separate, independent buffer
  (`Engine.englishRawKeys`) and entry points (`processInactive`,
  `flushInactive`, `resetInactive`), gated by BOTH `macrosEnabled` AND
  `macrosExpandWhenVietnameseOff` (checked in `EngineController.handle`, not
  inside `Engine`, so `Engine` doesn't need to know why it was called). Every
  keystroke passes through physically in this mode — `suppress` is always
  `false` — so the boundary character is delivered by the OS itself and must
  NOT be duplicated into the returned edit's text.

**Duplicate triggers: last one wins.** `MacroTable.init` first drops
disabled rules, then builds a `[String: MacroRule]` dictionary from the
survivors in order — so if two *enabled* rules share a trigger, the later
one in the list overwrites the earlier one. A disabled rule is simply
excluded before this step; it cannot "clear" an earlier enabled rule with
the same trigger by appearing later in the list. An **empty trigger** is
rejected too (both in `MacroTable.init` and in `parseTabSeparated`): it
would otherwise match the empty raw buffer and fire on every bare commit.
`MacroStore.importFile` likewise refuses to replace the user's macros with
an empty parse — a file that is neither valid JSON nor a tab-separated macro
list surfaces the decode error instead of silently wiping the list.

**autoCapitalize semantics, and why it's dormant.** `Engine` tracks
`atSentenceStart`: `.`, `!`, `?`, and newline boundaries start a new
sentence (a `.`/`!`/`?` only once whitespace confirms it — see "Auto-capitalize:
dấu kết câu phải có khoảng trắng theo sau" below); committing any word (via
any other boundary) ends it. A macro's
replacement gets its first character uppercased only when ALL of: the
per-macro `MacroRule.autoCapitalize` is on, the global
`EngineConfig.macroAutoCapitalize` is on, the cursor is at a sentence start,
and the replacement's first character is a lowercase letter
(`MacroTable.expandedText`). `MacroRule.autoCapitalize` defaults to `false`
per macro — so even though the global toggle defaults to `true` (mirroring
OpenKey's own default) and `AppModel.macrosEnabled` defaults to `true` (an
existing pre-Phase-4 UI default we keep, per "ships dormant unless already
configured"), the feature has no observable effect until a user (a) adds at
least one macro, and, for capitalization specifically, (b) opts that macro
into `autoCapitalize` explicitly.

**Legacy import.** `MacroTable.parseTabSeparated` reads OpenKey-style
`trigger<TAB>replacement` files: blank lines and lines without a tab are
skipped, and a trailing `\r` is trimmed per line (splitting is done on the
raw LINE FEED *scalar*, not the `Character` "\n", because Swift's grapheme
clustering merges a CRLF pair into a single `Character` that would never
match a bare "\n" separator). `MacroStore.importFile` tries JSON first and
falls back to this parser on failure, so both `.json` exports and legacy
`.txt` files work from the same "Nhập gõ tắt…" menu item.

## Smart-switch / per-app state (Phase 4)

Resolves spec **E.7** ("Smart-switch / đổi app") and **Part C §7** ("Settings
store & engine binding", §7.1 off the hot path / §7.2 persistence).

**Two independent toggles**, both pre-existing on `AppModel` (previously
inert scaffolding, now wired):
- `smartSwitch` ("Chuyển chế độ thông minh") — remember/restore
  **Vietnamese on/off** per frontmost app.
- `rememberCodePerApp` ("Tự ghi nhớ bảng mã theo ứng dụng") — remember/
  restore the **code table** per frontmost app.

Either, both, or neither may be on; each field of the remembered state is
applied independently of the other (`SmartSwitch.resolve` in
`Sources/KeystoneInput/PerAppState.swift`). With both off, behavior is
unchanged from before Phase 4: only the existing engine-buffer reset on app
switch happens. An app Keystone has never seen (`remembered == nil`) always
keeps the current state — there is nothing to restore yet, so the first time
you visit an app it does not silently flip anything.

**Off the hot path (E.7 / §7.1).** All of this runs inside the existing
`NSWorkspace.didActivateApplicationNotification` observer in
`AppModel.bootstrap()`, on the main queue — never inside the CGEventTap
callback. The observer already reset the composing buffer before Phase 4;
that reset is unconditional and now runs first, followed by the per-app
resolve/restore logic only when at least one toggle is on.

**Keystone's own bundle id and `nil` ids are skipped.** The bundle id is read
from `notification.userInfo?[NSWorkspace.applicationUserInfoKey]`. If it's
`nil` or equals `Bundle.main.bundleIdentifier`, Keystone's own windows (e.g.
the Control Panel) never cause a state flip — only the buffer reset applies.

**Save-on-leave + save-on-manual-change + restore-on-enter:**
1. On activation, if tracking is on, the state we're leaving (`enabled` +
   `codeTable` for the previous `currentBundleID`) is saved first, *then*
   `currentBundleID` advances to the new app, *then* — if something was
   previously learned for the new app — `SmartSwitch.resolve` computes what
   to apply and `enabled`/`codeTable` are set under an `applyingPerAppState`
   guard so step 2 doesn't immediately re-learn the state it's restoring.
2. `enabled`'s and `codeTable`'s `didSet`s call `persistPerAppStateIfNeeded()`
   after their existing engine-push work, so a manual toggle/menu change is
   learned for the current app right away, not only at the next app switch.
   This is skipped while `applyingPerAppState` is true (see above), while
   tracking is off, or before `currentBundleID` is known (e.g. at launch,
   before the first activation notification arrives).
3. `currentBundleID` itself is tracked regardless of whether tracking is on,
   so flipping a toggle on mid-session has an app to persist against
   immediately rather than waiting for the next switch.

**Persistence.** The pure `PerAppStateStore` (`Sources/KeystoneInput/PerAppState.swift`,
a `[bundleID: AppInputState]` dictionary, `Codable`, no I/O) is wrapped by
`App/PerAppStore.swift` (`@Observable @MainActor` singleton, mirrors
`MacroStore`'s pattern), which loads/saves it as JSON at
`~/Library/Application Support/com.tanta.keystone/appstates.json`. A missing
file on first run is normal and not logged as an error; a decode failure
*is* logged (via `Logger`) and leaves the in-memory store as-is rather than
silently presenting a corrupt file as "no learned apps".

**`resetToDefaults()` does not erase learned apps.** It resets the
`smartSwitch`/`rememberCodePerApp` *settings* to their defaults (as it
already did), but leaves `PerAppStore` untouched — learned data and settings
are separate concerns. Only the explicit "Xoá ghi nhớ theo ứng dụng" button
in the Control Panel's "Chuyển đổi" section (`AppModel.resetLearnedApps()`)
wipes learned apps.

**Deferred / not unit-testable headless.** The live `NSWorkspace` wiring in
`AppModel.handleAppActivation` is integration-only, same reasoning as the
CGEventTap itself — it needs a real app switch to exercise. What's pinned by
`Tests/KeystoneInputTests/PerAppStateTests.swift` is the pure resolver
(`SmartSwitch.resolve`) and the pure store (`PerAppStateStore`) that the live
wiring is built on.

## Nucleus × coda rime (spec §5.3)

A nucleus that ends in a semivowel offglide (falling diphthongs/triphthongs:
`ai`, `oi`, `ui`, `ươi`, `iêu` …) cannot take a true consonant coda. This
protects English words such as `coins`, `ruins`, `rains` (which would otherwise
become pseudo-Vietnamese) while keeping genuine rimes like `oan` (`toán`,
`loán`), `uôn` (`muốn`) and `uyt` (`suýt`) valid.

## System toggles (Phase 4)

Three of the "Hệ thống" tab toggles in `AppModel` moved from persistence-only
scaffolding to real behavior; a fourth stays dormant on purpose.

**`runAtLogin` → `SMAppService.mainApp`.** `didSet` persists first, then
`register()`/`unregister()`s the login item. A failed call is logged via
`Logger.error` with context and the property is reverted to its actual state
(rather than leaving the toggle claiming a login-item state that isn't true),
guarded by a private `isSyncingLoginItem` flag so the revert's own
reassignment doesn't re-enter `didSet` and fire another register/unregister.
`bootstrap()` calls `reconcileLoginItemStatus()` once at launch, under the
same guard, to catch drift between the persisted toggle and
`SMAppService.mainApp.status` (e.g. the user removed the login item from
System Settings directly): `.enabled` → `true`, `.notRegistered`/`.notFound`
→ `false`, `.requiresApproval` is left as-is and just logged.

**`showDockIcon` → `NSApp.setActivationPolicy`.** `didSet` sets `.regular`/
`.accessory` and, when turning the icon on, also calls
`NSApp.activate(ignoringOtherApps: true)` so the new Dock tile is focused
immediately rather than sitting there unfocused.
`AppDelegate.applicationDidFinishLaunching` in `KeystoneApp.swift` now sets
the *initial* policy from the persisted setting
(`AppModel.shared.showDockIcon ? .regular : .accessory`) instead of the old
hardcoded `.accessory`; the single-instance check → policy → `bootstrap()`
order is unchanged.

**`openControlPanelAtLaunch` → a scene-registered `openWindow` closure.**
`AppDelegate`/`bootstrap()` run before any SwiftUI scene exists, so
`openWindow` isn't available there. Instead, `AppModel.openControlPanelRequest`
is a closure the SwiftUI layer fills in once its scene appears —
`MenuBarContent`'s `.onAppear` captures `@Environment(\.openWindow)` and sets
`model.openControlPanelRequest = { openWindow(id: WindowID.controlPanel) }`,
then calls `model.performLaunchOpenIfNeeded()`, which (guarded by
`didAttemptLaunchOpen` so it only ever acts once) activates the app and
invokes the closure if `openControlPanelAtLaunch` is on.

**`checkForUpdates` stays dormant.** Real update checking needs a signed
release feed / appcast (Sparkle), which is Phase 5 work and doesn't exist
yet. The toggle still persists to `UserDefaults` as before; nothing reads it
yet.

**Integration-only, not unit-testable headless.** `SMAppService`,
`NSApp.setActivationPolicy`, and `openWindow` all need a real running app
(same reasoning as the CGEventTap and the `NSWorkspace` smart-switch wiring
above) — verified by building and by manual exercise on a real Mac, not by
new unit tests.

## Quick consonants & auto-capitalize (Phase 4)

Three more `EngineConfig` fields, all default OFF (dormant):
`quickStartConsonant`, `quickEndConsonant`, `autoCapitalize`.

**Start-shortcut is onset-only, and only on the word's first keystroke.**
`f`, `j`, `w` already have Telex jobs (huyền, nặng, horn/bare-ư) that fire
constantly mid-word — `quickStartConsonant` cannot simply reinterpret those
keys everywhere without breaking existing tone/horn typing (`af`→`à` must
keep working). So the shortcut is gated on `cells.isEmpty`: it only ever
fires as the very first key of a fresh word (`f`→`ph`, `j`→`gi`, `w`→`qu`),
checked at the very top of `Telex.apply`, before the tone-key branch. Casing
rule: the first letter of the cluster takes the typed key's case, the rest is
lowercase — this gives the natural `"Fa "`→`"Pha "`, `"Wa "`→`"Qua "`. A
would-be all-caps cluster (holding shift through the whole shortcut trigger)
isn't specially cased by this feature — that's an accepted rare edge, not a
goal for v1.

**End-shortcut fires only immediately after a vowel.** `g`, `h`, `k` are not
tone/mark keys, so unlike the start-shortcut they always reach Telex's case 8
("any other consonant") — but expanding them unconditionally would corrupt
ordinary words: "tong" (t-o-n-g) must not become "tonng" just because it
contains a trailing `g`. The fix is the same shape check either way: only
expand when `cells.last?.isVowel == true`, i.e. the key lands right where the
nucleus just closed (`"tog"`→`"tong"`, `"vih"`→`"vinh"`, `"bak"`→`"bach"`),
never when a consonant already closed the coda (`"tong"` stays `"tong"`).
This check lives inside case 8, before the existing `quickTelex` doubling
block, so both features can coexist without one shadowing the other.

**Test isolation note:** `EngineTogglesTests`'s end-consonant suite sets
`restoreIfInvalid: false`. This isolates the per-key coda expansion from the
separate whole-word phonotactic-validity restore layer (see "Restore-if-
invalid: two layers" above) — e.g. a *ngang*-toned `"bach"` is rejected by
Phonology's stop-coda tone restriction (§5.4: `p`/`t`/`c`/`ch` codas require
sắc/nặng), so with `restoreIfInvalid` **on** (the real default) that
particular expansion would actually revert to raw keystrokes at commit, same
as any other stop-coda word typed without a sắc/nặng tone. That's expected,
existing behavior of the restore layer, not a bug in the new shortcut.

**Auto-capitalize is commit-time and reuses `atSentenceStart`.** `Engine`
already tracked `atSentenceStart` for macro capitalization; `autoCapitalize`
reuses the same flag instead of adding a second tracker. In `finalize`, when
`config.autoCapitalize && atSentenceStart && !rawKeys.isEmpty`, the
sentence-initial word's first letter is capitalized right before the edit is
computed — on the un-capitalized `Composition` for the restore-if-invalid
branch (uppercasing `rawKeys.first` before `table.plain`, so English words
like `"hello"` also capitalize via the restore path) and on a local `var
comp` for the normal render branch (`comp.cells[0].isUpper = true` before
`encode`). `isValid(comp)` is evaluated on the *un-capitalized* composition
first, since capitalization never changes phonotactic validity. An
already-uppercase first letter is left alone. This only runs after the
macro-hit branch has already returned, so a fired macro's own
`autoCapitalize`/`macroAutoCapitalize` handling is untouched. Because the
first letter's on-screen code unit changes, the commit diff naturally
produces the backspace+retype that turns the lowercase-while-composing first
letter into its capitalized form only once the word commits — so a
sentence-initial word visibly shows lowercase while still being typed and
flips to uppercase at commit. Accepted for v1.

All three flags default OFF; `App/AppModel.swift`'s
`quickStartConsonant`/`quickEndConsonant`/`autoCapitalize` properties (previously
persistence-only scaffolding) now also call `pushConfig()` in their `didSet`,
same pattern as `quickTelex`/`restoreIfInvalid`.

**`autoCapitalize` defaults OFF at the app layer too, and `reset()` clears
`atSentenceStart`.** `App/AppModel.swift`'s `autoCapitalize` UI toggle used
to default `true` (a leftover from before this flag was wired to the
engine), out of step with `EngineConfig`'s own OFF default above — it is now
`false` in both `loadBool(..., default:)` and `resetToDefaults()`.
Sentence-start detection is unreliable in a system-wide IME (no real
knowledge of cursor context), so the feature stays opt-in. Separately,
`Engine.reset()` — called on caret moves, app switches, and other nav keys —
now sets `atSentenceStart = false` instead of `true`: a reset has no actual
information that the next word starts a sentence, so it must not
auto-capitalize it. Only a real sentence terminator (`.`/`!`/`?`/newline)
seen by `updateSentenceStart` sets it back to `true` (refined below:
`.`/`!`/`?` now also need whitespace after them — see "Auto-capitalize: dấu
kết câu phải có khoảng trắng theo sau"). A brand-new `Engine`'s
stored-property initial value is untouched (still `true`), so a fresh
engine's very first word is still treated as sentence-initial — this is what
the existing `AutoCapitalizeTests` suite (fresh engines) relies on.

## Auto-capitalize sau Enter / đầu dòng (Return → commitNewline)

**Bug:** `autoCapitalize` never fired at the start of a new LINE. Pressing
Return/KeypadEnter went through `KeyTranslator` as `.commitPassthrough`
(grouped with Tab/arrows/Escape), which calls `Engine.flush()` →
`finalize(boundary: nil)` — that commits the pending word but never touches
`atSentenceStart`. A `.`/`!`/`?` boundary works because those are ordinary
characters that flow through `process` and hit `updateSentenceStart`; Return
never becomes a character at all, since `KeyTranslator` intercepts it by
`keyCode` first. Net effect: a bullet line like `"- muc"` typed right after
Enter stayed `"- muc"` instead of `"- Muc"`.

**Fix:** split Return (keyCode 36) and KeypadEnter (76) out of
`.commitPassthrough` into a new `KeyDecision.commitNewline` case
(`Contracts.swift`). `EngineController.handle(_:)` routes it to two new
`Engine` methods — `flushNewline()` (active) and `flushInactiveNewline()`
(Vietnamese off, English-macro path) — that finalize exactly like
`flush()`/`flushInactive()` (`finalize(boundary: nil)` /
`matchEnglishMacro(boundary: nil)`, so no `\n` is ever added to the returned
edit text — the physical Return key already inserts the newline via
passthrough) and then force `atSentenceStart = true`. Other commit keys
(Tab/arrows/Home/End/PageUp/PageDown/Escape) stay `.commitPassthrough` and do
NOT start a new sentence — only Return/KeypadEnter carry real "new line"
information.

Covered by `EngineTogglesTests.swift`'s `AutoCapitalizeAfterNewline` suite
(newline re-capitalizes after a mid-sentence word; a `- ` bullet right after
Enter capitalizes the word that follows it; behavior is a no-op with
`autoCapitalize` off) and `TranslatorTests.swift` (`keyCode 36`/`76` →
`.commitNewline`, `keyCode 48` (Tab) still `.commitPassthrough`).

## Auto-capitalize: dấu kết câu phải có khoảng trắng theo sau

**Bug:** any `.`/`!`/`?` was a sentence boundary the instant it was typed,
even glued to the next word — `"readme.m"` + Tab gave `"readme.M"`;
`"google.com "` → `"google.Com "`; `"obj.method("` → `"obj.Method("`. Macro
`autoCapitalize` shared the same bug in both Vietnamese and English mode
(one shared tracker).

**Fix:** a tri-state `SentencePosition` (`.midSentence` / `.afterTerminator`
/ `.sentenceStart`, `Sources/KeystoneEngine/SentencePosition.swift`) replaces
`atSentenceStart: Bool`. `after(boundary:committedWord:)`: a committed word
collapses to `.midSentence` (cancelling a pending terminator too); `nil`
(flush/Tab/arrows) leaves the state as-is; a newline always goes to
`.sentenceStart`; `.`/`!`/`?` always opens `.afterTerminator`; whitespace
promotes a pending `.afterTerminator` to `.sentenceStart`; a letter or digit
glued onto it cancels it back to `.midSentence`; anything else (quotes,
brackets, markdown closers `*`, `_`, `` ` ``, `~`, "," "-" "(" "|" ...) is
transparent. `Engine.atSentenceStart` is now computed over
`sentencePosition`; the one new wire is `process`'s `rawKeys.isEmpty` early
return also calling `updateSentenceStart`, the path the confirming space
after a "." takes.

**Deliberate behavior changes** (this fix's side effects, not bugs):
- Telex `nawm 2020. tieeps` → "Năm 2020. Tiếp" (was "tiếp"), matching English mode.
- after Enter `...vaf` → "...và" (was "...Và") and `.gitignore` stays lowercase
  (was ".Gitignore").
- Telex `hoa. 3.14 lan` → "Hoa. 3.14 lan" (was "Lan": the "." inside the number
  opens the window and the digit cancels it).
- `hoa.<Tab>lan` → lowercase "lan" (was "Lan") — Tab/arrows/Escape carry no
  character, deliberately conservative (Tab may be focus change or shell completion).

**Accepted limitations:** the rule is simply "terminator + whitespace =
sentence end" (the UniKey/OpenKey-style behavior Tân asked for; not verified
against those apps). Telling an abbreviation apart would need a dictionary, so
"e.g. x" → "e.g. X" (was "e.G. X") and "TP. hcm" → "TP. Hcm". A
comma/semicolon/colon right after the terminator is transparent too, so
"e.g., x" → "e.g., X" (was "e.G., X" — only the glued "g" changed). A Telex
sentence opening with a bare number still capitalizes the next word:
`hoa. 3 lan` → "Hoa. 3 Lan" (unchanged). A passthrough Backspace over the
terminator or over the confirming space is invisible to the engine.

**Tests:** `SentencePositionTests.swift` covers `after` in isolation; the
`AutoCapitalizeTerminatorNeedsWhitespace` suite in `EngineTogglesTests.swift`
covers the engine wiring (bug repros, VNI, markdown closers, Tab/reset/newline
pins).

## Auto-capitalize: resetInactive() cũng xoá vị trí đầu câu

`Engine.reset()` (active-mode `.resetPassthrough`, plus mouse clicks, app
switches and deactivation in both modes) already reset `sentencePosition` to
`.midSentence`, but `resetInactive()` — English mode's `.resetPassthrough`,
i.e. a Cmd/Ctrl/Option chord such as Cmd+V or Option+← — only cleared
`englishRawKeys`. So such a chord right after `"hoa."` still left a pending
terminator standing, and on a fresh engine the initial `.sentenceStart`, and
`" md"` / `"md"` after it expanded the `md` macro as `"Markdown"` instead of
`"markdown"`. A reset key carries no information that the next word starts a
sentence, so `resetInactive()` now also sets `sentencePosition =
.midSentence`, same as `reset()`. Covered by `EngineTogglesTests.swift`'s
`EnglishModeResetClearsSentenceStart` suite.

## Onboarding / permissions (Phase 4)

Resolves spec **§5 "Onboarding / permissions flow"**.

**No separate `PermissionsModel`.** The spec sketches a standalone
`@Observable PermissionsModel` with its own 1 s poll timer. `AppModel`
already observes `accessibilityTrusted`, `inputMonitoring`, `tapRunning`, and
`needsRelaunch`, refreshed every 1.5 s by the `statusTimer` started in
`bootstrap()` (pre-existing, not new). `App/OnboardingView.swift` binds
directly to those fields instead of duplicating the polling — one status
timer for the whole app, not two.

**Accessibility is required, Input Monitoring is recommended.** The
Accessibility card has no way to be dismissed short of granting it or
finishing/deferring onboarding entirely — the tap cannot exist without it.
The Input Monitoring card is informational: its buttons help, but nothing
in the flow blocks on it, per the spec's "don't hard-block" note.

**The relaunch affordance covers "granted but not yet effective".** A fresh
Accessibility grant often doesn't take effect for an already-running
process. `AppModel.needsRelaunch` (existing) goes true once the tap has
failed to come up a couple of refresh cycles after trust was granted; the
Accessibility card shows a "Khởi động lại Keystone" button (→
`model.relaunch()`, existing) in that state instead of polling forever.

**Auto-opens once at first launch, reachable afterward from the menu.**
`AppModel.needsOnboarding` is `!accessibilityTrusted && !didFinishOnboarding`
— a new persisted flag, same `loadBool`/`Keys` pattern as the app's other
settings. The single-window launch mechanism
(`AppModel.openControlPanelRequest` / `performLaunchOpenIfNeeded()`) is
generalized to `openWindowRequest: ((String) -> Void)?` so it can open either
window; `performLaunchOpenIfNeeded()` now checks `needsOnboarding` first and
falls back to `openControlPanelAtLaunch` — onboarding wins on a first run so
it's seen before any auto-opened Control Panel. Once dismissed, it stays
reachable via the menu bar's new "Hướng dẫn cấp quyền…" item
(`MenuBarContent.swift`), so a user who deferred permissions can come back
to it.

**The user is never trapped.** The footer button
("Bắt đầu gõ" when Accessibility is trusted, "Để sau" otherwise) is never
disabled; either label calls `model.finishOnboarding()` (sets
`didFinishOnboarding = true`) then `dismiss()`. Deferring is always available.

**No macOS-26-only APIs.** The spec's sketch uses `.glassEffect`/
`.buttonStyle(.glassProminent/.glass)` (Liquid Glass, macOS 26). The
deployment target here is conservative (macOS 13/14), so the shipped
`OnboardingView` uses `.regularMaterial` card backgrounds, a `RoundedRectangle`
stroke, SF Symbols, and `.buttonStyle(.borderedProminent)` for primary
actions instead — same visual intent (cards, live status, a prominent
action), widely-available APIs.

**Integration-only, not unit-testable headless.** Same reasoning as the
CGEventTap, `NSWorkspace` smart-switch wiring, and `SMAppService`/
`openWindow` system-toggle wiring above: `AXIsProcessTrusted`,
`IOHIDRequestAccess`, `NSWorkspace.shared.open`, and the SwiftUI
`Window`/`openWindow`/`dismiss` machinery all need a real running app and a
real permission dialog to exercise. Verified by `swift build` staying clean
and by the existing engine/input suites staying green (68 + 36 tests) — no
fabricated unit tests were added for this UI layer.

## Phím chuyển / switch-language hotkey (Phase 4, custom combos in Phase 7)

Resolves the `switchKeyModifier` scaffolding left in the Phase 4 system-
toggles work ("Phím chuyển:" picker with no hot key actually registered).
Phase 7 then replaced the fixed four-chord picker with a user-recordable
combo — any modifiers, optionally plus one real key — see "Custom combos"
below for what changed and why.

**Modifier-only chord, detected via a pure `SwitchKeyDetector`.** OpenKey's
"Phím chuyển" isn't a single key — it's a chord like Ctrl+Shift that toggles
Vietnamese input when pressed and released *cleanly*, with no other key
pressed in between. That "cleanly" requirement is the whole point: it's what
lets `SwitchKeyDetector` tell a bare Ctrl+Shift tap apart from an ordinary
shortcut like Ctrl+Shift+C, which must never toggle the input state. The
detector is a tiny arm/cancel state machine (`Sources/KeystoneInput/
SwitchKeyDetector.swift`): `flagsChanged(active:)` arms when the live
modifier set exactly matches `target`, fires `true` only when the set then
returns to empty while still armed and not cancelled, and `otherKeyPressed()`
(fed from `.keyDown`) cancels an armed chord — so does any modifier joining
the chord that isn't part of `target` (e.g. Command joining a Ctrl+Shift
chord). `target` was originally one of four fixed chords (Phase 4); Phase 7
lets it be ANY non-empty `ModifierSet`, so the detector logic itself needed
no change — only more `target` values to test with (`ModifierSet` targets:
single modifier, three modifiers, ⌥⌘). Pinned by `Tests/KeystoneInputTests/
SwitchKeyDetectorTests.swift`.

**`ModifierSet`, not `NSEvent.ModifierFlags`, at the detector boundary.** The
detector lives in `KeystoneInput`, which has no AppKit dependency and must
stay unit-testable headless — same constraint as every other pure type in
`Contracts.swift`. `App/AppModel.swift` maps `NSEvent.modifierFlags` to
`ModifierSet` at the edge (`ModifierSet(nsEventFlags:)`).

**`NSEvent` global + local monitors, deliberately NOT the CGEventTap.** The
tap is this project's most stability-critical code and this feature has no
business anywhere near its hot path — a bug here must never be able to wedge
every keystroke in every app. So the modifier-only path is wired entirely
through AppKit `NSEvent.addGlobalMonitorForEvents`/`addLocalMonitorForEvents`
(`matching: [.flagsChanged, .keyDown]`) in `AppModel.bootstrap()`/
`shutdown()`, independent of `EventTapController`. The global monitor is what
lets the chord fire while some other app is frontmost; like the tap, it needs
Accessibility to see other apps' events, but unlike the tap its absence is
harmless — the hot key just doesn't fire globally yet, no crash, no
degraded typing. The local monitor covers Keystone's own windows and must
return the event unmodified (`return event`) — this path only ever reads
modifier/key events, never consumes them. (The modifier+key path is
different — see "Custom combos" below.)

**Concurrency: extract-then-hop, same pattern as the app-activation
observer.** `NSEvent` monitor closures fire on the main run loop but aren't
statically `@MainActor`-isolated, and `NSEvent` itself isn't `Sendable`. Both
monitors pull out only the two `Sendable` pieces they need (the `NSEvent
.EventType` and a computed `ModifierSet`) synchronously in the closure, then
hop via `Task { @MainActor in ... }` into one shared method,
`handleSwitchKeyEvent(type:modifiers:)` — mirroring exactly how
`bootstrap()`'s `NSWorkspace.didActivateApplicationNotification` observer
already extracts a bundle ID before hopping actors. That method feeds
`switchDetector` and, on a fired chord, calls `toggleVietnameseFromHotKey()`
(`enabled.toggle()`, plus `NSSound.beep()` iff `switchKeyBeep`).

**Integration-only, not unit-testable headless.** Same reasoning as the tap
and the `NSWorkspace` smart-switch wiring above: the live `NSEvent` monitors
need a real running app and real system input events to exercise. Only the
pure `SwitchKeyDetector`/`SwitchHotKey` types are unit-tested; the monitor
wiring in `AppModel` and the Carbon registrar in `App/
SwitchHotKeyRegistrar.swift` are verified by `swift build` staying clean and
the existing engine/input suites staying green — no fabricated unit tests
were added for either. The two `NSEvent` monitor closures run on the main
thread and are handled **synchronously** (`MainActor.assumeIsolated`, not a
`Task` hop) so the detector — an ordered state machine — never sees a
cancelling `keyDown` reordered after the releasing `flagsChanged`.

### Custom combos: any modifiers, optional key (Phase 7)

The Phase 4 picker only ever offered four fixed chords
(`SwitchKeyModifier`: ⌃⇧/⌥⇧/⌘⇧/⌃⌥, or off). Phase 7 replaces it with a
recordable `SwitchHotKey` (`Sources/KeystoneInput/SwitchHotKey.swift`, pure —
no AppKit/Carbon): any combination of ⌃⌥⇧⌘, optionally plus one key captured
from a real keystroke (`SwitchHotKey.Key { keyCode, label }`).
`AppModel.switchHotKey`/`switchKeyEnabled`/`switchKeyBeep` replace the old
`switchKeyModifier` property; `SwitchKeyModifier` itself is gone.

**Why a key needs a second, different mechanism (Carbon, not the
detector).** `SwitchKeyDetector` only ever recognizes a chord going back to
*empty* — it has no notion of "this modifier combo plus THIS key was
pressed", and rightly so: teaching it that would put a second key-comparison
path next to the tap-adjacent modifier bookkeeping, in a type whose whole
value is being small and provably correct. So a modifier+key combo
(`switchHotKey.key != nil`) takes an entirely different, OS-level route
instead: Carbon's `RegisterEventHotKey` (`App/SwitchHotKeyRegistrar.swift`),
which — same as the Spotlight/screenshot hot keys — lets the OS consume the
key outright before it reaches any app, needs no Accessibility permission of
its own, and stays off the CGEventTap exactly like the modifier-only path.
`AppModel.applySwitchHotKeyRegistration()` is the single place that decides
which mechanism is live: modifier-only → `switchDetector.target` set,
registrar unregistered; modifier+key → registrar registered, detector target
`nil`; disabled → both torn down.

**Why Shift-only+key is rejected.** `KeyTranslator.decide` (see its header)
only treats command/control/option as hotkey-shaped
(`.resetPassthrough`) — a Shift+key combo is ordinary typing that the engine
still processes (Shift is how capital letters and most punctuation are
typed). Registering e.g. Shift+F as a system-wide hot key would silently eat
every Shift-F keystroke everywhere, including inside Keystone's own composing
logic. `SwitchHotKey.validationError` rejects any combo with a key attached
whose modifiers don't include at least one of ⌃⌥⌘; a modifier-ONLY chord may
still be Shift-inclusive (⌃⇧ is the long-standing default) since there's no
key for Shift to type. `SwitchHotKey.validationError` also rejects zero
modifiers outright (a bare key isn't a hot key).

**Disabled is checked BEFORE validation.** `applySwitchHotKeyRegistration()`
checks `switchKeyEnabled` first and tears both mechanisms down immediately if
it's off — before ever looking at `switchHotKey.validationError`. Checking
validation first (the original Phase 7 order) had a real bug: unchecking
every modifier mid-edit leaves an invalid draft, and the modifier
checkboxes/recorder are `.disabled(!switchKeyEnabled)`, so the ONLY way to
back out is to turn "Bật phím chuyển" off — but the validation-error early
return came first and skipped the teardown, leaving the last valid combo
(possibly a bare single modifier, reachable since Phase 7 allows one) still
live and still toggling Vietnamese while the UI showed the feature off, with
no way to fix it short of re-enabling. `switchKeyEnabled` must always win.

**Invalid combos are never applied while enabled.** Past the
`switchKeyEnabled` guard, `applySwitchHotKeyRegistration()` checks
`switchHotKey.validationError` and returns immediately if it's non-nil,
leaving whichever mechanism (and `appliedSwitchHotKey`, below) was last
successfully applied still running — an in-progress bad edit in the Control
Panel (e.g. unchecking every modifier while deciding what to record next)
never drops a working hot key. The reason surfaces via
`AppModel.switchKeyError` (the Control Panel's red caption) either way.

**`appliedSwitchHotKey` — what's live, separate from the draft being
edited.** `switchHotKey` is the Control Panel's in-progress draft and may be
temporarily invalid or (for a key combo) fail to register; showing it
verbatim in the "Tổ hợp hiện tại" caption would make an actually-still-live
hot key look unset the moment the draft goes bad. `AppModel
.appliedSwitchHotKey` is a separate `private(set)` property, updated ONLY on
`applySwitchHotKeyRegistration()`'s two success paths (and cleared to `nil`
when disabled) — that's what the caption reads.

**`RegisterEventHotKey` failures are logged AND surfaced, never swallowed.**
An OSStatus failure (most commonly `eventHotKeyExistsErr` — the combo is
already claimed by the system or another app) is logged via `NSLog`-style
`Logger` with the OSStatus and the combo's display string, and turned into
the Vietnamese caption "Tổ hợp này đang được hệ thống hoặc app khác dùng".
`SwitchHotKeyRegistrar.register` registers the NEW combo first and only
unregisters the OLD one once that succeeds, so a failed change leaves the
previous, still-valid registration live instead of leaving nothing
registered — the same "keep the last valid one active" behavior as the
validation-error case above, extended to OS-level conflicts. `AppModel`
mirrors this ordering on its own side too: it only clears
`switchDetector.target` (the modifier-only mechanism) AFTER
`hotKeyRegistrar.register` succeeds, so switching from a live modifier-only
chord to a key combo that fails to register leaves the modifier-only chord
running instead of dropping to nothing.

**Re-registering the SAME combo is a no-op, not a false "already in use."**
`didSet` fires even when a property is set to a value equal to its current
one (re-recording the same key, or unchecking then re-checking a modifier
back to the combo that's already live), which would otherwise call
`hotKeyRegistrar.register` for the exact `(modifiers, keyCode)` pair
`hotKeyRef` already holds — and Carbon rejects that as
`eventHotKeyExistsErr`, indistinguishable from a real conflict with another
app. `SwitchHotKeyRegistrar` now remembers the currently-registered pair and
treats a repeat as a successful no-op instead of calling
`RegisterEventHotKey` again.

**`InstallEventHandler` failing is surfaced too, not just logged.** If the
Carbon event handler fails to install (`init`, effectively unreachable in
practice), `RegisterEventHotKey` itself doesn't depend on that handler and
would otherwise still succeed — silently claiming the combo system-wide with
nothing to ever deliver it to, the language never toggling and no error
shown, which is exactly the silent-failure shape this project's rules forbid.
`SwitchHotKeyRegistrar` now tracks `handlerInstalled` and `register()` throws
(the same `RegistrationError` path, so it surfaces the same way) while it's
false.

**Recording a key: a local monitor that consumes exactly one keyDown, scoped
to the Control Panel's own window, with the engine suspended.** The "Phím
kèm:" button in `BasicPane` (`App/ControlPanel.swift`) arms a
`NSEvent.addLocalMonitorForEvents(matching: [.keyDown])`. A LOCAL monitor is
app-wide, not window-scoped, so the handler itself filters to `event.window
=== recordingWindow` (captured as `NSApp.keyWindow` when recording starts)
and passes any OTHER window's keyDown straight through — otherwise a keyDown
typed into a different Keystone window (e.g. "Chuyển mã"/"Gõ tắt", opened
while the Control Panel is merely still in the view hierarchy behind it, so
`.onDisappear` never fires) would be swallowed and recorded as the hot key
instead of reaching that window's text field. A matching keyDown returns
`nil` — consuming it so it never reaches the Control Panel window itself —
then immediately removes the monitor. Escape (keyCode 53) cancels recording
without storing a key, exactly like any modal recorder; any other key is
stored as `SwitchHotKey.Key(keyCode:label:)`, with the label from
`SwitchHotKey.keyLabel(forKeyCode:characters:)` fed
`event.charactersIgnoringModifiers` (NOT `.characters` — held modifiers
already transform that string, e.g. ⌥Z → "Ω", ⌃Z → an invisible control
character), and `keyLabel`'s fallback branch itself strips control
characters and AppKit's private-use "function key" range (U+F700–U+F8FF —
how `NSEvent.characters`/`charactersIgnoringModifiers` spell Home/End/
PageUp/PageDown/Forward-Delete/F13+ when the keyCode isn't one of the named
cases) before falling back further to "Key N". `.onDisappear` on the pane
tears the monitor down too, so navigating away mid-recording can't leave it
consuming keys forever.

`AppModel.beginSwitchKeyRecording()`/`endSwitchKeyRecording()` bracket the
whole recording: they call `EngineController.setActive(false)`/`setActive
(enabled)` directly — bypassing `AppModel.enabled` itself, so the persisted
user-facing toggle is untouched — for the recorder's one-keystroke window.
This is necessary, not cosmetic: with the engine active (the default, and
Vietnamese being ON is the common case), a plain character key is
unconditionally suppressed by `EngineController.handle` and re-synthesized on
a BRAND NEW `CGEvent` with `virtualKey 0` (`TapSink.postText`) carrying
whatever the engine transformed the key into as its Unicode string. The local
monitor would then see only that synthetic event — keyCode 0 (registering as
⌘⌥A on a US layout, not the key the user pressed) and a label derived from
the engine's OUTPUT (Telex "w"→"Ư", a cancelled tone mark→a different letter,
etc.), not the physical key at all. Suspending the engine makes every key
pass through untouched for that one keystroke, so the recorder always sees
the real keyCode and characters.

**Legacy migration, resolved independently from `switchKeyEnabled`.**
`SwitchHotKey.migrateLegacy(rawValue:)` is a pure function from the retired
`SwitchKeyModifier` raw string (`"controlShift"`/`"optionShift"`/
`"commandShift"`/`"controlOption"`/`"off"`/missing/unknown) to `(SwitchHotKey,
isEnabled)`. `"off"` keeps ⌃⇧ as the stored combo but starts disabled — so
turning "Bật phím chuyển" back on needs no reconfiguration — and a missing or
unrecognized raw value falls back to today's default, ⌃⇧ enabled.
`AppModel.loadSwitchHotKeyState()` resolves the combo and the enabled flag
SEPARATELY rather than as one bundled migration result: the combo prefers the
NEW `Keys.switchHotKey` JSON (falling back to the legacy migration's combo
only if that key is absent or fails to decode to a *valid* combo), and
`isEnabled` prefers `Keys.switchKeyEnabled` WHENEVER THAT KEY HAS EVER BEEN
WRITTEN (`UserDefaults.object(forKey:)`, so a stored `false` isn't confused
with "never written"), falling back to the legacy migration's `isEnabled`
only when it's truly absent. The two used to be coupled — the migration
branch returned its own `isEnabled` unconditionally — which meant a user who
only ever flipped "Bật phím chuyển" (and never touched the combo, so
`Keys.switchHotKey` stayed unwritten) had that on/off choice silently
discarded on every relaunch, in BOTH directions (turning it off and losing
that on relaunch; turning a legacy-"off" combo on and losing that too). The
legacy key is read-only from here on — nothing writes
`Keys.switchKeyModifierLegacy` anymore.

**`switchHotKey` is persisted ONLY when actually applied, never as a raw
draft.** The property's `didSet` used to call `AppModel.saveSwitchHotKey`
unconditionally, before validation — so every intermediate state while
editing (unchecking a modifier down to an invalid set, recording a key that
then fails to register against another app) got written to UserDefaults,
and a quit mid-edit would persist a combo that `loadSwitchHotKeyState()` then
rejects on the next launch, falling all the way back to the legacy migration
and silently discarding the user's actual last-good combo (and, compounding
the bug above, potentially their enabled/disabled choice too). Persistence
now happens ONLY inside `applySwitchHotKeyRegistration()`'s two success
paths — modifier-only (always succeeds once valid) and a Carbon-registered
key combo — the same places that update `appliedSwitchHotKey`. An invalid
draft, or a key combo that fails to register, changes neither.

**`switchKeyBeep`, default off.** "Kêu bíp khi chuyển" is a plain opt-in
`NSSound.beep()` on every successful toggle (both firing paths share
`toggleVietnameseFromHotKey()`), independent of which combo is configured.

### Hardening arbitrary modifier targets (Phase 7.1)

Phase 7's `SwitchHotKey` lets the modifier-only chord be ANY non-empty
`ModifierSet`, including a single modifier (⇧, ⌥, or ⌘ alone) — the old fixed
`SwitchKeyModifier` enum only ever offered two-or-more-modifier chords, which
happened to make two classes of bug unreachable. Independent review surfaced
both once single modifiers became legal:

**A target that's a SUBSET of a larger held chord must not re-arm on the way
down.** `SwitchKeyDetector.flagsChanged` used to arm whenever `active ==
target`, full stop — with target=`[.shift]`, holding ⌘⇧Z (Redo) and releasing
⌘ FIRST leaves `active == [.shift] == target`, which looked exactly like a
fresh clean press, and releasing ⇧ next then fired a spurious toggle. The
same shape hits target=`[.command]` with ⌘⇧S, or even the long-standing
default ⌃⇧ via ⌃⌥⇧+key with ⌥ released first. The detector now tracks a
`dirty` flag: any modifier outside `target`, or any real key
(`otherKeyPressed()`), taints the WHOLE hold, not just the moment it happens
— `dirty` only clears when `active` goes fully empty (a real release), so
`active` re-equaling `target` later in the same hold never arms. Pinned by
`SwitchKeyDetectorTests.targetSubsetOfHeldChordDoesNotFireOnCommandReleasedFirst`
and
`.defaultTargetDoesNotFireWhenOptionReleasedFirstFromThreeModifierChord`.

**A modifier-click must cancel an armed chord too, not just a keyDown.** The
`NSEvent` monitors in `AppModel.installSwitchKeyMonitors()` used to watch
only `[.flagsChanged, .keyDown]`. With a two-or-more-modifier default, a
click while holding one of its modifiers was rare enough not to matter; with
a single modifier now legal, shift-click (extend a selection), ⌘-click (open
in new tab, multi-select), and ⌥-click are everyday gestures that would each
spuriously toggle Vietnamese on release. The monitors now also watch
`[.leftMouseDown, .rightMouseDown, .otherMouseDown]` and route them into
`switchDetector.otherKeyPressed()` exactly like a keyDown (see
`AppModel.switchKeyMonitoredEvents`/`handleSwitchKeyEvent`). This is
integration-only, same reasoning as the rest of the monitor wiring below —
verified by `swift build` staying clean and the existing suites staying
green, not a fabricated unit test.

## Menu-bar mode indicator (V / E)

The `MenuBarExtra` label shows a bold **`V`** while Vietnamese input is on and
**`E`** while it's off, instead of an icon — the current mode is readable at a
glance and is the immediate visual feedback for the "Phím chuyển" toggle above.
Driven by `AppModel.enabled` (see `MenuBarLabel` in `KeystoneApp.swift`).

## Input-layer compatibility toggles (Phase 4)

`sendEachKeystroke` and `autoFixSuggestion` ("Hệ thống" tab) moved from
persistence-only scaffolding to real behavior in `EventTapController`'s
posting path — the CGEventTap output side, this project's most
stability-critical code.

**`InputBehavior` snapshot, same lock/snapshot pattern as `EngineController`.**
`Contracts.swift` gained a plain `InputBehavior` value type
(`sendEachKeystroke`, `textOnKeyDownOnly`). `EventTapController` holds one
behind an `OSAllocatedUnfairLock` (`behaviorLock`) and exposes
`updateBehavior(_:)`; `AppModel.pushInputBehavior()` calls it — mirroring
exactly how `pushConfig()` pushes `EngineConfig` into `EngineController` —
from `bootstrap()` and from both toggles' `didSet`s, after persisting. The
tap's `handle(...)` reads the snapshot **once per edit** (`behaviorLock
.withLock { behavior }`), not once per raw keystroke that passes through
untouched, so the added hot-path cost is exactly one cheap lock acquire on
edits the engine already decided to act on — the same cost class as the
existing `EngineController` config lock.

**`sendEachKeystroke` ("Gửi từng phím") → per-grapheme `postText`.**
`KeystrokeExecutor.execute` gained an `eachGrapheme: Bool = false` parameter:
when true, it calls `sink.postText(String(ch))` once per Swift `Character`
in the result text instead of one `postText(wholeString)` call, after the
same single `postBackspace(count:)` as before. Helps apps that mishandle
multi-char Unicode insertions. Default off, matching `AppModel`'s existing
default.

**`autoFixSuggestion` ("Sửa lỗi gợi ý") → keyDown-only Unicode posting.**
`TapSink.postText` now takes `textOnKeyDownOnly: Bool`. When true, the synthesized Unicode string is set on the keyDown event only —
the keyUp is still posted (tagged with `selfTag`, flags cleared) but carries
no string. When false, both events carry the string, matching the tap's
original behavior. This is the documented remedy for browsers/Excel doubling
synthesized text. It defaults **OFF**, so the tap's default posting is
UNCHANGED (both events, as before) — turning it on is an opt-in switch to
keyDown-only. When enabling it, verify on real browsers/Excel/Terminal — see
HANDOFF.md [VERIFY] #2 for the double-char background. `postBackspace` and the
self-tag/flags logic are unchanged.

**Integration-only, except the executor's per-grapheme split.** Same
reasoning as the tap and the `NSWorkspace`/`NSEvent` wiring elsewhere in this
file: the live keyDown-only posting needs a real synthetic `CGEvent` pair and
a real target app to observe, so it isn't unit-tested. The per-grapheme split
lives in the pure `KeystrokeExecutor` and is covered by
`Tests/KeystoneInputTests/ExecutorTests.swift` against the fake `EventSink`.

## Bảng mã mặc định — Unicode dựng sẵn (NFC), không phải tổ hợp

The app-level default `codeTable` is **`.unicode`** (NFC precomposed), matching
`EngineConfig.codeTable`. This is not a stylistic choice, it is a correctness
one: the tap deletes on-screen text with N literal Backspace keystrokes where
N is `EngineResult.backspaceCount`, and the engine counts that in **code
units** (design spec §6-7). NFC spells every Vietnamese grapheme as exactly one
code unit, so one Backspace = one code unit = one grapheme in every app, and
the count always matches.

`.unicodeCompound` ("Unicode tổ hợp", combining diacritics) spells one grapheme
as base + combining mark(s) — 2-3 code units. A single Backspace then deletes a
whole grapheme in most apps but only one code unit in a few, so the code-unit
`backspaceCount` can under- or over-delete on any diacritic/restore edit,
dropping or duplicating a character in a real app's Backspace handling. NFC has
no such ambiguity. `.unicodeCompound` therefore stays a **Control-Panel opt-in**
for legacy software that specifically needs decomposed Unicode, and must not be
the default. A brief window where it *was* the default (commit "Phase 5 … +
compound default", never tagged/released) is what surfaced this — reverted here.

Related: `AppModel.codeTable`'s `didSet` persists to the global default key only
when `!applyingPerAppState`, so a per-app **restore** can no longer overwrite
the user's chosen startup default (that write is a leak, same class as the
per-app re-learn the flag already guards).

## Duplicate key-down — the phantom-repeat echo guard

> **Correction (2026-09-19): there was never a phantom.** The "duplicate" is
> the user's own Telex tone-CANCEL keystroke, and the doubled letters come from
> `restoreIfInvalid` reverting a word to raw keys that include that keystroke.
> The "Root cause" paragraph below is wrong and is kept only as history. The
> resolution is the paragraph starting "The echo guard is GONE".

**Symptom.** Typing a word with a Telex tone/mark in Vietnamese mode doubled the
diacritic key: `task`→`tassk`, `fix`→`fixx`, `google`→`gooogle`, `mà`→`m`,
`maaf`→`m`. Only keys that make Keystone emit a **Backspace** doubled; plain
keys never did. Worse the faster the typist (more keys, cascading corruption).

**Root cause (a live event-tap file log nailed it).** The tap receives the tone
key **twice** for one physical press. Both copies are indistinguishable — same
keycode, `state=1` (HID), `pid=0`, `autorepeat=0`, each with its own key-up — so
neither source nor flags tell them apart. The duplicate arrives ~120-210ms after
the first, sometimes while the key is still held, sometimes just after its
key-up. It is **100% correlated with Keystone suppressing the key-down and
injecting a Backspace**: on this Mac (`ApplePressAndHoldEnabled=0`, fast
`KeyRepeat`), that suppression makes macOS emit a phantom repeat of the
just-suppressed key. Things that did NOT fix it (verified live): posting via
`CGEventPost` instead of `tapPostEvent`, deferring the injection with
`CFRunLoopPerformBlock`, and OpenKey-style pass-through of unchanged keys — the
phantom is generated regardless.

**Fix — drop exactly one duplicate after a transform (`EventTapController`).**
A physical key cannot be pressed twice without a key-up between, so a key-down
for the just-transformed key — whether it is still held (mis-flagged repeat) or
arrives right after its key-up (phantom) — is spurious. We arm on any key that
emits a Backspace; drop its held repeats until the key-up, then drop one
post-release phantom and disarm; any other key ends the window. Removing exactly
one of a run of identical key-downs is always correct because the engine's own
double-key handling is order-independent (`task`→`task`, `ass`→`as`,
`boss`→`boss` via restore) — it doesn't matter whether the dropped press was the
phantom or a real one. The tap now also masks `keyUp` (to see the release). This
is integration-only (needs a real key stream), so it is not unit-tested; the
pure engine keeps composing whatever keys survive the guard. Synthetic events
still post via `tapPostEvent(proxy)` as before (OpenKey does the same).

**Follow-up bug: holding Delete deleted only one character.** The guard above
armed on ANY key whose transform emitted a Backspace — and Delete, while a
word is composing, does exactly that. So the very key-down that armed the
guard was Delete's own, and every subsequent Delete key-down while held (the
user's genuine OS auto-repeats, not phantoms) matched `armedKey` and was
dropped, not just the one phantom. Holding Delete stopped after a single
character. The fix distinguishes the two cases using the OS autorepeat flag
CGEvent already carries: a phantom duplicate always arrives with
`autorepeat = false` (same as the original press), while a genuine held-key
repeat arrives with `autorepeat = true`. The guard now drops only
non-autorepeat key-downs of the armed key and forwards autorepeat ones, so
holding Delete (or any other transformed key) keeps acting on every repeat
while the single-phantom-after-a-transform case is still caught. The state
machine itself was extracted out of `EventTapController` into a pure,
unit-testable `EchoGuard` (`Sources/KeystoneInput/EchoGuard.swift`,
`Tests/KeystoneInputTests/EchoGuardTests.swift`) — the tap still does the
CGEvent-level wiring (reading `keyboardEventKeycode`/`keyboardEventAutorepeat`
and calling `onKeyDown`/`onKeyUp`/`armIfTransformed`), but the drop/forward
decision itself no longer needs a real event stream to test.

**The echo guard is GONE — and there was never a phantom.** The doubled
letters are reproduced by the engine alone, with no tap, OS or keyboard
involved. Typing English in Telex mode, the user sees a tone appear (`tá`,
`gôgle`, `fĩ`) and, by standard Telex habit, presses that key again to CANCEL
it, so the screen shows the intended word:

| keys typed (cancel habit) | shown before space | after space, `restoreIfInvalid` on |
|---|---|---|
| `t a s s k` | `task` | `tassk` |
| `g o o o g l e` | `google` | `gooogle` |
| `f i x x` | `fix` | `fixx` |

On space the word is not valid Vietnamese, so `restoreIfInvalid` reverts it to
the RAW keystrokes — which contain the cancel key — and the letter doubles. With
`restoreIfInvalid` off, the same keystrokes commit `task`/`google`/`fix`. The
"extra" key-downs seen in every event log were the user's real cancel presses,
which is why they had their own hardware timestamps and key-ups and why
`CGEventSource.keyState(.hidSystemState)` saw the key held. The tell-tale that
was missed for a long time: only Telex keys (`s`, `o`, `x`, `f`) ever doubled.
Plain letters never did. A misdiagnosis of keyboard chatter was also made and
retracted.

So the four filter generations (single-slot arm; 250ms window; 400ms drop-all;
500ms refreshing window) "fixed" it only by eating the user's cancel keystroke.
That is also why they ate real double letters (the second `s` of
`class`/`pass`/`miss`/`address`), which look identical at the key level, and why
they broke held-Delete. **A visible extra character is recoverable by the user;
a silently eaten keystroke is not.** `EchoGuard.swift` and its tests are deleted.

Event-tap experiments that changed nothing, recorded so nobody repeats them:
tap-timeout re-delivery (zero tap-disabled events); `tapPostEvent(proxy)` vs
`CGEvent.post(.cgSessionEventTap)` vs `.cghidEventTap`; deferring the injection
by a run-loop hop or until key-up; synthetic-event flags `[]`,
`.maskNonCoalesced` and the creation default 0x20000000; one pre-created
Backspace pair; `localEventsSuppressionInterval = 0`; and an inert F16 control
pair. None of them could have mattered, because the tap was never at fault.
Three are kept because they are better regardless: the pre-created Backspace pair
(no per-backspace allocation, and deleting feels smoother), the creation-default
flags (what OpenKey sends), and a zero local-event suppression window (an input
method must never swallow the user's own keys after posting). InputMethodKit was
also probed as a cure. It is moot, and macOS 27 rejects an ad-hoc-signed input
method anyway (`amfid` -423).

**Fixed in `restoreIfInvalid` itself, via a lexicon.** It cannot tell a cancel
(`t a s s k` → wants `task`) from an intended double letter (`p a s s` → wants
`pass`). Both leave one `s` composed and two raw. What separates them is which
reading is a real word, and the system word list decides every case above:
`task`✓/`tassk`✗, `pass`✓/`pas`✗, `boss`✓/`bos`✗, `class`✓/`clas`✗,
`fix`✓/`fixx`✗, `passing`✓/`pasing`✗ — implemented below, see "Restore chooses
the composed word when it is the real one".

**Do NOT let plain keystrokes bypass the synthetic channel.** It is tempting:
every printable key is suppressed and re-synthesized, even a letter whose only
output is itself, so returning the physical key unsuppressed looks like free
speed (one suppression + two CGEvents saved on ~80% of keys). It was tried and
it LOSES CHARACTERS. Ordering is only guaranteed inside one callback — events
posted with `tapPostEvent` are delivered before the event that callback returns.
Across callbacks it is not: a plain letter passed through physically can
overtake the Backspace events a tone key posted one callback earlier, and those
Backspaces then delete the new letter (and the engine's model of the screen
drifts from then on). Every character must keep going through the same ordered
channel. The unit tests could not see this — `EngineControllerTests`'
reconstruction helper applies edits in call order by construction — so this is
recorded here instead.

## `restoreIfInvalid` back ON (after the duplicate-key-down fix)

`AppModel.restoreIfInvalid` defaults **true** ("Tự khôi phục phím với từ sai") —
the "auto-drop the diacritic when the word isn't Vietnamese" behavior: a word
whose composed form is not a legal Vietnamese syllable reverts to raw keys at
commit (`hehe`→hêh→`hehe`, `task`→ták→`task`). It was briefly flipped OFF while
the duplicate-key-down bug above made those revert edits corrupt (`task`→`tassk`);
with that bug fixed it is back on, which — together with `freeMarkAcrossCoda` ON
(the author's "dấu ở cuối" style, `tana`→tân) — gives the OpenKey-like result:
Vietnamese types cleanly, English/informal words stay literal, no doubling.
`EngineConfig.restoreIfInvalid` also defaults **true**, matching.

## Restore chooses the composed word when it is the real one

Even with `restoreIfInvalid` back on, the tone-CANCEL habit documented above
under "Duplicate key-down" still doubled a letter, because raw-keystroke
restore is exactly what makes the cancel key visible:

| keys typed | shown before space | committed (raw restore) | wanted |
|---|---|---|---|
| `t a s s k` | `task` | `tassk` | `task` |
| `g o o o g l e` | `google` | `gooogle` | `google` |
| `f i x x` | `fix` | `fixx` | `fix` |
| `c l a s s s s` | `class` | `classss` | `class` |
| `p a s s s s` | `pass` | `passss` | `pass` |
| `m i s s s s` | `miss` | `missss` | `miss` |
| `p r e s s s s` | `press` | `pressss` | `press` |
| `l e s s s s` | `less` | `lessss` | `less` |
| `o f f f f` | `off` | `offff` | `off` |

**The rule** (`RestoreDecision.choose`, `Sources/KeystoneEngine/Lexicon.swift`):

```
use COMPOSED  iff  lexicon != nil
               AND lexicon.contains(composed)
               AND !lexicon.contains(raw)
               AND composed is a SUBSEQUENCE of raw (obtainable by deleting characters only)
otherwise     RAW  (exactly today's behaviour)
```

Both `composed` and `raw` are compared case-insensitively and BEFORE
capitalization — sentence-start auto-capitalize is applied afterward, to
whichever side wins (`Engine.finalize`'s `capitalized(_:if:)` helper), so it
never influences the lexicon lookup itself. `raw` is the collapsed-doubled-w
keystrokes exactly as today's revert already computes them; `composed` is the
on-screen word rendered through the UNICODE table (`outputTable(for: .unicode)`)
regardless of the active code table, since the comparison is against an
English word list and a legacy table's ASCII bytes are identical anyway.

**The subsequence guard.** A genuine Telex tone/mark CANCEL only ever DELETES
characters from what's on screen (`tassk` → `task` deletes one `s`) — it never
introduces a different letter. The quick-consonant toggles (`quickTelex`,
`quickStartConsonant`, `quickEndConsonant`) are a different shape entirely:
they turn a raw consonant into a DIFFERENT, longer spelling (`nn`→`ng`,
`tt`→`th`, `j`→`gi`, `w`→`qu`, `g`→`ng`, `k`→`ch`), which can land composed on
an unrelated real word — `sinning`→`singing`, `nike`→`niche`,
`wilted`→`quilted`, `raged`→`ranged`, `bak`→`bach`. Two code reviewers caught
that the first version of this rule (without the subsequence requirement)
would wrongly commit `niche` for someone who actually typed `nike`, purely
because the lexicon happened to contain `niche` and not `nike` — rewriting
keystrokes the user never typed. `RestoreDecision.isSubsequence` closes that:
composed must be reachable from raw by deletion alone, so every
quick-consonant case above still falls back to `.raw`, matching HEAD.
`RestoreDecisionSubsequenceGuardTests` and `LexiconRestoreQuickConsonantFallsBackToRawTests`
pin it, including the worst case (lexicon contains the wrong composed word
and not raw).

**Why RAW must win when both (or neither) are words, or the subsequence guard
fails.** When both spellings happen to be real words (contrived, but
`RestoreDecisionTests.bothInLexiconChoosesRaw` pins it), when neither is, or
when composed isn't reachable from raw by deletion, raw wins: it's the safer
default, identical to having no lexicon at all, and it's what makes
`Engine.lexicon == nil` byte-identical to the pre-fix engine (see below). Note
this is NOT the same claim as "natural typing of a real word always has raw
in the lexicon" — that claim is false (see "Known limitation" below); it is
`RestoreDecision`'s own fallback-to-raw default, applied whenever the
conditions above aren't ALL met, that keeps things safe regardless of what
is or isn't in the lexicon.

**Dormant-at-engine / enabled-by-app, the same pattern as
`freeMarkAcrossCoda`.** `Engine.lexicon: Lexicon?` defaults `nil` — with no
lexicon installed, `RestoreDecision.choose` always returns `.raw`, so every
existing restore-if-invalid behavior (corpus, `DoubledWTests`,
`LiteralRestoreTests`, ...) is completely untouched at the engine/test level;
`LexiconRestoreDormantWithoutLexiconTests` pins that `tassk` still reverts to
`tassk` with `lexicon: nil`, and `LexiconRestoreClearingLexiconRestoresHeadBehaviorTests`
pins that calling `setLexicon(nil)` AFTER a lexicon was installed restores the
same behavior (not just "never installed"). **The app** additionally gates
this behind its own kill switch, `AppModel.useLexicon` (Control Panel: "Giữ
từ tiếng Anh đang hiển thị (dùng từ điển)", right beside "Tự khôi phục phím
với từ sai", greyed out when that toggle is off) — the lexicon is loaded only
while BOTH `restoreIfInvalid` AND `useLexicon` are on; either turning off
calls `EngineController.setLexicon(nil)` so the `Set` can be freed, and
turning both back on reloads it. Loading always happens off the main thread
(`AppModel.updateLexiconLoaded()`, `DispatchQueue.global(qos: .utility)` —
never blocking startup) and never on the tap thread either, since
`EngineController.setLexicon` takes the same lock as every keystroke and must
not be held for a file read; a generation counter discards a load that
finishes after the gate has since flipped again, so a fast toggle-off can't
be clobbered by a slow in-flight load. `Lexicon` is deliberately kept OUT of
`EngineConfig` for two concrete reasons, not "it's diffed every change" —
nothing in this codebase ever compares two `EngineConfig` values for equality
(`EngineController.updateConfig` just assigns `engine.config = config`, no
diff): (1) `EngineConfig` is `Codable`, which Swift auto-synthesizes only
when every stored property is `Codable` too — `Lexicon` deliberately isn't,
so it could not become a field without hand-writing that conformance for no
benefit; (2) `AppModel.pushConfig()` builds a brand-new `EngineConfig(...)`
value from AppModel's own stored settings on EVERY preference change, even
unrelated ones (`quickTelex`, `allowFreeToneMark`, ...) — folding the lexicon
into that would mean threading a ~236k-entry word list through routine
settings plumbing that has nothing to do with it. Keeping `Engine.lexicon`
a separate stored property, set only by `EngineController.setLexicon`, keeps
the kill switch's load/unload independent of every unrelated settings push.

**Coverage: two supplementary word lists, two different jobs**
(`Sources/KeystoneInput/SupplementaryWords.swift`). `/usr/share/dict/words`
is the 1934 Webster corpus (235,976 entries) and correctly separates every
case in the nine-row table above — but it lacks essentially all modern
internet/software vocabulary (`google`, `email`, `website`, `vietnix`, ...)
AND, separately, a surprising number of ordinary inflections, loanwords,
acronyms and surnames an exhaustive offline search turned up (`fussed`,
`jarred`, `herr`, `oss`, `hassan`, ...) whose COMPOSED (collapsed-double-
letter) form happens to already be a different real word in the system list
(`fussed`→`fused`, `jarred`→`jared`, `OSS`→`OS`, `Herr`→`Her`, `Kerr`→`Ker`).
Without protection, that second kind is worse than "no improvement" — it's a
regression, silently rewriting a correctly-typed real word into a different
one. So `SupplementaryWords` keeps two SEPARATE lists: `all` (modern words,
enabling the COMPOSED side, e.g. `vietnixx`→`vietnix`) and
`protectedRealWords` (old words the 1934 list lacks, protecting the RAW side
so it keeps beating a coincidentally-real composed collapse). Both are merged
by `LexiconLoader.load()`. Neither list carries a vowel-less entry (`http`,
`dns`, `ssl`, ...) or a word that already types as a valid Vietnamese
syllable on its own (`cors`, `meme`, `orm`, `saas`, ...): `Engine.finalize`
only reaches `RestoreDecision` when the composition has a vowel AND fails
Vietnamese phonological validity, so either kind of entry could never
actually be looked up — dead weight, removed rather than kept-but-inert.

**Known limitation: a real word missing from both lists.** A real English
word that is in NEITHER `/usr/share/dict/words` NOR either supplementary
list, typed naturally with a doubled Telex key, can still collapse to the
wrong spelling exactly like it did before this feature existed — e.g., before
`protectedRealWords` was added, `fussed` (typed with `restoreIfInvalid` +
`quickTelex`/tone-cancel habit shaping) collapsed to `fused`. This is a real,
accepted limitation, not a claim that "natural typing always has raw in the
lexicon" — that claim was false and has been removed from this document and
from the code comments that repeated it. `protectedRealWords` covers the
cases an exhaustive offline search against the 1934 corpus actually found,
not every English word that could ever be missing; extending
`SupplementaryWords.all`/`.protectedRealWords` is the fix the next time a
real, commonly-typed word is found falling into this gap. The new
`useLexicon` toggle (Control Panel, see above) is the user-facing escape
hatch for that case: turning it off returns to raw-only restore.

## Auto-update (Phase 5, no Apple account)

Keystone ships a self-contained auto-updater instead of Sparkle: no Apple
Developer account, no third-party update framework, just GitHub Releases plus
an Ed25519 signature Keystone verifies itself.

**Source: GitHub Releases on `tanhattan0051/Keystone`, nothing else.** The
updater only ever calls the hardcoded, HTTPS
`https://api.github.com/repos/tanhattan0051/Keystone/releases/latest`
endpoint, and only ever downloads the two asset URLs *that exact response*
returns — it never follows an update URL from anywhere else (not a web page,
not user input, not a redirect to a different repo). Each release publishes
exactly two assets: `Keystone.zip` (a zipped `Keystone.app`) and
`Keystone.zip.sig` (base64 of the Ed25519 signature of `Keystone.zip`'s raw
bytes). The release tag must be `vMAJOR.MINOR.PATCH` (e.g. `v1.0.1`).

**Mandatory Ed25519 verification before install — no bypass.** An update is
downloaded from the internet and then executed, so signature verification is
the actual security boundary of this feature, not a nice-to-have. The public
key (`MJ8bmdlgJFAYi+M4+Hm3g+phMGDE+lamYdN3DPuiuvA=`, base64, 32 raw bytes) is
embedded in the app. `App/Updater.swift`'s `downloadAndInstall` calls `guard
UpdateVerifier.isValid(zipData:signatureBase64:publicKeyBase64:) else { abort
}` — a `Keystone.zip` that fails verification, or a missing/unreadable
`.sig` asset, is **never** unzipped-into-place or launched; the user sees
"Chữ ký bản cập nhật không hợp lệ — đã huỷ để an toàn" and nothing else
happens. `UpdateVerifier` (`Sources/KeystoneInput/UpdateCheck.swift`) decodes
both base64 inputs defensively and returns `false` on any decode failure
rather than throwing — a malformed signature or key always reads as "not
verified". `Tests/KeystoneInputTests/UpdateCheckTests.swift` proves the gate
actually rejects bad input with a real round-trip: it generates a
`Curve25519.Signing.PrivateKey`, signs bytes, and asserts `isValid` accepts
the genuine (data, signature, public key) triple but rejects tampered data, a
wrong public key, and garbage base64.

**Pure core vs. app-layer glue, same split as the rest of KeystoneInput.**
`Sources/KeystoneInput/UpdateCheck.swift` holds everything unit-testable:
`SemVer` (parses `vMAJOR.MINOR.PATCH`, tolerates a missing leading `v` and a
pre-release/build suffix, `Comparable` by (major, minor, patch));
`ReleaseInfo.parse(latestReleaseJSON:)` (decodes the GitHub API JSON,
requiring both assets, a parseable tag, and `https://` asset URLs — anything
else, including JSON that doesn't even parse, returns `nil` rather than
crashing); `UpdateVerifier.isValid` (the signature gate above); and
`UpdateCheck.shouldOffer(currentVersion:release:)` (a `currentVersion` that
fails to parse is treated as "don't offer" — safer than assuming every
release is newer than a version we couldn't even read). `App/Updater.swift`
(`@MainActor final class Updater`, singleton `shared`) is the integration
glue on top — `URLSession` fetches, `NSAlert` prompts, `Process` calls — and
is not unit-tested headless, same reasoning as the CGEventTap itself.

**Install: strip quarantine, then swap the bundle via a wait-for-exit
relaunch helper.** Once the zip is verified, `Updater` writes it to a temp
dir, extracts with `ditto -x -k` (via `Process`, failures surfaced, never
swallowed), locates `Keystone.app` inside, and runs `xattr -dr
com.apple.quarantine` on it. A running app bundle can't overwrite itself, so
`Updater` writes a small shell script to a temp file that (a) polls `kill -0
<pid>` until this process has exited, (b) `rm -rf` the current bundle path
(`Bundle.main.bundleURL`), (c) `ditto`s the verified new app into place, (d)
`open`s it — launches that script detached via `Process`, then calls
`AppModel.shared.quit()`. Every path is quoted with POSIX single-quote
escaping before going into the script, even though these come from
`Bundle.main`/the verified zip rather than attacker input.

**Current version from `CFBundleShortVersionString`; dev builds skip
auto-install.** `checkForUpdates(userInitiated:)` reads
`Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")`; a
`swift run` build has no meaningful value there, so a missing/unparseable
version silently returns for a background check and shows "Đang chạy bản dev
(swift run) — không kiểm tra cập nhật được" for a user-initiated one — either
way, no network call and no install ever happens for a dev build. A silent
background check (`checkForUpdates(userInitiated: false)`) is kicked off
from `AppModel.bootstrap()` when the persisted "Kiểm tra bản mới khi khởi
động" toggle is on; network/parse errors are logged and swallowed rather than
surfaced, so a flaky connection at launch never nags the user. The "Kiểm tra
bản mới" button in the About pane calls the same entry point with
`userInitiated: true`, surfacing every outcome (error, already up to date,
or the update prompt) as an alert.

**The Ed25519 private key never enters the repo.** It's kept at
`~/.config/keystone/ed25519_private.b64` on the machine that cuts releases
and is used only by the release tooling that signs `Keystone.zip` before
uploading it as a GitHub Release asset — the app only ever embeds and uses
the matching *public* key.

**Standing limitation: still one Gatekeeper prompt, and Accessibility may
need re-granting.** Without Apple notarization, the very first manual
install of Keystone.app still triggers Gatekeeper's "unidentified developer"
prompt once, exactly like today. And unless the app is signed with a stable
self-signed certificate, macOS may treat the swapped-in bundle as a
different app for TCC purposes, so Accessibility (and Input Monitoring) can
require re-granting after an update — the same class of issue
`AppModel.needsRelaunch` already surfaces for a fresh Accessibility grant.

## Screen desync — suppress every character the engine took ownership of, even a no-op one

**Symptom.** Typing certain words — `tasks`, `servers`, `hashes`, `offsets`
— produced a corrupted result instead of the plain English word:
`tasks`→`táasks`, `servers`→`sểervers`, `hashes`→`háashes`,
`offsets`→`óoffsets`. Unlike the "Duplicate key-down" bug above, this one
requires no cancel-key habit at all — the word is typed once, plainly.

**Root cause: `EngineController.handle`'s ACTIVE branch conflated "no-op
edit" with "physical passthrough".** For `.character`/`.backspace` it
computed `noop = r.backspaceCount == 0 && r.text.isEmpty` and returned
`suppress: !noop` — so a keystroke that produced a no-op edit was left
UNSUPPRESSED, reaching the app physically. That is wrong whenever the engine
still took the keystroke into its composing word: `Engine.rerender()`
re-folds the WHOLE word from `rawKeys` on every keystroke, and a mid-word
tone/mark key can be absorbed into `rawKeys` while rendering nothing new
(the fold's net effect on the visible text is zero, even though the key is
now part of the word) — e.g. typing `t a s k s`, the second `s` (after the
`k` coda already closed the syllable) is absorbed with no visible change:
the screen still reads `ták`, but `Engine.rawKeys` is now `tasks`. A no-op
edit is not the same claim as "the engine has nothing to do with this key" —
the old code treated them as the same thing.

Letting that `s` pass through physically means the REAL screen becomes
`táks` (the app inserted it itself) while `Engine.prevUnits` — the engine's
own belief of what's on screen — is still the 3-unit `ták`, because
`rerender()` only ever updates `prevUnits` to what IT rendered, never to
what the app actually displays. The two beliefs are now different, silently.
Nothing looks wrong yet — the desync is invisible until the next edit, which
computes its backspace count against the engine's (now wrong) `prevUnits`
and deletes the wrong number of characters from the REAL (now longer)
screen. For `tasks`, commit reverts to raw (`ták`'s coda `k` isn't legal)
and the arithmetic that should turn `ták` into `tasks ` instead turns the
real `táks` into `táasks ` — the same shape as every symptom above.

**This is the general case of "Do NOT let plain keystrokes bypass the
synthetic channel"** (see "Duplicate key-down" above): that entry already
proved unconditional suppression is required because cross-callback
ordering isn't guaranteed — a passed-through letter can overtake Backspaces
a previous callback posted. The `noop` short-circuit was a second, narrower
way to violate the same rule, reachable even though nobody was trying to
"optimize" passthrough this time — it fell out of treating an edit's
emptiness as a proxy for the engine's ownership, which isn't the same
question.

**Symmetric bug on Backspace.** `.backspace` had the identical flaw: with a
composing word already containing an absorbed, invisible key (as above), a
Backspace deleting exactly that key is also a no-op edit — the engine has
nothing to render differently — but under the old logic that meant
UNSUPPRESSED, so the physical Delete key reached the app and deleted a real,
VISIBLE character the engine never intended to touch.

**Why the tests never caught it.** `EngineControllerTests`' `typeAndFlush`
(and the same pattern duplicated in `LexiconRestoreTests` and
`LexiconRealDictionaryTests`) reconstructed the on-screen text purely by
replaying `EngineController`'s returned edits, in call order — it never
modeled the physical key that reaches the app when `suppress` is `false`.
So a test harness driving the exact code path that leaks a character was
structurally blind to that leak: it only ever saw the edits, never the extra
character the OS delivered on the side. The real tap
(`EventTapController.handle`) applies both, in order — inject the edit, THEN
let the original event through if unsuppressed — which is exactly what let
this bug ship invisibly under a passing test suite.

**Fix.**
- **Test harness first** (`Tests/KeystoneInputTests/RealisticTyping.swift`,
  new, shared by the three files above): `applyRealistically` applies an
  edit and then, only if `suppress` is `false`, the physical key itself —
  appending a `.character`'s letter, or removing one character for an
  unsuppressed `.backspace`. `commitPassthrough`/`commitNewline`
  (Return/Tab/arrows) still contribute nothing to the simulated screen: the
  physical key there is a navigation/newline key with no text content these
  string-comparison tests represent (Return's own `"\r"` is deliberately not
  appended). `typeInactive` (English-mode macros, Vietnamese off) already
  modeled physical passthrough correctly and was left alone.
- **`EngineController.handle`, ACTIVE branch** (`Sources/KeystoneInput/
  EngineController.swift`): `.character` now suppresses UNCONDITIONALLY —
  reading `process(.character)`'s call sites in `Engine.process` shows the
  engine always takes ownership of a character while active, either
  appending it to `rawKeys` (rendering visibly or not) or handing it back
  embedded in a real edit (empty buffer, or a commit boundary always
  appends the boundary char to the edit's text) — there is no active
  `.character` path where the engine leaves a key for the app to handle on
  its own. `.backspace` suppresses iff the engine was already composing a
  word (`Engine.isComposing`, checked BEFORE calling `process`, since
  `process` itself mutates `rawKeys`): an empty buffer means Backspace was
  never the engine's to take, so it stays a normal passthrough Delete;
  a non-empty buffer means the engine owns this Backspace regardless of
  whether the re-render is visible.
- **`Engine.isComposing`** (`Sources/KeystoneEngine/Engine.swift`): a tiny
  `public var isComposing: Bool { !rawKeys.isEmpty }` — read-only, no I/O,
  keeps `Engine` pure. The one new surface `EngineController` needed and
  didn't already have.

**Verified no other state leaves `rawKeys` non-empty while expecting a
physical key.** Read the whole of `Engine.swift` (`process`, `rerender`,
`finalize`, `flush`/`flushNewline`, macro handling, VNI digits via
`isWordChar`) looking for a path where the engine takes a character but
still wants the physical key delivered by the app — none exists; every
active `.character` outcome above is accounted for. `.backspace` on empty
`rawKeys` (`return .none` in `Engine.process`) is the one legitimate
passthrough case, and it's exactly what `isComposing` gates on.

**Test count.** 129 → 134 `@Test` declarations in `KeystoneInputTests`
(the harness refactor changed no test's identity, only its body); the 5 new
declarations cover 249 additional individual cases: the four bug-report
words with and without a lexicon, a Backspace-on-absorbed-key regression
(`servers`/`corners`/`borders`/`workers`, each with the trailing letter
dropped), 114 Telex→Vietnamese pairs pulled from the engine's own JSON
corpus and re-verified end-to-end through `EngineController`, and 123 plain
English words (including plurals shaped like the bug report: `masks`,
`risks`, `crashes`, `baskets`, ...) that must commit unchanged with no
lexicon installed. All were RED against the fixed harness and the
pre-fix `EngineController`; all are GREEN after the fix, alongside the full
pre-existing suite (`KeystoneEngineTests`: 132/132 unaffected — this bug
lives entirely in `EngineController`, not `Engine`).

## OpenKey-compatible literal-after-cancel (Phase 6)

The author types English inside Vietnamese Telex mode with the OpenKey
habit: press the tone/mark key twice to cancel it, then keep typing — and
expects what's on screen to be the literal result, e.g. `classs` (the
natural double `s` of "class", plus one more `s` pressed on purpose once the
toggle is seen) → `class`. Keystone instead re-derives the whole word from
`rawKeys` on every keystroke (`Telex.fold`/`VNI.fold`, see `Engine.swift`'s
header), so a THIRD press of the same key was, before this feature, treated
exactly like a first press: it re-applied the tone/mark instead of staying
literal (`classs` composed to `clás`, not `class`), and — because a tone
mark makes the composed word non-ASCII — the existing lexicon-restore
(`Lexicon.swift`, see "Restore chooses the composed word when it is the real
one" above) couldn't rescue it either, so the raw keystrokes (`classs`, one
letter too many) won.

**Reference: OpenKey's `tempDisableKey`**
(`/Users/tanta/Downloads/OpenKey/Sources/OpenKey/engine/Engine.cpp`).
OpenKey sets a single `static bool tempDisableKey` to `true` inside every
mark/tone double-strike-undo branch — `insertMark` (~line 789, tone/quality
marks), `insertD` (~line 819, đ-stroke), `insertAOE` (~line 854, circumflex/
breve keys typed as their own vowel letters) and `insertW` (~lines 896, 922,
966, the `w`/`[`/`]` horn family) — and clears it only at the next
`startNewSession()` (a word boundary). The dispatcher then reads it
unconditionally: `if (!IS_SPECIALKEY(data) || tempDisableKey) { ... insert
data as a plain key ... }` (~line 1486) — once the flag is set, EVERY later
key of the word, special or not, is inserted as a literal character instead
of running through `handleMainKey`'s Vietnamese transforms.

**Keystone's `cancelled` local mirrors this exactly, without any new mutable
state.** Every double-strike "undo" branch in `Telex.fold`/`VNI.fold`
already returns the private `Effect.literal` case — and, checked directly
against both files, `.literal` is returned from NO other branch. So
`.literal` already *is* "a cancel just fired" with no new bookkeeping
needed: `fold`'s loop keeps a plain local `var cancelled = false`, flips it
to `true` the first time `apply(...)` returns `.literal` (only when
`literalAfterCancel` is on), and from then on skips `apply` entirely for the
rest of that `fold` call — each later key is appended verbatim via
`SyllableOps.literalCell` (a vowel letter → a plain unmarked vowel cell,
anything else → a plain consonant-slot cell holding that character), the
same shape every existing "literal" branch already builds by hand. Because
`cancelled` is local to one `fold` call and `fold` always re-derives the
whole word from `rawKeys` from scratch (never incrementally), backspacing
past the cancelling keystroke drops `literalAfterCancel` back to inert with
no special-case code — `LiteralAfterCancelBackspacePastCancelResetsTests`
pins this. `z` (tone-clear) is deliberately NOT a cancel trigger: it clears
the tone outright without doubling a letter to undo anything (see "`z` key
semantics" above; OpenKey's own `removeMark()`, the `z` handler, never
touches `tempDisableKey` either), so typing `z` never enters literal mode.

**How it composes with the lexicon restore.** `literalAfterCancel` only
changes what gets COMPOSED; `RestoreDecision` (see above) is unchanged and
still runs afterward. For a word like `classs`, the flag alone (even with
`restoreIfInvalid` off and no lexicon) already composes the right spelling
character-for-character, because every key after the cancel is now literal:
`class` — nothing left to restore. For a word like `tassk`, the flag makes
no difference at all, because the character after the cancel (`k`) was
never a Telex transform key to begin with; that case was already fixed by
`RestoreDecision` alone. The two features are independent and additive:
either can fix a given cancel-habit word depending on what follows the
cancel keystroke, and both stacked (the shipped app default) fix the whole
nine-row table from the design spec.

**Trade-off, accepted on purpose.** The OLD toggle behavior (no
`literalAfterCancel`) re-applies the tone/mark on every odd-numbered repeat
of the key, so four presses of a cancel key round-trip back to "off" with no
extra letter (`asss` s×4 composes to `ass`, tone ngang). With
`literalAfterCancel` on, only the SECOND press is a cancel; the third and
fourth are both literal, so four presses leave an extra letter behind
(`asss` s×4 composes to `asss`, one more `s` than the old toggle). This
matches OpenKey's own behavior (`tempDisableKey` stays latched until the
word boundary, it does not re-arm on a further double-strike), and is the
deliberate cost of "cancel means cancel, permanently, for this word" instead
of "cancel toggles."

**Dormant-at-engine / on-by-default-in-the-app, the same pattern as
`freeMarkAcrossCoda`.** `EngineConfig.literalAfterCancel` defaults `false` —
with it off, `Telex.fold`/`VNI.fold`'s `cancelled` local is never allowed to
suppress anything, so every existing corpus/toggle test is byte-identical
(pinned by `LiteralAfterCancelUnchangedBeforeTheCancelTests` and the
~60-word Vietnamese regression suite in `LiteralAfterCancelVietnameseUnchanged`).
`AppModel.literalAfterCancel` defaults **true** (Control Panel: "Huỷ dấu
xong thì gõ tiếp chữ thường (như OpenKey)", next to the lexicon-restore
toggle) and is pushed through `pushConfig()`/reset by `resetToDefaults()`
like every other mapped toggle.

**Natural-typing sweep.** A throwaway scratch executable (not part of the
repo) loaded the real system lexicon (`LexiconLoader.load()`) and typed
every lowercase-alphabetic word in `/usr/share/dict/words` (210,773 words
after filtering) straight through `Engine`, character by character, with
`restoreIfInvalid` + `freeMarkAcrossCoda` + the lexicon all on, comparing
`literalAfterCancel` off vs. on. Zero words differed. This is expected, not
a coincidence: the flag can only change anything once a cancel has already
fired, and a cancel only fires on a key that repeats the immediately
preceding tone/mark key past what the word's own natural spelling requires
— natural dictionary typing (one keystroke per letter, no deliberate extra
press) essentially never produces that shape. The rare real words containing
three consecutive Telex-special letters (`bossship`, `whenceeer`, …) still
commit identically either way, because the flag only ever changes the
COMPOSED intermediate shape, and both paths converge on the same final
lexicon-restore decision.

## Eager restore (spellCheck / Phase 7)

"Kiểm tra chính tả" shipped as dormant scaffolding (persisted, shown in the
Control Panel, but not wired to `EngineConfig`) since Phase 4. This phase
wires it to a new engine behavior: EAGER RESTORE. Typing an English word like
`docker` inside Vietnamese Telex mode used to "flash" pseudo-Vietnamese
(`d`, `do`, `doc`, `dock`, `dỏcke`) until Space, where the EXISTING
`restoreIfInvalid` (see "Restore-if-invalid: two layers" above) reverts it to
`docker` — correct at the boundary, but visually noisy while typing. `Engine`
already re-derives the whole word from `rawKeys` on every keystroke
(`rerender`, see this file's header), so nothing stops the SAME kind of
revert from firing earlier, character by character, once the outcome is
already certain — that's `spellCheck`/`EngineConfig.spellCheck`.

**Dead vs. merely invalid — the reason `isValid` couldn't be reused as-is.**
`Engine.isValid` (used by `finalize`'s restore-if-invalid) answers "is this
syllable legal RIGHT NOW" — and a huge fraction of real Vietnamese words are
*not* legal right now at every prefix. Typing `một` Telex-style
(`m-o-o-t-j`) passes through `mo`, `môt` (circumflex applied, but the stop
coda `t` has tone ngang — illegal per `Phonology.toneAllowed`) before the
final `j` supplies nặng and it becomes legal. Firing `restoreIfInvalid`'s
revert at the `môt` step would flash `moot` (raw keys) mid-word for a
completely normal, correctly-typed Vietnamese word — unacceptable. A manual
survey of the corpus and the tricky-word list found roughly one in eight
words (`môt`→một, `ngươ`→người, `tâp`→tập, and the ~20 more in
`EagerRestoreVietnameseUnaffectedTests`) pass through at least one
"currently invalid" intermediate state that later recovers. So eager restore
needs a STRICTER predicate than `isValid`: not "is this legal now" but "can
this EVER become legal again" — `Engine`'s new private
`isUnrecoverable(_:)`, sitting right next to `isValid`. Only a truly DEAD
composition — structurally incapable of becoming a legal syllable no matter
what is typed next — may trigger the early revert.

**A no-vowel composition is never dead — the guard before the four
conditions.** `isUnrecoverable` first returns `false` for any composition
with no vowel at all, mirroring `finalize`'s own restore branch (which is
also `&& compHasVowel`, see "Restore-if-invalid: two layers"). A vowel-less
composition is either a still-pending onset (`đ` from `dd` before its vowel)
or a DELIBERATE Telex double-strike literal (`ww`→`w`, `ddd`→`dd`) that the
engine keeps as composed — never a "dead English word." Without this guard,
eager restore would rewrite those escapes back to their raw keystrokes
(`dd`→`ddd`) mid-word. English consonant clusters (`vm`, `cl`, `st`) are
caught one keystroke later, at their first vowel, so coverage is unchanged.

**The four dead conditions** (see `Engine.isUnrecoverable`, reusing the
existing private `parse(_:)` plus two new `Phonology` prefix helpers,
`isOnsetPrefix`/`isCodaPrefix`, mirroring the existing `isNucleusPrefix`):

1. **A vowel typed after the coda region** (`p.trailingVowelAfterCoda`) — a
   syllable's shape is onset–nucleus–coda in that order; once a consonant
   coda has started, a LATER vowel cannot be un-typed into an earlier
   position. Unrepairable by construction.
2. **An onset that is neither legal nor the prefix of any legal onset**
   (`vm`, `cl`, `br`, `st`, …). Every legal onset and every prefix of one
   (`c`, `ch`, `t`, `th`, `tr`, …) is explicitly excluded — recoverable
   onsets keep composing.
3. **A coda that is neither legal nor the prefix of any legal coda** (`ck`,
   `g`, `d`, `s`, `x`, `b`, …). Vietnamese has exactly eight consonant codas
   (`c ch m n ng nh p t`); anything else, and anything that can't grow into
   one of them, is dead.
4. **An offglide-final nucleus already closed by a consonant coda** — nuclei
   like `ai`, `oi`, `ươi`, `iêu` end in a semivowel offglide and can never
   take a true consonant coda (`Phonology.isLegalRime`, the same rule that
   already protects `coins`/`ruins`/`rains` from restore-if-invalid). Once
   such a nucleus is closed by a coda consonant, more typing only lengthens
   that coda — never fixes it.

**Two conditions deliberately left OUT, on purpose:**

- **`toneAllowed`** (a stop coda `p/t/c/ch` without its required sắc/nặng
  tone — exactly the `một`/`môt` shape above) is NOT a dead condition: the
  tone key is the repair, and it always arrives eventually in normal typing.
  Excluding it is precisely what keeps `một`/`người`/`tập`-shaped words from
  false-triggering the corpus safety sweep below.
- **Nucleus legality** (`Phonology.isLegalNucleus`) is NOT a dead condition
  either: an intermediate plain nucleus like `uo` (before the second `o`
  arrives and folds `oo`→ô in `muốn`) is a completely normal recoverable
  mid-word shape, not a dead one. A "safe" version of this check (one that
  never false-positives on any real recoverable nucleus) would have to be so
  narrow it catches almost nothing not already caught by conditions 1-4 —
  not worth the added surface area for the risk of a false positive.

**Where it hooks in: `rerender`, not `finalize`.** `finalize`'s
restore-if-invalid only ever runs at the word boundary; `spellCheck`'s
eager version runs on every keystroke, in `Engine.rerender`:

```swift
let comp = interpret(rawKeys)
let table = outputTable(for: config.codeTable)
let newUnits: [UInt16]
if config.spellCheck && isUnrecoverable(comp) {
    newUnits = Engine.collapseDoubledW(rawKeys).flatMap { table.plain($0) }
} else {
    newUnits = encode(comp, table: table)
}
```

This renders the SAME way `finalize`'s revert-to-raw branch does — raw
`rawKeys`, `collapseDoubledW`'d, through `table.plain` — so there is no
visual jump between the eager mid-word restore and the eventual word-
boundary commit: once a word goes dead, it stays showing its raw keystrokes
verbatim for the rest of that word (backspacing past the dead keystroke
naturally un-restores it too, since `rerender` always re-folds the whole of
`rawKeys` from scratch — no separate state to unwind, same as
`literalAfterCancel`'s `cancelled` local).

**The safety guarantee, and how it's proven.** The hard requirement: with
`spellCheck` on, every REAL Vietnamese word renders byte-identical —
stepwise AND at the boundary — to `spellCheck` off. `EagerRestoreTests.swift`
proves this three ways, all with ZERO tolerated divergence (no allowlist):

1. A 69-word hardcoded list built around the 21 known tricky recoverable-
   intermediate shapes (`một`, `người`, `tập`, and friends): stepwise and
   final identical on vs. off.
2. `corpusVietnameseStepwiseIdenticalOnAndOff` — a by-construction sweep of
   every telex single-word case across the ENTIRE pinned corpus (`words`,
   `words2`, `diacritics`, `placement`, `positional`, `tones`, `quicktelex`)
   whose `expected` is an actual Vietnamese word (carries a non-ASCII
   scalar — `đ` or a toned/quality-marked vowel), each run in ITS OWN config
   with only `spellCheck` toggled: the full per-keystroke trace must match.
   Running each fixture in its own config is what keeps the `quickTelex`
   fixtures (`saccs`→`sách`, `ccaf`→`chà`, `ttoo`→`thô`) honest — with
   `quickTelex` on, their doubled consonant folds into a legal digraph coda,
   so they are never dead and never diverge.
3. `corpusFinalOutputIdenticalOnAndOff` — the universal invariant that pins
   why this feature is inherently safe at commit: `finalize` NEVER reads
   `spellCheck`, so the word-boundary output is identical on vs. off for
   EVERY fixture, Vietnamese or not (including the `ddd`→`dd` / `ass`→`as`
   double-strike escapes, whose ASCII-only `expected` excludes them from the
   stepwise gate above — eager restore may change how they LOOK mid-word, but
   never what commits).

**Dormant-at-engine / on-by-default-in-the-app**, the same pattern as
`literalAfterCancel`/`freeMarkAcrossCoda`: `EngineConfig.spellCheck` defaults
`false` so every existing test and the whole corpus stay byte-identical;
`AppModel.spellCheck` (already-persisted scaffolding, Control Panel "Kiểm
tra chính tả") defaults `true` and is now pushed through `pushConfig()`/
`resetToDefaults()` like every other mapped toggle.

## Force-English whitelist (Lớp B)

Eager restore and restore-if-invalid (both above) both handle the same class
of problem: an English word Telex-composes into something that ISN'T a legal
Vietnamese syllable, so it can safely revert to raw keystrokes — `docker`
composes to the dead `dỏcke`, `task` to the invalid `ták`. But a second,
disjoint class of English word exists that neither of those features can ever
touch: one whose Telex keystrokes compose a syllable that IS phonologically
legal Vietnamese. `test`→`tét`, `reset`→`rết`, `six`→`sĩ`, `box`→`bõ`,
`row`→`rơ` are all valid Vietnamese syllables, so `isValid` says yes,
`isUnrecoverable` says "never dead", and the word stays Vietnamese all the
way to commit — today, with no code change, that's actually correct: nothing
in the composed text signals it should have been English at all. The
keystrokes are, genuinely, ambiguous between "an English word" and "a
Vietnamese syllable" — that ambiguity is the entire problem this feature
solves, not something the previous two features overlooked.

**Why not just "prefer English when the composition also happens to be a
real English word"?** That was the obvious first design and it's wrong: the
same Telex shape that makes `test`/`reset`/`six` look like English also makes
extremely common Vietnamese words look like English. `car`→`cả`, `cow`→`cơ`,
`bee`→`bê`, `bus`→`bú` are everyday Vietnamese words the user types
constantly, and `car`/`cow`/`bee`/`bus` are all real English words too — a
blanket rule would silently break Vietnamese typing far more often than it
would fix English typing. There is no phonological, lexical, or statistical
signal inside the keystrokes themselves that reliably tells `test` (should
win as English) apart from `car` (should lose to Vietnamese) — both are
"real English word whose Telex composition is a valid Vietnamese syllable."
The only honest way to resolve the ambiguity is a human, per-word judgment
call about which reading is more likely in practice — hence a CURATED list,
not a rule.

**The tradeoff, stated plainly.** Every entry in
`SupplementaryWords.forceEnglishWords` is a deliberate decision to SHADOW a
Vietnamese homograph: typing `test`/`reset`/`row`/`box`/`six`/`refer`/`defer`
in actual Vietnamese prose (rare, but not impossible) will now render the
English word instead. This is only acceptable because each entry was chosen
for having English usage that vastly outweighs its Vietnamese collision in
realistic typing (a hosting/dev-heavy vocabulary, same audience as
`SupplementaryWords.all`) — this is not a knob to turn up casually. A
candidate word only belongs on the list if it's a genuine "Lớp B" collision
in the first place: something that ALREADY composes to a different, valid
Vietnamese syllable with `spellCheck`/`forceEnglish` both absent (a word that
already renders as itself needs no override; a word that reverts via
ordinary restore-if-invalid already loses to Vietnamese for a different
reason and doesn't need this mechanism either). `ForceEnglishListIntegrity`'s
`everyEntryIsAGenuineVietnameseHomographCollision` test enforces exactly
this, so the list can't silently accumulate dead weight.

**Mechanism: gated under `spellCheck`, decided in `finalize`, wins over
everything else.** Unlike eager restore (which hooks `rerender`, mid-word),
the force-English check runs once, at the word boundary, in
`Engine.finalize` — there is nothing to decide until the whole word is known,
since a prefix of `test` (e.g. `te`) isn't itself in the whitelist and isn't
dead either. It reuses `finalize`'s existing raw-word/composed-word/
`revertToRawUnits` machinery (hoisted to the top of the function so both this
branch and the pre-existing restore-if-invalid branch share one copy) and is
checked FIRST, before restore-if-invalid: `config.spellCheck` must be on,
`Engine.forceEnglish` (an optional `Lexicon`, set independently of
`EngineConfig` exactly like `Engine.lexicon` — see that property's own doc
comment for why: `EngineConfig` is `Codable` and rebuilt from scratch on
every unrelated settings change) must be installed and contain the raw typed
word, and the raw and composed spellings must actually differ (guards
against a no-op "win" when raw already equals composed). When all of that
holds, `finalize` commits the raw keystrokes exactly the way
restore-if-invalid's revert branch always has — same `collapseDoubledW`,
same auto-capitalize-preserving `revertToRawUnits`. A word not on the list is
completely untouched: it falls through to the existing restore-if-invalid
check and, since it composed a VALID syllable, on to the ordinary composed-
output path — byte-identical to before this feature existed.

**Independent of the lexicon-driven restore feature.** `RestoreDecision`
(the ~236k-word system dictionary used by restore-if-invalid, see "Restore
chooses the composed word when it is the real one") never even runs for
these words — their composition is valid, so `!isValid(comp)` is false and
that whole branch is skipped. `forceEnglish` is a separate, tiny (~7-word),
always-resident `Lexicon` (unlike the 236k-entry system dictionary, no
lazy/off-thread loading is warranted) installed via
`EngineController.setForceEnglish`, mirroring `setLexicon`'s pattern but
gated only by `spellCheck` (`AppModel.updateForceEnglishLoaded`, called from
`init()` and `spellCheck`'s `didSet`) rather than by two flags.

**Ship-dormant discipline maintained.** `Engine.forceEnglish` defaults `nil`
exactly like `Engine.lexicon`, so no existing test or corpus fixture is
affected until something installs it — proven by full-suite regression
(`LexiconRestoreTests`, `LiteralRestoreTests`, `LiteralAfterCancelTests`,
`EagerRestoreTests`, and the whole corpus suite are all unchanged).
## Deferred across-coda circumflex — tried, reverted

The across-coda circumflex (`freeMarkAcrossCoda`, e.g. `hopoj`→hộp, `tana`→tân,
`trene`→trên) is applied EAGERLY, per keystroke — like every other mark. This
means an English word with the same vowel–consonant–vowel shape flashes
pseudo-Vietnamese mid-word (`manager` shows mân→mâng before later keys make it
invalid and it reverts to raw; the final commit is still correct). OpenKey has
the identical flash (it shows `mânger`), because at the moment the second vowel
is typed `tan`+`a` and `man`+`a` are the same keystrokes.

We briefly DEFERRED this mark to the word boundary (a `committing` flag on
`Telex.fold`, true only in `finalize`) to kill that flash. It worked for English
— but it also delayed EVERY Vietnamese word typed in the "bỏ dấu ở cuối" style
(`hopoj`→hộp, `tana`→tân, `cana`→cân…) to the boundary, showing the literal
keystrokes until Space. The maintainer types Vietnamese in exactly that style
constantly, so the delay was far more disruptive than the occasional English
flash. Reverted: the across-coda circumflex is eager again. The flash is the
accepted cost of the feature (and matches OpenKey); `restoreIfInvalid`/eager
restore still land the correct final English word.
## The ddd→dd escape in raw-restore

`dd`→đ is the Telex đ transform, so to type two LITERAL `d`s you press three:
`ddd` (the third d undoes the đ and leaves "dd" — see `Telex.apply`'s d branch
and `literalAfterCancel`). This matters because a word that should start with a
literal "dd" has no other route: bare `ddos` is the extremely common Vietnamese
word `đó` (`dd`+`o`+`s`→sắc — identical keystrokes), so we can NOT force it to
English without breaking `đó` (same class as `six`↔`sĩ`, see "Force-English
whitelist"). The user types `dddos` to mean "ddos" (e.g. DDoS).

The bug: `finalize`'s revert-to-raw and `rerender`'s eager restore both render
the RAW keystrokes for the (invalid, onset "dd") composition, and the raw
"dddos" still has the escape d, so it showed "dddos" instead of "ddos". Fix:
`collapseDoubledLiterals` (renamed from `collapseDoubledW`) now collapses a run
of three d's to two — `ddd`→`dd` — exactly as it already collapses the horn
escape `ww`→`w`. A plain `dd` pair (English "add", "buddy") is a run of two,
untouched; a tone-key double ("boss") never involves d at all. So `dddos`→`ddos`,
`dddong`→`ddong`, while every existing restore is unchanged. Pinned by
`DStrokeEscapeTests.swift`. (`ddos` typed with two d's still composes to `đó` —
that homograph is inherent and unchanged.)
