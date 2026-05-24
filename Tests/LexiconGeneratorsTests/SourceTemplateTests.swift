//
// github.com/screensailor 2026
//

import XCTest
@testable import LexiconGenerators

final class SourceTemplateTests: XCTestCase {

	func test_render_replaces_placeholders() throws {
		let source = try SourceTemplate("hello {{name}}").render(["name": "world"])

		XCTAssertEqual(source, "hello world")
	}

	func test_render_supports_alternateDelimiters() throws {
		let source = try SourceTemplate("public var body: String { %%value%% }", delimiters: .percentSigns)
			.render(["value": "\"ok\""])

		XCTAssertEqual(source, "public var body: String { \"ok\" }")
	}

	func test_render_does_not_parse_replacement_values() throws {
		let source = try SourceTemplate("let value = \"{{value}}\"").render(["value": "literal {{braces}}"])

		XCTAssertEqual(source, "let value = \"literal {{braces}}\"")
	}

	func test_render_throws_for_unresolvedPlaceholders() {
		XCTAssertThrowsError(try SourceTemplate("hello {{name}}").render([:]))
	}

	func test_render_treats_non_identifier_braces_as_literalText() throws {
		let source = try SourceTemplate("{{ not a placeholder }}").render([:])

		XCTAssertEqual(source, "{{ not a placeholder }}")
	}
}
