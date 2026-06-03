//
// github.com/screensailor 2026
//

import Testing
@testable import Lexicon

@Suite
struct StringSortingTests {

	@Test
	func sortedByLocalizedStandard_uses_standard_numeric_order() {
		let values = ["item 10", "item 2", "item 1"]

		#expect(values.sortedByLocalizedStandard() == ["item 1", "item 2", "item 10"])
		#expect(values.sortedByLocalizedStandard(.orderedDescending) == ["item 10", "item 2", "item 1"])
	}

	@Test
	func sortedByLocalizedStandard_accepts_string_protocol_key_paths() {
		let values = [
			Example(name: "item 10"[...]),
			Example(name: "item 2"[...]),
			Example(name: "item 1"[...])
		]

		#expect(values.sortedByLocalizedStandard(by: \.name).map(\.name) == ["item 1", "item 2", "item 10"])
	}
}

private struct Example {
	let name: Substring
}
