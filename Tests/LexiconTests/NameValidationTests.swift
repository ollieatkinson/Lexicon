import Testing

@Suite
struct NameValidationTests {
	@Test
	func ascii_names_and_unicode_transitions_keep_the_same_grammar() {
		let grammar = #/(?!.*__)[A-Za-z_][A-Za-z0-9_]*/#
		let ascii = (0 ..< 128).compactMap(Unicode.Scalar.init).map(String.init)
		for first in [""] + ascii {
			for second in [""] + ascii {
				let name = first + second
				let prefix = name.wholeMatch(of: grammar) != nil
				#expect(Lemma.Name.isValidPrefix(name) == prefix, "Prefix: \(name.debugDescription)")
				#expect(Lemma.Name.isValid(name) == (prefix && name != "_"), "Name: \(name.debugDescription)")
			}
		}
		for (name, valid) in [
			("a__b", false),
			("_a_2_", true),
			("é_2", true),
			("東京", true),
			("א_2", true),
			("a\u{0301}", true),
			("aa\u{0301}", true),
			("a_\u{0301}", false),
			("_\u{0301}a", false),
			("a__\u{0301}", false),
			("é__x", false),
			("_é_", true),
			("١", false),
			("a١", true),
			("a١\u{0301}", false),
			("a\u{200D}", false),
			("a💡", false),
			("a\n", false)
		] {
			#expect(Lemma.Name.isValidPrefix(name) == valid, "Prefix: \(name.debugDescription)")
			#expect(Lemma.Name.isValid(name) == valid, "Name: \(name.debugDescription)")
		}
	}
}
