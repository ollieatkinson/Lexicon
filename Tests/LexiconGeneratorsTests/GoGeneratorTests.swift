//
// github.com/screensailor 2026
//

import Testing
import Foundation

@Suite

struct GoGeneratorTests {

	@Test
	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try GoStandAloneGenerator.generate(json).string()

		#expect(code == (try "test.go".file().string()))
	}

	@Test
	func test_generated_selectors_are_exported_titlecase_without_keyword_underscores() async throws {
		let source = """
		type:
			camelCase:
				PascalCase:
			func:
			select:
		"""
		var json = try await TaskPaper(source).lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try GoStandAloneGenerator.generate(json).string()

		#expect(code.contains("type Lemma string"))
		#expect(code.contains("func l(path string) Lemma"))
		#expect(!code.contains("func L(path string) Lemma"))
		#expect(code.contains("func (l Lemma) ID() string"))
		#expect(code.contains("var Type = new_L_type(\"type\")"))
		#expect(code.contains("CamelCase L_type_camelCase"))
		#expect(code.contains("PascalCase L_type_camelCase_PascalCase"))
		#expect(code.contains("Func L_type_func"))
		#expect(code.contains("Select L_type_select"))
		#expect(!code.contains("type__"))
		#expect(!code.contains("func__"))
		#expect(!code.contains("select__"))
		#expect(!code.contains("func lemma("))
		#expect(!code.contains("func child("))
		#expect(code.contains("l.Func = new_L_type_func(id + \".func\")"))
		#expect(code.contains("l.Select = new_L_type_select(id + \".select\")"))
	}

	@Test
	func test_generated_keyword_selectors_do_not_collide_with_trailing_underscore_names() async throws {
		let source = """
		root:
			type:
			type_:
		"""
		var json = try await TaskPaper(source).lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try GoStandAloneGenerator.generate(json).string()

		#expect(code.contains("Type L_root_type"))
		#expect(code.contains("Type_ L_root_type__"))
		#expect(code.contains("l.Type = new_L_root_type(id + \".type\")"))
		#expect(code.contains("l.Type_ = new_L_root_type__(id + \".type_\")"))
	}

	@Test
	func test_generated_selectors_fail_when_titlecase_collides() async throws {
		let source = """
		root:
			type:
			Type:
		"""
		var json = try await TaskPaper(source).lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		do {
			_ = try GoStandAloneGenerator.generate(json).string()
			Issue.record("Expected titlecase selector collision to throw.")
		} catch {
			let description = String(describing: error)
			#expect(description.contains("Go selector collision in 'root'"))
			#expect(description.contains("both generate 'Type'"))
		}
	}

	@Test
	func test_generated_source_rejects_base_selector_collisions() async throws {
		for source in [
			"l:",
			"lemma:",
			"root:\n\tID:",
			"root:\n\tL:",
			"root:\n\tLocalized:",
		] {
			let json = try await source.lexicon().json()
			do {
				_ = try GoStandAloneGenerator.generateSource(json)
				Issue.record("Expected Go base selector collision to throw.")
			} catch {
				#expect(String(describing: error).contains("Go"))
				#expect(String(describing: error).contains("selector '"))
			}
		}
	}

	@Test
	func test_protonym_chain_compiles_and_resolves_to_canonical_id() async throws {
		guard Self.hasCommand("go"), Self.hasCommand("gofmt") else {
			return
		}
		let json = try await """
		root:
			target:
			alias1:
			= target
			alias2:
			= alias1
		""".lexicon().json()
		let code = try GoStandAloneGenerator.generate(json)
		let source = try code.string()

		#expect(source.contains("type L_root_alias1 = L_root_target"))
		#expect(source.contains("type L_root_alias2 = L_root_target"))
		#expect(source.contains("l.Alias2 = new_L_root_target(id + \".target\")"))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconGoProtonymTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		try code.write(to: directory.appendingPathComponent("lexicon.go"))
		try Data("module lexicon.test\n\ngo 1.18\n".utf8)
			.write(to: directory.appendingPathComponent("go.mod"))
		try Data("""
		package lexicon

		import "testing"

		func TestProtonymChain(t *testing.T) {
			if Root.Alias2.ID() != "root.target" {
				t.Fatalf("got %q", Root.Alias2.ID())
			}
		}
		""".utf8).write(to: directory.appendingPathComponent("lexicon_test.go"))

		try Self.run("gofmt -w .", in: directory)
		try Self.run("go test .", in: directory)
	}

	@Test
	func test_generated_type_names_preserve_path_separators() async throws {
		let source = """
		root:
			foo_bar:
			foo:
				bar:
		"""
		var json = try await TaskPaper(source).lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try GoStandAloneGenerator.generate(json).string()

		#expect(code.contains("type L_root_foo__bar struct"))
		#expect(code.contains("type L_root_foo_bar struct"))
	}

	@Test
	func test_decomposed_lexicon_letters_generate_valid_go_identifiers() async throws {
		let decomposedName = "e\u{301}"
		let json = try await "root:\n\t\(decomposedName):".lexicon().json()
		let code = try GoStandAloneGenerator.generate(json)
		let source = try code.string()

		#expect(source.contains("É L_root_é"))
		#expect(source.contains("return \"root.\(decomposedName)\""))

		guard Self.hasCommand("gofmt") else {
			return
		}
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconGoUnicodeTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		try code.write(to: directory.appendingPathComponent("lexicon.go"))
		try Self.run("gofmt -w lexicon.go", in: directory)
	}

	@Test
	func test_generated_source_can_use_the_consuming_go_package_name() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try GoStandAloneGenerator.generateSource(json, packageName: "commerce")

		#expect(code.hasPrefix("package commerce\n"))
	}

	@Test
	func test_generated_source_rejects_invalid_go_package_names() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		for packageName in ["type", "_"] {
			do {
				_ = try GoStandAloneGenerator.generateSource(json, packageName: packageName)
				Issue.record("Expected invalid Go package name to throw.")
			} catch {
				#expect(String(describing: error).contains(
					"'\(packageName)' is not a valid Go package name."
				))
			}
		}
	}

	@Test
	func test_generated_code_formats_and_compiles() async throws {
		guard Self.hasCommand("go"), Self.hasCommand("gofmt") else {
			return
		}

		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)
		let code = try GoStandAloneGenerator.generate(json)

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconGoStandAloneTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		try code.write(to: directory.appendingPathComponent("lexicon.go"))
		try Data("module lexicon.test\n\ngo 1.18\n".utf8)
			.write(to: directory.appendingPathComponent("go.mod"))
		try Data(Self.goTest.utf8)
			.write(to: directory.appendingPathComponent("lexicon_test.go"))
		try Data(Self.goExternalTest.utf8)
			.write(to: directory.appendingPathComponent("external_test.go"))

		try Self.run("gofmt -w .", in: directory)
		try Self.run("go test .", in: directory)
	}
}

