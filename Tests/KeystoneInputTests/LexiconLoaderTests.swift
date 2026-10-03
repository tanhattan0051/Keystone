// LexiconLoaderTests.swift — TDD suite for `LexiconLoader`, which reads the
// system word list (normally /usr/share/dict/words) and merges the
// hardcoded `SupplementaryWords` list of modern English words the system
// list lacks (google, email, website, ...). Never throws or crashes: a
// missing/unreadable file just falls back to the supplement alone.

import Testing
import Foundation
@testable import KeystoneInput

@Suite("LexiconLoader")
struct LexiconLoaderTests {
    @Test func loadsTempFileAndMergesSupplement() throws {
        let dir = FileManager.default.temporaryDirectory
        let path = dir.appendingPathComponent("lexicon-loader-test-\(UUID().uuidString).txt")
        try "apple\nbanana\nCherry\n".write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }

        let lexicon = LexiconLoader.load(systemWordsPath: path.path)

        #expect(lexicon.contains("apple"))
        #expect(lexicon.contains("banana"))
        #expect(lexicon.contains("cherry"))
        // Supplement words are merged in alongside the file's own words.
        #expect(lexicon.contains("google"))
        #expect(lexicon.contains("email"))
    }

    @Test func missingPathReturnsSupplementAloneWithoutCrashing() {
        let missing = "/nonexistent/path/\(UUID().uuidString)/words.txt"
        let lexicon = LexiconLoader.load(systemWordsPath: missing)

        // No system words, but both supplement lists are still present.
        #expect(lexicon.contains("google"))
        #expect(lexicon.contains("website"))
        #expect(lexicon.contains("fussed"))
        let expectedCount = Set(SupplementaryWords.all + SupplementaryWords.protectedRealWords).count
        #expect(lexicon.count == expectedCount)
    }

    // MARK: - Prefix index
    //
    // The English-likeness choice after a Telex cancel (see DECISIONS.md
    // "Cancel keeps the literal") reads `Lexicon.isPrefix`/`prefixDepth`, which
    // answer `false`/`0` until `buildPrefixIndex()` ran. The loader is the one
    // place that sorts the ~236k words (off the tap thread), so a load that
    // forgot to build would silently turn the whole feature off: pin it.

    @Test func loadedLexiconHasItsPrefixIndexBuilt() throws {
        let dir = FileManager.default.temporaryDirectory
        let path = dir.appendingPathComponent("lexicon-loader-prefix-\(UUID().uuidString).txt")
        try "unsuspected\nsuspense\n".write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }

        let lexicon = LexiconLoader.load(systemWordsPath: path.path)

        #expect(lexicon.isPrefixIndexBuilt)
        #expect(lexicon.isPrefix("suspen"))
        #expect(lexicon.prefixDepth("unsuspend") == 7)
        // Supplement words are indexed too, not only the file's own.
        #expect(lexicon.isPrefix("goog"))
    }

    @Test func missingPathStillBuildsThePrefixIndexFromTheSupplement() {
        let missing = "/nonexistent/path/\(UUID().uuidString)/words.txt"
        let lexicon = LexiconLoader.load(systemWordsPath: missing)

        #expect(lexicon.isPrefixIndexBuilt)
        #expect(lexicon.isPrefix("goog"))
    }

    @Test func supplementaryWordsAreAllLowercaseAndNonEmpty() {
        for w in SupplementaryWords.all {
            #expect(w == w.lowercased(), "\(w) must be lowercase")
            #expect(!w.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test func supplementaryWordsHasNoDuplicates() {
        let words = SupplementaryWords.all
        #expect(Set(words).count == words.count)
    }

    @Test func supplementaryWordsCoversAFewHundredEntries() {
        #expect(SupplementaryWords.all.count >= 150)
    }

    // MARK: - protectedRealWords (raw-side protection, item 2)
    //
    // An exhaustive offline search against /usr/share/dict/words (1934
    // Webster) found real English words the list lacks — inflections,
    // loanwords, acronyms, surnames — whose COMPOSED (collapsed-double-letter)
    // form happens to be a different real word already in the system list.
    // Without these, RestoreDecision.choose would rewrite the user's actual
    // typing into that other, unintended word. Adding them here makes `raw`
    // recognized too, so `RestoreDecision.choose`'s `!lexicon.contains(raw)`
    // guard keeps `.raw` winning, exactly like HEAD (pre-lexicon).

    private static let falsePositiveWords: [String] = [
        "fussed", "mussed", "mussing", "jarred", "purred", "parring", "riffling",
        "coiffed", "squirreling", "moussing", "suss", "terra", "torr", "iff", "barre",
        "lassi", "frisson", "farro", "barrie", "currie", "buffo", "triffid",
        "transsonic", "hassidic", "hassidim", "chassidim", "mycorrhiza", "degass",
        "unbiassed", "aaa", "iss", "poisson", "cassava", "cassaba", "hassan",
        "parramatta", "oss", "herr", "kerr", "orr", "starr", "barr", "neff", "foxx", "maxx",
    ]

    @Test func protectedRealWordsCoversTheFullFalsePositiveList() {
        for w in Self.falsePositiveWords {
            #expect(SupplementaryWords.protectedRealWords.contains(w), "\(w) missing from protectedRealWords")
        }
    }

    @Test func protectedRealWordsAreLowercaseAndDeduplicated() {
        let words = SupplementaryWords.protectedRealWords
        #expect(Set(words).count == words.count)
        for w in words {
            #expect(w == w.lowercased(), "\(w) must be lowercase")
        }
    }

    @Test func protectedRealWordsAreDisjointFromTheModernWordSupplement() {
        // Two separate, separately-commented lists — never the same entry
        // twice across both.
        #expect(Set(SupplementaryWords.all).isDisjoint(with: Set(SupplementaryWords.protectedRealWords)))
    }

    @Test func loaderMergesProtectedRealWordsAlongsideTheModernSupplement() {
        let missing = "/nonexistent/path/\(UUID().uuidString)/words.txt"
        let lexicon = LexiconLoader.load(systemWordsPath: missing)
        #expect(lexicon.contains("fussed"))
        #expect(lexicon.contains("jarred"))
        #expect(lexicon.contains("herr"))
    }

    // MARK: - Coverage extension (item 3)

    @Test func vietnixIsInTheSupplementAndIsFirst() {
        #expect(SupplementaryWords.all.first == "vietnix")
    }

    @Test func coversVietnamMarketBrands() {
        for w in ["viettel", "vnpt", "fpt", "mobifone", "vinaphone", "matbao", "pavietnam",
                  "nhanhoa", "tenten", "vinahost", "azdigi", "bizfly", "zalopay", "momo",
                  "shopee", "lazada", "tiki"] {
            #expect(SupplementaryWords.all.contains(w), "\(w) missing")
        }
    }

    @Test func coversSysadminDevTokensWithVowels() {
        for w in ["systemctl", "openssl", "stderr", "stdout", "sudoers", "iptables", "xargs",
                  "dmarc", "exim", "iframe", "nodejs", "haproxy", "firebase", "pytest", "eslint",
                  "websocket", "vhost", "laravel", "jquery", "flexbox"] {
            #expect(SupplementaryWords.all.contains(w), "\(w) missing")
        }
    }

    @Test func coversInflectionsOfTheSupplementsOwnWords() {
        for w in ["emails", "websites", "domains", "servers", "backups", "uploads",
                  "downloads", "logins", "deployed", "deploying"] {
            #expect(SupplementaryWords.all.contains(w), "\(w) missing")
        }
    }

    @Test func coversCommonWebsterMissingInflections() {
        for w in ["tasks", "passed", "errors", "fixes", "offsets", "hashes", "processes",
                  "processed", "files", "users"] {
            #expect(SupplementaryWords.all.contains(w), "\(w) missing")
        }
    }

    @Test func inertNoVowelAndValidVietnameseEntriesWereRemoved() {
        // Restore only ever fires on a composition WITH a vowel cell
        // (Engine.finalize's `compHasVowel` guard), so a word with none can
        // never actually reach RestoreDecision — dead weight. And a few
        // entries happen to type as a VALID Vietnamese syllable already (no
        // diacritic needed), so `restoreIfInvalid`'s `!isValid(comp)` guard
        // never lets them reach RestoreDecision either. Both kinds were
        // removed rather than kept-but-inert.
        let removed = [
            "http", "https", "dns", "ssl", "tls", "vpn", "cdn", "html", "css", "npm",
            "xml", "ssh", "ftp", "sftp", "sql", "mvc", "jwt", "xss", "whm", "vps", "wfh",
            "cors", "meme", "memes", "orm", "paas", "saas",
        ]
        for w in removed {
            #expect(!SupplementaryWords.all.contains(w), "\(w) should have been removed as inert")
        }
    }
}
