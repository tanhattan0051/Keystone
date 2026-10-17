// CodeUnitEditsUnchangedTests.swift — pins that the per-keystroke edits of the
// tables WITHOUT combining marks (.unicode and the 8-bit legacy tables) are
// byte-identical to the code-unit diff they had before the grapheme-aware diff
// was added for combining-mark output (see DECISIONS.md "Engine edit hardening:
// multi-character uppercase, grapheme edits, eager restore needs restore").
//
// The expected strings were recorded on the base commit d1e96ec: one
// "backspaceCount:scalars.in.hex" entry per keystroke, then one for the Space
// that commits the word, with a default EngineConfig (Telex, no spellCheck) and
// only the code table changed. CP1258 is deliberately not pinned here: it is
// being changed to decode to real combining marks, so it follows the grapheme
// rule by design.

import Testing
@testable import KeystoneEngine

@Suite("Code-unit edits unchanged") struct CodeUnitEditsUnchangedTests {
    static let recorded: [(table: String, keys: String, edits: String)] = [
        ("unicode", "vieejt", "0:76 0:69 0:65 1:ea 1:1ec7 0:74 0:20"),
        ("unicode", "tosf", "0:74 0:6f 1:f3 1:f2 0:20"),
        ("unicode", "tasks", "0:74 0:61 1:e1 0:6b 0: 2:61.73.6b.73.20"),
        ("unicode", "nguyeexn", "0:6e 0:67 0:75 0:79 0:65 1:ea 1:1ec5 0:6e 0:20"),
        ("unicode", "dduwowcj", "0:64 1:111 0:75 1:1b0 0:6f 1:1a1 0:63 2:1ee3.63 0:20"),
        ("unicode", "hoaf", "0:68 0:6f 0:61 2:f2.61 0:20"),
        ("unicode", "tieengs", "0:74 0:69 0:65 1:ea 0:6e 0:67 3:1ebf.6e.67 0:20"),
        ("unicode", "ruwowjuj", "0:72 0:75 1:1b0 0:6f 1:1a1 1:1ee3 0:75 0: 0:20"),
        ("unicode", "docker", "0:64 0:6f 0:63 0:6b 0:65 4:1ecf.63.6b.65 4:6f.63.6b.65.72.20"),
        ("unicode", "Vieejt", "0:56 0:69 0:65 1:ea 1:1ec7 0:74 0:20"),
        ("tcvn3", "vieejt", "0:76 0:69 0:65 1:aa 1:d6 0:74 0:20"),
        ("tcvn3", "tosf", "0:74 0:6f 1:e3 1:df 0:20"),
        ("tcvn3", "tasks", "0:74 0:61 1:b8 0:6b 0: 2:61.73.6b.73.20"),
        ("tcvn3", "nguyeexn", "0:6e 0:67 0:75 0:79 0:65 1:aa 1:d4 0:6e 0:20"),
        ("tcvn3", "dduwowcj", "0:64 1:ae 0:75 1:ad 0:6f 1:ac 0:63 2:ee.63 0:20"),
        ("tcvn3", "hoaf", "0:68 0:6f 0:61 2:df.61 0:20"),
        ("tcvn3", "tieengs", "0:74 0:69 0:65 1:aa 0:6e 0:67 3:d5.6e.67 0:20"),
        ("tcvn3", "ruwowjuj", "0:72 0:75 1:ad 0:6f 1:ac 1:ee 0:75 0: 0:20"),
        ("tcvn3", "docker", "0:64 0:6f 0:63 0:6b 0:65 4:e1.63.6b.65 4:6f.63.6b.65.72.20"),
        ("tcvn3", "Vieejt", "0:56 0:69 0:65 1:aa 1:d6 0:74 0:20"),
        ("vniWindows", "vieejt", "0:76 0:69 0:65 0:e2 1:e4 0:74 0:20"),
        ("vniWindows", "tosf", "0:74 0:6f 0:f9 1:f8 0:20"),
        ("vniWindows", "tasks", "0:74 0:61 0:f9 0:6b 0: 2:73.6b.73.20"),
        ("vniWindows", "nguyeexn", "0:6e 0:67 0:75 0:79 0:65 0:e2 1:e3 0:6e 0:20"),
        ("vniWindows", "dduwowcj", "0:64 1:f1 0:75 1:f6 0:6f 1:f4 0:63 1:ef.63 0:20"),
        ("vniWindows", "hoaf", "0:68 0:6f 0:61 1:f8.61 0:20"),
        ("vniWindows", "tieengs", "0:74 0:69 0:65 0:e2 0:6e 0:67 3:e1.6e.67 0:20"),
        ("vniWindows", "ruwowjuj", "0:72 0:75 1:f6 0:6f 1:f4 0:ef 0:75 0: 0:20"),
        ("vniWindows", "docker", "0:64 0:6f 0:63 0:6b 0:65 3:fb.63.6b.65 4:63.6b.65.72.20"),
        ("vniWindows", "Vieejt", "0:56 0:69 0:65 0:e2 1:e4 0:74 0:20"),
    ]

    private static func signature(table: CodeTable, keys: String) -> String {
        var config = EngineConfig()
        config.codeTable = table
        let engine = Engine(config: config)
        func entry(_ r: EngineResult) -> String {
            let hex = r.text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ".")
            return "\(r.backspaceCount):\(hex)"
        }
        var steps = keys.map { entry(engine.process(KeyInput($0))) }
        steps.append(entry(engine.process(KeyInput(" "))))
        return steps.joined(separator: " ")
    }

    @Test(arguments: CodeUnitEditsUnchangedTests.recorded.map { [$0.table, $0.keys, $0.edits] })
    func editsMatchTheBaseCommit(_ row: [String]) throws {
        let table = try #require(CodeTable(rawValue: row[0]))
        #expect(Self.signature(table: table, keys: row[1]) == row[2], "table=\(row[0]) keys=\(row[1])")
    }
}