private extension GoGeneratorTests {

	static let goTest = """
	package lexicon

	import "testing"

	func TestGeneratedLexicon(t *testing.T) {
		if Test.One.More.Time.ID() != "test.one.more.time" {
			t.Fatal("child fields did not preserve dot syntax")
		}
		if Test.One.More.Time.One().More.Time.ID() != "test.one.more.time.one.more.time" {
			t.Fatal("inherited child accessors did not preserve receiver path")
		}
		if Test.Type.Even.Bad.ID() != "test.type.even.no.good" {
			t.Fatal("synonym accessor did not forward to protonym")
		}
		if Test.One.More.Time.Type().Even.ID() != "test.one.more.time.type.even" {
			t.Fatal("inherited keyword accessor did not preserve receiver path")
		}
		if Test.Two.Bad().ID() != "test.two.no.good" {
			t.Fatal("inherited synonym accessor did not preserve receiver path")
		}
		if l("test.type.even.bad").ID() != "test.type.even.bad" {
			t.Fatal("string lemma helper did not preserve the exact path")
		}
		var lemma I = l("test.type.even.bad")
		if lemma.Localized() != "test.type.even.bad" {
			t.Fatal("string lemma helper did not satisfy the generated interface")
		}
	}
	"""

	static let goExternalTest = """
	package lexicon_test

	import (
		"testing"

		lexicon "lexicon.test"
	)

	func TestGeneratedLexiconExportedAPI(t *testing.T) {
		if lexicon.Test.Type.Even.Bad.ID() != "test.type.even.no.good" {
			t.Fatal("exported selector API did not work from another package")
		}
		if lexicon.Test.One.More.Time.Type().Even.ID() != "test.one.more.time.type.even" {
			t.Fatal("exported inherited accessors did not work from another package")
		}
	}
	"""

	static func hasCommand(_ command: String) -> Bool {
		(try? run("command -v \(command) >/dev/null 2>&1")) != nil
	}

	static func run(_ command: String, in directory: URL? = nil) throws {
		let process = Process()
		let standardOutput = Pipe()
		let standardError = Pipe()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-lc", command]
		process.currentDirectoryURL = directory
		process.standardOutput = standardOutput
		process.standardError = standardError
		try process.run()
		process.waitUntilExit()
		let output = String(data: standardOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		let error = String(data: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		if process.terminationStatus != 0 {
			throw LexiconError("""
			Command failed (\(process.terminationStatus)): \(command)
			stdout:
			\(output)
			stderr:
			\(error)
			""")
		}
	}
}

extension String {

	func taskpaper() throws -> String {
		try "\(self).taskpaper".file().string()
	}

	func file() throws -> Data {
		guard let url = Bundle.module.url(forResource: "Resources/\(self)", withExtension: nil) else {
			throw LexiconError("Could not find '\(self)'")
		}
		return try Data(contentsOf: url)
	}

	func lexicon() async throws -> Lexicon {
		try await TaskPaper(self).lexicon()
	}
}

extension TaskPaper {

	func lexicon() async throws -> Lexicon {
		let document = try decodeDocument()
		guard let selectedRoot = document.roots.keys.first else {
			throw LexiconError("The document must contain a root")
		}
		return try await Lexicon(document: document, selectedRoot: selectedRoot)
	}
}

extension Data {

	func string(encoding: String.Encoding = .utf8) throws -> String {
		try String(data: self, encoding: encoding).try()
	}
}
