import Testing
@testable import SwiftLexicon

@Suite
struct PatternMatchingTests {

    @Test
    func string_switch_accepts_generated_lemma_patterns() {
        func route(_ id: String) -> String {
            switch id {
                case test.one: "one"
                case test.two: "two"
                default: "unknown"
            }
        }

        #expect(route("test.one") == "one")
        #expect(route("test.two") == "two")
        #expect(route("test.one.more") == "unknown")
        #expect(route("test.oneish") == "unknown")
        #expect(route("test") == "unknown")
        #expect(route("") == "unknown")
    }

    @Test
    func bracketed_patterns_match_their_full_identifier() {
        let pattern = test.one["value"]
        #expect(pattern ~= pattern.__)
        #expect(!(pattern ~= "test.one"))
        #expect(!(pattern ~= test.one["other"].__))
    }

    @Test
    func type_erased_patterns_keep_exact_identity() {
        let pattern: any I = test.one
        #expect(pattern ~= "test.one")
        #expect(!(pattern ~= "test.one.more"))
    }
}
