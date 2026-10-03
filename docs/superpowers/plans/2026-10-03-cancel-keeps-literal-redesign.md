# Cancel keeps the literal — redesign (English-likeness by dictionary prefixes)

Approved direction: Tân Tạ, 2026-10-02/03. He reported `unssuspend` / `unsspend` / `susspend` again on
the installed 1.1.6 and asked for the fix. The first attempt (plan 2026-10-02, Task 1) was reverted.

## Why the first attempt failed, and what this one changes

**The bug.** Tân types English inside Vietnamese Telex with OpenKey habits. He sees a tone appear
(`u n s` → `ún`) and presses the key again to cancel it. Keystone then shows and commits the RAW keys,
cancel key included: `unss…` → `unssuspend`.

**First attempt (reverted).** After a cancel, it kept the cancelled composition unless the raw spelling
was itself a dictionary word. That broke correctly typed English the 1934-Webster lexicon lacks
(messages→mesages, processing→procesing, diff→dif): about 1 word in 160 of real prose.

**This design.** The lexicon decides which spelling is more ENGLISH-LIKE, using dictionary PREFIXES.
"Depth" means how far the spelling stays a prefix of some lexicon word. The cancelled form wins only
when it is a word, or when it stays English-like for at least 2 more letters than the raw spelling.
A throwaway prototype was measured on 159,287 words of real English (22 man pages + repo docs, 6,977
distinct words) and gave:

| | main d0d3837 | prototype (margin 2) |
|---|---|---|
| natural typing, final output correct | 87.60% | 87.60% (0 words newly wrong) |
| natural typing, on-screen before the space correct | 83.33% | 83.32% (6 rare words: troff, missed, presses…) |
| OpenKey habit*, final correct | 87.13% | 89.39% (0 newly wrong, 408 newly right) |
| OpenKey habit*, on-screen before the space correct | 71.10% | 87.51% |

\* Habit simulation: after each intended letter, if the screen shows a Vietnamese mark the writer did
not intend, press the same key once more.

Margin 1 broke 9 words (lesskey, onerror, nonbootable). Adding -s/-ed/-es stem rules broke the habit
case (`thiss` → this+s). Both were rejected.

## Global Constraints

- Swift 6 package at the repo root. Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`,
  `#expect`) only. Full suite: `swift test --skip Scratch` from the repo root. Every existing test
  must pass. 2 known issues (room/door) are expected.
- TDD is mandatory: write the new tests first, run them and see them fail for the right reason, then
  implement.
- Business logic goes in PURE code: the decision and the prefix queries live in
  `Sources/KeystoneEngine/Lexicon.swift`, and the engine only calls them.
- Match the surrounding style. Doc comments explain WHY. Add no new dependencies.
- Change only what this plan asks.
- **No work on the CGEventTap thread may block.** Sorting the ~236k-word lexicon happens ONLY where it
  is loaded today: `LexiconLoader.load`, which already runs off the main and tap threads. Never sort
  in `Engine` or `EngineController.setLexicon`, which runs under the per-keystroke lock.
- Per-keystroke cost after a cancel must stay small: binary searches over the sorted words, with no
  per-call allocation of the whole lexicon.
- A missing or unbuilt prefix index must NEVER make the engine prefer the composed form. It falls back
  to main's behavior, and must not fail silently in a way that hides a load bug: LexiconLoader always
  builds it, and a test pins that.
- Docs: add a `DECISIONS.md` section (cite the numbers above and the two rejected variants) and extend
  the README "Huỷ dấu xong thì gõ tiếp chữ thường (kiểu OpenKey)" bullet in Vietnamese, wrapped at
  ~100 columns.
- Commits on branch `claude/cancel-redesign`. Every commit message ends with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Never push, merge, or touch `/Applications/Keystone.app`.

## Task 1: English-likeness choice after a Telex cancel

**Files**
- `Sources/KeystoneEngine/Telex.swift`
  - Add `var cancelled: Bool = false` to `struct Composition`, with a doc comment: "a same-key
    double-strike cancel fired in this word (only ever true when `literalAfterCancel` is on)".
  - `Telex.fold` returns it from its existing `cancelled` local.
  - `VNI.fold` (`VNI.swift`) also returns it, for honesty. The engine gates VNI out (see below).
- `Sources/KeystoneEngine/Lexicon.swift`
  - Add a lowercase sorted-word prefix index to `Lexicon`:
    - built by `init<S: Sequence>` and `parse`
    - built by a new `public mutating func buildPrefixIndex()` that `LexiconLoader.load` calls once
      after its inserts
    - marked stale by `insert`
  - `public func isPrefix(_ p: String) -> Bool`: true iff some word starts with the lowercased `p`.
    Use a lower-bound binary search.
  - `public func prefixDepth(_ s: String) -> Int`: the largest k such that the first k characters of
    lowercased `s` pass `isPrefix`. 0 for "".
  - Both return `false` / `0` on a stale or unbuilt index, so the engine falls back to main.
  - Add `public static func chooseAfterCancel(composed: String, raws: [String], lexicon: Lexicon,
    atCommit: Bool) -> RestoreChoice` to `RestoreDecision`. All strings are compared lowercased.
    - `atCommit == true`:
      1. Any raw is in the lexicon → `.raw`
      2. `composed` is in the lexicon → `.composed`
      3. `prefixDepth(composed) >= max(prefixDepth(raw)) + englishLikenessMargin` → `.composed`
      4. Otherwise → `.raw`
    - `atCommit == false` (mid-word display):
      1. Any raw `isPrefix` → `.raw`
      2. `composed` `isPrefix` → `.composed`
      3. The same margin rule → `.composed`
      4. Otherwise → `.raw`
    - `static let englishLikenessMargin = 2`, with a WHY doc comment carrying the measurements above.
