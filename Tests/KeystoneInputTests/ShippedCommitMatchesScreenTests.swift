// ShippedCommitMatchesScreenTests.swift — through the shipped config, what Space
// commits must not differ from what the screen showed for a cancelled word whose
// display came from the cancel rule, and a run of three w's must survive.

import Testing
@testable import KeystoneEngine

private let vniShipped: EngineConfig = {
    var c = shippedConfig
    c.inputMethod = .vni
    return c
}()

@Suite("WwwAndVniCollapse", .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct WwwAndVniCollapseTests {
    @Test func threeWsStayThree() {
        #expect(typeShipped("www") == "www ")
        #expect(screenWhileTyping("www") == "www")
    }
    @Test func twoWsShowOneMidWord() {
        #expect(screenWhileTyping("ww") == "w")
    }
    @Test func exactlyTwoStillCollapse() {
        #expect(typeShipped("wwin") == "win ")
        #expect(typeShipped("swwim") == "swim ")
        #expect(typeShipped("dddos") == "ddos ")
    }
    @Test func vniKeepsEveryLetter() {
        #expect(typeShipped("dddos", config: vniShipped) == "dddos ")
        #expect(typeShipped("swwim", config: vniShipped) == "swwim ")
    }
}

@Suite("ShippedCommitMatchesScreen", .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct ShippedCommitMatchesScreenTests {
    @Test func songssCommitsWhatTheScreenShowed() {
        #expect(screenWhileTyping("songss") == "songs")
        #expect(typeShipped("songss") == "songs ")
    }
    @Test(arguments: [
        ("tassk", "task "), ("gooogle", "google "), ("unssuspend", "unsuspend "),
        // One cancel (`classs`) keeps the word; a second repeat (`classss`) is a natural
        // typo-run that main already commits as typed, screen and commit agreeing.
        ("classs", "class "), ("passs", "pass "),
        ("classss", "classss "), ("passss", "passss "),
        ("missed", "missed "), ("messages", "messages "), ("issues", "issues "),
        ("passwords", "passwords "), ("process", "process "),
    ])
    func unchangedGuards(keys: String, expected: String) {
        #expect(typeShipped(keys) == expected)
    }
}
