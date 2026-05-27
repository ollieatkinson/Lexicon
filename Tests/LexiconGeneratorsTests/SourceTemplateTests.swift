//
// github.com/screensailor 2026
//
import Testing
@testable import LexiconGenerators

@Suite

struct SourceTemplateTests {

	@Test
	func test_render_replaces_placeholders() throws {
		let source = try SourceTemplate("hello {{name}}").render(["name": "world"])

		#expect(source == "hello world")
	}

	@Test
	func test_render_supports_alternateDelimiters() throws {
		let source = try SourceTemplate("public var body: String { %%value%% }", delimiters: .percentSigns)
			.render(["value": "\"ok\""])

		#expect(source == "public var body: String { \"ok\" }")
	}

	@Test
	func test_render_supports_alternateDelimitersWithSwiftLiteralBraces() throws {
		let source = try SourceTemplate(
			"var id: (I) -> String {{ $0.__ }}\nlet %%name%% = %%type%%()",
			delimiters: .percentSigns
		)
		.render([
			"name": "test",
			"type": "L_test",
		])

		#expect(source == """
		var id: (I) -> String {{ $0.__ }}
		let test = L_test()
		""")
	}

	@Test
	func test_render_does_not_parse_replacement_values() throws {
		let source = try SourceTemplate("let value = \"{{value}}\"").render(["value": "literal {{braces}}"])

		#expect(source == "let value = \"literal {{braces}}\"")
	}

	@Test
	func test_render_throws_for_unresolvedPlaceholders() {
		do {
			_ = try SourceTemplate("let {{name}} = {{value}}").render(["name": "test"])
			Issue.record("Expected unresolved placeholder to throw.")
		} catch {
			let description = String(describing: error)
			#expect(description.contains("Unresolved source template placeholder"))
			#expect(description.contains("{{value}}"))
		}
	}

	@Test
	func test_render_treats_non_identifier_braces_as_literalText() throws {
		let source = try SourceTemplate("{{ not a placeholder }}").render([:])

		#expect(source == "{{ not a placeholder }}")
	}
}
