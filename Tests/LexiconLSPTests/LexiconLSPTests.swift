//
// github.com/screensailor 2026
//

import Testing
import LexiconLSP

@Suite
struct LexiconLSPTests {

	@Test
	func test_completes_go_string_lexicon_paths() throws {
		let service = try Self.service()
		let text = #"let value = l("test.type.even.")"#

		let result = try #require(service.completion(in: text, line: 0, character: #"let value = l("test.type.even."#.utf16.count))

		#expect(result.items.map(\.label) == ["bad", "no"])
	}

	@Test
	func test_completes_partial_go_string_lexicon_paths() throws {
		let service = try Self.service()
		let text = #"let value = l("test.type.even.b")"#

		let result = try #require(service.completion(in: text, line: 0, character: #"let value = l("test.type.even.b"#.utf16.count))

		#expect(result.items.map(\.label) == ["bad"])
		#expect(result.range.start.character == #"let value = l("test.type.even."#.utf16.count)
		#expect(result.range.end.character == #"let value = l("test.type.even.b"#.utf16.count)
	}

	@Test
	func test_completes_rust_macro_lexicon_paths() throws {
		let service = try Self.service()
		let text = "let value = l!(test.type.even.)"

		let result = try #require(service.completion(in: text, line: 0, character: "let value = l!(test.type.even.".utf16.count))

		#expect(result.items.map(\.label) == ["bad", "no"])
	}

	@Test
	func test_completes_lexicon_document_references() throws {
		let service = try Self.service()
		let text = "consumer:\n\t+ test.type."

		let result = try #require(service.completion(in: text, line: 1, character: "\t+ test.type.".utf16.count))

		#expect(result.items.map(\.label) == ["even", "odd"])
	}

	@Test
	func test_completes_relative_lexicon_synonym_references() throws {
		let text = """
		test:
			type:
				even:
					bad:
						= no.
					no:
						good:
		"""
		let service = try LexiconLSPService(index: LexiconPathIndex(lexiconText: text))

		let result = try #require(service.completion(in: text, line: 4, character: "\t\t\t\t= no.".utf16.count))

		#expect(result.items.map(\.label) == ["good"])
	}

	@Test
	func test_diagnoses_unknown_code_paths() throws {
		let service = try Self.service()
		let text = #"""
		let go = l("test.type.even.bed")
		let rust = l!(test.type.even.bed)
		"""#

		let diagnostics = service.diagnostics(in: text)

		#expect(diagnostics.map(\.message) == [
			"Unknown Lexicon path 'test.type.even.bed'.",
			"Unknown Lexicon path 'test.type.even.bed'.",
		])
	}

	@Test
	func test_does_not_diagnose_incomplete_prefixes() throws {
		let service = try Self.service()
		let text = #"""
		let go = l("test.type.")
		let rust = l!(test.type.)
		consumer:
			+ test.type.
		"""#

		let diagnostics = service.diagnostics(in: text)

		#expect(diagnostics.isEmpty)
	}

	@Test
	func test_diagnoses_lexicon_document_references_and_resolves_relative_synonyms() throws {
		let text = """
		test:
			type:
				even:
					bad:
						= no.good
					wrong:
						= missing
					no:
						good:
		"""
		let service = try LexiconLSPService(index: LexiconPathIndex(lexiconText: text))

		let diagnostics = service.diagnostics(in: text)

		#expect(diagnostics.map(\.message) == [
			"Unknown Lexicon path 'test.type.even.missing'."
		])
	}

	private static func service() throws -> LexiconLSPService {
		try LexiconLSPService(index: LexiconPathIndex(lexiconText: """
		test:
			type:
				even:
					bad:
						= no.good
					no:
						good:
				odd:
					good:
		"""))
	}
}