- `Sources/KeystoneInput/LexiconLoader.swift`: call `lexicon.buildPrefixIndex()` after the
  supplementary inserts.
- `Sources/KeystoneEngine/Engine.swift`
  - Add a private helper `cancelledLiteralApplies(_ comp: Composition) -> Bool`. It is true iff ALL of:
    - `config.literalAfterCancel`
    - `config.inputMethod != .vni` (in VNI the cancel key is a digit, and `win11` / `ubuntu22.04` must
      survive)
    - `lexicon != nil`
    - `comp.cancelled`
    - `comp.tone == .ngang`
    - every vowel cell has `mark == .none`
  - Candidates:
    - composed = the composition rendered through the `.unicode` output table
    - raws = `[String(Engine.collapseDoubledLiterals(rawKeys)), String(rawKeys)]`
  - `rerender()`: in the eager-restore branch (`config.spellCheck && isUnrecoverable(comp)`), if
    `cancelledLiteralApplies(comp)` and `chooseAfterCancel(..., atCommit: false) == .composed`, render
    `encode(comp, table:)` instead of the raw keys. Everything else is unchanged.
  - `finalize(boundary:)`: inside the existing restore branch, check first: if
    `cancelledLiteralApplies(comp)`, choose with `atCommit: true` between
    `encode(capitalized(comp, if: shouldCapitalize), table: table)` and `revertToRawUnits()`.
    Otherwise use the existing `RestoreDecision.choose` path, unchanged. The force-English branch
    before it stays first and unchanged.
- Tests, written FIRST:
  - New `Tests/KeystoneEngineTests/CancelKeepsLiteralTests.swift`, with engine-level stepwise and final
    traces. Copy the helper pattern from `EagerRestoreTests.swift`. Use a small hand-built `Lexicon`
    per test and comment which words make each depth work.
  - Pure `Lexicon` prefix tests and `chooseAfterCancel` tests, including the exact margin boundary
    (depth difference 1 → raw, 2 → composed).
  - A `KeystoneInputTests` test that `LexiconLoader.load()` returns a lexicon whose prefix index is
    built (e.g. `isPrefix("suspen")` is true).

**Required behavior.** Telex. Config `on` = `EngineConfig(inputMethod: .telex, restoreIfInvalid: true,
allowFreeToneMark: true, freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)`. The
hand-built lexicons below are minimal suggestions; adjust them only to make the stated depths hold,
and say so in a comment.

| # | Keys | Lexicon contains (at least) | Expected |
|---|------|-----------------------------|----------|
| 1 | `unssuspend ` | `unsuspected` | `"unsuspend "` (composed depth 7 ≥ raw depth 3 + 2) |
| 2 | `unssuspend` stepwise | `unsuspected` | no entry contains `"unss"`; the 4th entry is `"uns"` |
| 3 | `unsspend ` | `unspent`, `unspeakable` | `"unspend "` |
| 4 | `susspend ` | `suspend` | `"suspend "` |
| 5 | `tassk ` | `task` | `"task "` |
| 6 | `classs ` and `class ` | `class`, `clasp` | both `"class "` |
| 7 | `messsage ` and `message ` | `message` | both `"message "` |
| 8 | `messages ` (natural, not in the lexicon) | `message` | `"messages "` (raw depth 7 vs composed 3) |
| 9 | `processing ` and `diff ` (natural) | `process`, `procession`, `difference` | unchanged: `"processing "`, `"diff "` |
| 10 | `onerror ` (natural; margin-1 regression) | `onerous`, `error` | `"onerror "` |
| 11 | VNI `a11 `, `win11 ` | any | unchanged from main |
| 12 | `unssuspend ` with literalAfterCancel off, or lexicon nil, or prefix index unbuilt | — | unchanged from main |
| 13 | `vieetss ` (the cancel leaves a circumflex) | any | unchanged from main |
| 14 | `unssuspend ` with `autoCapitalize: true` on a fresh engine | `unsuspected` | `"Unsuspend "` |

For rows 11–13, pin the exact strings from main: run the tests before changing `Engine.swift`.

**Acceptance measurements.** Run all three before reporting, and put the numbers in the report.
- **Corpus harness.** The tools are in this plan's SDD workspace:
  - `Harness.swift`: copy it to `Tests/KeystoneInputTests/ScratchCorpus.swift` temporarily
  - `corpus-tokens.txt`, `compare.py`, `res-base.tsv` (main's results)

  Run `CORPUS=<ws>/corpus-tokens.txt OUT=<ws>/res-new.tsv swift test --filter ScratchCorpus`, then
  `python3 <ws>/compare.py <ws> res-base.tsv res-new.tsv`. Required:
  - natural final: **0 newly wrong**
  - habit final: **0 newly wrong** and an accuracy ≥ 89%
  - report the mid-word lines too

  Delete `ScratchCorpus.swift` before committing; it must never be committed.
- **Dictionary sweep.** Type every all-lowercase-ASCII word of `/usr/share/dict/words` plus a space,
  with config `on`, the real `LexiconLoader.load()` lexicon and `SupplementaryWords.forceEnglishWords`
  as forceEnglish. Compare the final output against main, built from a `git archive d0d3837` copy
  outside the repo. Required: 0 differences. The sweep test is throwaway and not committed.
- **Full suite.** `swift test --skip Scratch` must be green.
