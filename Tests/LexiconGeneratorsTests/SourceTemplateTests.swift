//
// github.com/screensailor 2026
//

@_exported import Hope
@testable import LexiconGenerators
import XCTest

final class SourceTemplateTests: Hopes {

	func test_renders_default_double_brace_placeholders() throws {
		let template = SourceTemplate("type {{name}} = {{target}}")

		let source = try template.render([
			"name": "L_test",
			"target": "L_root",
		])

		hope(source) == "type L_test = L_root"
	}

	func test_renders_custom_delimiters_without_treating_double_braces_as_placeholders() throws {
		let template = SourceTemplate(
			"var id: (I) -> String {{ $0.__ }}\nlet %%name%% = %%type%%()",
			delimiters: .percentSigns
		)

		let source = try template.render([
			"name": "test",
			"type": "L_test",
		])

		hope(source) == """
		var id: (I) -> String {{ $0.__ }}
		let test = L_test()
		"""
	}

	func test_throws_when_a_placeholder_is_unresolved() throws {
		do {
			_ = try SourceTemplate("let {{name}} = {{value}}").render(["name": "test"])
			XCTFail("Expected unresolved placeholder error")
		} catch {
			hope.true(String(describing: error).contains("Unresolved source template placeholder"))
			hope.true(String(describing: error).contains("{{value}}"))
		}
	}
}
