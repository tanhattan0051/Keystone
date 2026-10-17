// EagerRestoreAgreesWithCommitTests.swift — what the screen shows WHILE a word is
// typed must be what Space commits. With spellCheck on and restoreIfInvalid off,
// the mid-word eager restore used to show the raw "docker" while finalize (which
// only restores when restoreIfInvalid) committed "dỏcke". The eager display and
// the cancel-display rule now require restoreIfInvalid too.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("Eager restore agrees with commit",
       .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct EagerRestoreAgreesWithCommitTests {
    // "test" is not here: its Vietnamese reading "tét" is valid, so the screen shows
    // it until Space and the force-English whitelist then commits "test" (the known
    // valid-compose case, same in every config); see `validComposeIsConfigIndependent`.
    static let words = ["docker", "songss", "tassk"]

    private var noRestore: EngineConfig {
        var config = shippedConfig
        config.restoreIfInvalid = false
        return config
    }

    @Test(arguments: EagerRestoreAgreesWithCommitTests.words)
    func spellCheckWithoutRestoreShowsWhatItCommits(_ word: String) {
        let config = noRestore
        let shown = screenWhileTyping(word, config: config)
        let committed = typeShipped(word, config: config)
        #expect(committed == shown + " ", "word=\(word) shown=\(shown) committed=\(committed)")
    }

    @Test(arguments: EagerRestoreAgreesWithCommitTests.words)
    func shippedConfigShowsWhatItCommits(_ word: String) {
        let shown = screenWhileTyping(word)
        let committed = typeShipped(word)
        #expect(committed == shown + " ", "word=\(word) shown=\(shown) committed=\(committed)")
    }

    @Test func dockerWithoutRestoreStaysComposedEverywhere() {
        let config = noRestore
        #expect(screenWhileTyping("docker", config: config) == typeShipped("docker", config: config).dropLast())
    }

    @Test func shippedConfigStillRestoresEagerly() {
        #expect(screenWhileTyping("docker") == "docker")
        #expect(typeShipped("docker") == "docker ")
    }

    @Test func validComposeIsConfigIndependent() {
        let config = noRestore
        #expect(screenWhileTyping("test", config: config) == screenWhileTyping("test"))
        #expect(typeShipped("test", config: config) == typeShipped("test"))
    }
}
