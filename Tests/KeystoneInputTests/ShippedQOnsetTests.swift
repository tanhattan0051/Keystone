// ShippedQOnsetTests.swift — bare q and qu+o/u/ư are not Vietnamese syllables.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("Shipped q onset", .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct ShippedQOnsetTests {

    @Test("q without the u glide, and qu+o/u/ư, restore to the raw keys",
          arguments: [("qas", "qas "), ("quos", "quos "), ("qo", "qo "),
                      ("quus", "quus "), ("quuf", "quuf ")])
    func rejected(keys: String, screen: String) {
        #expect(typeShipped(keys) == screen)
    }

    @Test("real qu words keep composing (Telex)",
          arguments: [("quoocs", "quốc "), ("quaan", "quân "), ("quowf", "quờ "),
                      ("quyeenf", "quyền "), ("quys", "quý "), ("quaj", "quạ "),
                      ("quee", "quê "), ("quay", "quay "), ("quaayf", "quầy "),
                      ("queor", "quẻo "), ("quawng", "quăng "), ("quaf", "quà "),
                      ("quanh", "quanh ")])
    func telexGuards(keys: String, screen: String) {
        #expect(typeShipped(keys) == screen)
    }

    @Test("real qu words keep composing (VNI)",
          arguments: [("quo6c1", "quốc "), ("qua6n", "quân ")])
    func vniGuards(keys: String, screen: String) {
        var cfg = shippedConfig
        cfg.inputMethod = .vni
        #expect(typeShipped(keys, config: cfg) == screen)
    }
}
