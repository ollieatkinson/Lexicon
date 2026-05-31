//
// github.com/screensailor 2026
//

import Testing
import Foundation
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
	func test_completes_inherited_rust_macro_paths() throws {
		let service = try Self.service()
		let text = "let value = l!(test.one.more.time.type.even.)"

		let result = try #require(service.completion(in: text, line: 0, character: "let value = l!(test.one.more.time.type.even.".utf16.count))

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
	func test_completes_inherited_lexicon_document_reference_paths() throws {
		let text = """
		test:
			type:
				good:
					nice:
				even:
					bad:
					no:
					+ test.type.good
				odd:
				+ test.type.even
		consumer:
			+ test.type.odd.
			+ test.type.odd.no.
		"""
		let service = try LexiconLSPService(index: LexiconPathIndex(lexiconText: text))

		let inherited = try #require(service.completion(
			in: text,
			line: 11,
			character: "\t+ test.type.odd.".utf16.count
		))
		let nestedInherited = try #require(service.completion(
			in: text,
			line: 12,
			character: "\t+ test.type.odd.no.".utf16.count
		))

		#expect(inherited.items.map(\.label) == ["bad", "no"])
		#expect(nestedInherited.items.map(\.label) == ["nice"])
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
	func test_completes_relative_lexicon_default_references() throws {
		let text = """
		test:
			type:
				even:
					bad:
						? @ no.
					no:
						good:
		"""
		let service = try LexiconLSPService(index: LexiconPathIndex(lexiconText: text))

		let result = try #require(service.completion(in: text, line: 4, character: "\t\t\t\t? @ no.".utf16.count))

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
	func test_code_reference_regexes_use_identifier_boundaries_and_macro_syntax() throws {
		let service = try Self.service()
		let text = #"""
		let helper = call_l("test.type.even.bed")
		let invalidMacro = l!(test.type.even-bed)
		let go = object.l("test.type.even.bed")
		let rust = l!(test.type.even.bed)
		"""#

		let diagnostics = service.diagnostics(in: text)

		#expect(diagnostics.map(\.message) == [
			"Unknown Lexicon path 'test.type.even.bed'.",
			"Unknown Lexicon path 'test.type.even.bed'.",
		])
	}

	@Test
	func test_validates_go_strings_and_rust_macros_against_live_paths() throws {
		let service = try Self.service()
		let text = #"""
		let validGo = l("test.two.bad")
		let invalidGo = l("test.two.bed")
		let validRust = l!(test.one.more.time.type.even.bad)
		let invalidRust = l!(test.one.more.time.type.even.bed)
		"""#

		let diagnostics = service.diagnostics(in: text)

		#expect(diagnostics.map(\.message) == [
			"Unknown Lexicon path 'test.two.bed'.",
			"Unknown Lexicon path 'test.one.more.time.type.even.bed'.",
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

		let diagnostics = service.diagnostics(in: text, lexiconDocument: true)

		#expect(diagnostics.isEmpty)
	}

	@Test
	func test_diagnoses_space_indentation_in_lexicon_documents() throws {
		let service = try LexiconLSPService(index: LexiconPathIndex(lexiconText: "test:\n\ttype:"))
		let text = "test:\n\t    type:"

		let diagnostics = service.diagnostics(in: text, lexiconDocument: true)

		#expect(diagnostics.map(\.message) == [
			"Lexicon indentation uses tabs; spaces are ignored for hierarchy."
		])
		#expect(service.diagnostics(in: text).isEmpty)
	}

	@Test
	func test_diagnoses_lexicon_document_references_and_resolves_relative_synonyms() throws {
		let text = """
		test:
			type:
				even:
					bad:
						= no.good
						? @ no.good
					wrong:
						= missing
						? @ missing
					no:
						good:
		"""
		let service = try LexiconLSPService(index: LexiconPathIndex(lexiconText: text))

		let diagnostics = service.diagnostics(in: text, lexiconDocument: true)

		#expect(diagnostics.map(\.message) == [
			"Unknown Lexicon path 'test.type.even.missing'.",
			"Unknown Lexicon path 'missing'."
		])
	}

	@Test
	func test_indexes_composed_imports_and_connections() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconLSPTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let imported = directory.appendingPathComponent("imported.lexicon")
		let local = directory.appendingPathComponent("local.lexicon")
		try Data(
			"""
			external:
				imported:
				type:
				reference:
				+ external.type
			""".utf8
		).write(to: imported)
		try Data(
			"""
			shared:
				connected:
				@ imported.lexicon
					local:
			""".utf8
		).write(to: local)

		let index = try LexiconPathIndex(lexiconURL: local)

		#expect(index.contains("shared.connected.imported"))
		#expect(index.contains("shared.connected.reference"))
		#expect(index.contains("shared.connected.type"))
		#expect(LexiconLSPService(index: index).diagnostics(in: #"let value = l("shared.connected.reference")"#).isEmpty)
	}

	@Test
	func test_completes_composed_connection_paths() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconLSPTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let imported = directory.appendingPathComponent("imported.lexicon")
		let local = directory.appendingPathComponent("local.lexicon")
		try Data(
			"""
			external:
				imported:
				type:
				reference:
				+ external.type
			""".utf8
		).write(to: imported)
		try Data(
			"""
			shared:
				connected:
				@ imported.lexicon
					local:
			""".utf8
		).write(to: local)

		let service = try LexiconLSPService(index: LexiconPathIndex(lexiconURL: local))
		let text = "let value = l!(shared.connected.)"

		let result = try #require(service.completion(
			in: text,
			line: 0,
			character: "let value = l!(shared.connected.".utf16.count
		))

		#expect(result.items.map(\.label) == ["imported", "local", "reference", "type"])
	}

	private static func service() throws -> LexiconLSPService {
		try LexiconLSPService(index: LexiconPathIndex(lexiconText: """
		test:
			one:
			+ test.type.odd
				more:
					time:
					+ test
			two:
			+ test.type.even
				timing:
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
