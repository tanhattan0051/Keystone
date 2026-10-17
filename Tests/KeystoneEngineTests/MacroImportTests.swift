import Testing
@testable import KeystoneEngine

// Import of macro text files: real OpenKey export format (`name:content`
// lines under a `;Compatible OpenKey ...` header), format sniffing, and the
// merge dedupe used by the app's import flow.

private let openKeyHeader = ";Compatible OpenKey Macro Data file for UniKey*** version=1 ***"

private func pairs(_ rules: [MacroRule]) -> [String] {
    rules.map { "\($0.trigger)=\($0.replacement)" }
}

@Suite("parseOpenKey")
struct ParseOpenKeyTests {
    @Test func realisticExport() {
        let text = [openKeyHeader, "vn:Việt Nam", "tphcm:Thành phố Hồ Chí Minh", "ko:không", ""]
            .joined(separator: "\n")
        #expect(pairs(MacroTable.parseOpenKey(text)) == [
            "vn=Việt Nam", "tphcm=Thành phố Hồ Chí Minh", "ko=không",
        ])
    }

    @Test func importedRulesUseDefaultFlags() {
        let rule = MacroTable.parseOpenKey("\(openKeyHeader)\nvn:Việt Nam\n")[0]
        #expect(rule == MacroRule(trigger: "vn", replacement: "Việt Nam"))
    }

    @Test func crlfLines() {
        let text = "\(openKeyHeader)\r\nvn:Việt Nam\r\nko:không\r\n"
        #expect(pairs(MacroTable.parseOpenKey(text)) == ["vn=Việt Nam", "ko=không"])
    }

    @Test func leadingBomIsStripped() {
        let text = "\u{FEFF}\(openKeyHeader)\nvn:Việt Nam\n"
        #expect(pairs(MacroTable.parseOpenKey(text)) == ["vn=Việt Nam"])
    }

    @Test func bomOnHeaderlessFileDoesNotPoisonFirstTrigger() {
        #expect(pairs(MacroTable.parseOpenKey("\u{FEFF}vn:Việt Nam\n")) == ["vn=Việt Nam"])
    }

    @Test func colonInsideContentSplitsOnFirstColonOnly() {
        let text = "\(openKeyHeader)\nweb:https://example.com\n"
        #expect(pairs(MacroTable.parseOpenKey(text)) == ["web=https://example.com"])
    }

    @Test func leadingColonNames() {
        let text = "\(openKeyHeader)\n:D:smile\n::x\n"
        #expect(pairs(MacroTable.parseOpenKey(text)) == [":D=smile", ":=x"])
    }

    @Test func lineWithoutColonIsSkipped() {
        let text = "\(openKeyHeader)\nnocolon\nvn:Việt Nam\n"
        #expect(pairs(MacroTable.parseOpenKey(text)) == ["vn=Việt Nam"])
    }

    @Test func emptyContentIsKept() {
        #expect(pairs(MacroTable.parseOpenKey("\(openKeyHeader)\nx:\n")) == ["x="])
    }

    @Test func lineOfOnlyColonHasNoUsableName() {
        // ":" -> name "", content "" -> the leading-colon loop needs non-empty content.
        #expect(MacroTable.parseOpenKey("\(openKeyHeader)\n:\n").isEmpty)
    }

    @Test func headerOnlyFileIsEmpty() {
        #expect(MacroTable.parseOpenKey(openKeyHeader).isEmpty)
        #expect(MacroTable.parseOpenKey(openKeyHeader + "\n").isEmpty)
    }

    @Test func headerlessColonFileKeepsItsFirstLine() {
        #expect(pairs(MacroTable.parseOpenKey("vn:Việt Nam\nko:không\n")) == ["vn=Việt Nam", "ko=không"])
    }

    @Test func duplicatesAreKeptInFileOrder() {
        let text = "\(openKeyHeader)\na:1\na:2\n"
        #expect(pairs(MacroTable.parseOpenKey(text)) == ["a=1", "a=2"])
    }

    @Test func emptyInputIsEmpty() {
        #expect(MacroTable.parseOpenKey("").isEmpty)
    }
}

@Suite("detectTextFormat / parseLegacyText")
struct DetectTextFormatTests {
    @Test func semicolonHeaderIsOpenKey() {
        #expect(MacroTable.detectTextFormat("\(openKeyHeader)\nvn:Việt Nam") == .openKey)
    }

    @Test func bomPlusHeaderIsOpenKey() {
        #expect(MacroTable.detectTextFormat("\u{FEFF}\(openKeyHeader)\nvn:x") == .openKey)
    }

    @Test func tabAnywhereIsTabSeparated() {
        #expect(MacroTable.detectTextFormat("vn\tViệt Nam\n") == .tabSeparated)
    }

    @Test func neitherIsHeaderlessOpenKey() {
        #expect(MacroTable.detectTextFormat("vn:Việt Nam\n") == .openKey)
    }

    @Test func headerWinsOverTabInContent() {
        #expect(MacroTable.detectTextFormat("\(openKeyHeader)\nvn:a\tb") == .openKey)
    }

    @Test func legacyTextDispatches() {
        #expect(pairs(MacroTable.parseLegacyText("vn\tViệt Nam\n")) == ["vn=Việt Nam"])
        #expect(pairs(MacroTable.parseLegacyText("\(openKeyHeader)\nvn:Việt Nam\n")) == ["vn=Việt Nam"])
        #expect(MacroTable.parseLegacyText("hello world").isEmpty)
    }
}

@Suite("rulesToAdd")
struct RulesToAddTests {
    private func rule(_ t: String, _ r: String = "x") -> MacroRule {
        MacroRule(trigger: t, replacement: r)
    }

    @Test func skipsExistingTriggers() {
        let out = MacroTable.rulesToAdd([rule("a"), rule("b")], existingTriggers: ["a"])
        #expect(out.toAdd.map(\.trigger) == ["b"])
        #expect(out.skippedDuplicates == 1)
    }

    @Test func withinFileDuplicateFirstWins() {
        let out = MacroTable.rulesToAdd([rule("a", "1"), rule("a", "2")], existingTriggers: [])
        #expect(pairs(out.toAdd) == ["a=1"])
        #expect(out.skippedDuplicates == 1)
    }

    @Test func emptyTriggerDroppedAndNotCountedAsDuplicate() {
        let out = MacroTable.rulesToAdd([rule(""), rule("a")], existingTriggers: [])
        #expect(out.toAdd.map(\.trigger) == ["a"])
        #expect(out.skippedDuplicates == 0)
    }

    @Test func preservesOrderAndFlags() {
        let flagged = MacroRule(trigger: "z", replacement: "Z", enabled: false,
                                expandInEnglishMode: true, autoCapitalize: true)
        let out = MacroTable.rulesToAdd([rule("b"), flagged, rule("a")], existingTriggers: [])
        #expect(out.toAdd.map(\.trigger) == ["b", "z", "a"])
        #expect(out.toAdd[1] == flagged)
        #expect(out.skippedDuplicates == 0)
    }

    @Test func triggersAreCaseSensitive() {
        let out = MacroTable.rulesToAdd([rule("A")], existingTriggers: ["a"])
        #expect(out.toAdd.count == 1)
    }
}
