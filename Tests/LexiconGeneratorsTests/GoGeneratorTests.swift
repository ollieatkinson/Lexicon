//
// github.com/screensailor 2026
//

import Foundation

final class GoGeneratorTests: Hopes {

	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try GoStandAloneGenerator.generate(json).string()

		try hope(code) == "test.go".file().string()
	}

	func test_generated_identifiers_match_lexicon_case() async throws {
		let source = """
		caseRoot:
			camelCase:
				PascalCase:
		"""
		var json = try await Lexicon.from(TaskPaper(source).decode()).json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try GoStandAloneGenerator.generate(json).string()

		hope.true(code.contains("var caseRoot = new_L_caseRoot(\"caseRoot\")"))
		hope.true(code.contains("camelCase L_caseRoot_camelCase"))
		hope.true(code.contains("PascalCase L_caseRoot_camelCase_PascalCase"))
	}

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

		try Self.run("gofmt -w .", in: directory)
		try Self.run("go test .", in: directory)
	}
}

private extension GoGeneratorTests {

	static let goTest = """
	package lexicon

	import "testing"

	func TestGeneratedLexicon(t *testing.T) {
		if test.one.more.time.ID() != "test.one.more.time" {
			t.Fatal("child fields did not preserve dot syntax")
		}
		if test.one.more.time.one().more.time.ID() != "test.one.more.time.one.more.time" {
			t.Fatal("inherited child accessors did not preserve receiver path")
		}
		if test.type_.even.bad.ID() != "test.type.even.no.good" {
			t.Fatal("synonym accessor did not forward to protonym")
		}
		if test.two.bad().ID() != "test.two.no.good" {
			t.Fatal("inherited synonym accessor did not preserve receiver path")
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
			throw """
			Command failed (\(process.terminationStatus)): \(command)
			stdout:
			\(output)
			stderr:
			\(error)
			"""
		}
	}
}

extension String {

	func taskpaper() throws -> String {
		try "\(self).taskpaper".file().string()
	}

	func file() throws -> Data {
		guard let url = Bundle.module.url(forResource: "Resources/\(self)", withExtension: nil) else {
			throw "Could not find '\(self)'"
		}
		return try Data(contentsOf: url)
	}

	func lexicon() async throws -> Lexicon {
		try await Lexicon.from(TaskPaper(self).decode())
	}
}

extension Data {

	func string(encoding: String.Encoding = .utf8) throws -> String {
		try String(data: self, encoding: encoding).try()
	}
}
