//
// github.com/screensailor 2026
//

import Testing
@testable import SwiftLexicon

@Suite
struct KBracketedTests {

	@Test
	func exposes_bracketed_detail() {
		let k = test.one[1].more["two"]
		let detail = k.detail
		let event = Event(k)

		#expect(k.bracketed == "test.one[1].more[two]")
		#expect(String(describing: k) == "test.one[1].more[two]")
		#expect(detail.id == "test.one.more")
		#expect(detail.data["test.one"]?.int == 1)
		#expect(detail.data["test.one.more"]?.string == "two")
		#expect(event.detail == detail)
	}

	@Test
	func initializes_from_bracketed_description() throws {
		let k = try K<L_test_one_more>(bracketed: "test.one[1].more[two]")
		let one: Int = try k[test.one]
		let more: String = try k[test.one.more]

		#expect(k.bracketed == "test.one[1].more[two]")
		#expect(k(\.id) == "test.one[1].more[two]")
		#expect(k(\.L) == test.one.more)
		#expect(one == 1)
		#expect(more == "two")
	}

	@Test
	func bracketed_description_quotes_ambiguous_strings() throws {
		for value in ["true", "null", "1", "1.5", "a]b", #"a"b"#] {
			let k = test.one[value]
			let reparsed = try K<L_test_one>(bracketed: k.bracketed)
			let reparsedValue: String = try reparsed[test.one]

			#expect(reparsed.detail == k.detail)
			#expect(reparsedValue == value)
		}
	}

	@Test
	func parses_scalar_values_from_brackets() throws {
		let k = try K<L_test_one_more_time>(bracketed: "test.one[true].more[null].time[1.5]")
		let detail = k.detail

		#expect(detail.id == "test.one.more.time")
		#expect(detail.data["test.one"]?.bool == true)
		#expect(detail.data["test.one.more"]?.isNull == true)
		#expect(detail.data["test.one.more.time"]?.double == 1.5)
	}

	@Test
	func parses_nested_json_values_from_brackets() throws {
		let k = try K<L_test_one>(bracketed: #"test.one[[1, "two"]]"#)
		let value = try #require(k.detail.data["test.one"])
		let reparsed = try K<L_test_one>(bracketed: k.bracketed)

		#expect(value.array?[0].int == 1)
		#expect(value.array?[1].string == "two")
		#expect(k.bracketed == #"test.one[[1,"two"]]"#)
		#expect(reparsed.detail == k.detail)
	}

	@Test
	func parses_json_string_brackets_inside_nested_values() throws {
		let k = try K<L_test_one>(bracketed: #"test.one[[{"text":"left]right"}]]"#)
		let value = try #require(k.detail.data["test.one"])

		#expect(value.array?[0].object?["text"]?.string == "left]right")
		#expect(try K<L_test_one>(bracketed: k.bracketed).detail == k.detail)
	}

	@Test
	func rejects_malformed_bracketed_descriptions() throws {
		#expect(throws: KBracketedDescriptionError.missingClosingBracket("test.one[two")) {
			try EventDetail(bracketed: "test.one[two")
		}

		#expect(throws: KBracketedDescriptionError.unexpectedClosingBracket("test.one]")) {
			try EventDetail(bracketed: "test.one]")
		}

		#expect(throws: KBracketedDescriptionError.emptyIdentifier("")) {
			try EventDetail(bracketed: "")
		}
	}
}
