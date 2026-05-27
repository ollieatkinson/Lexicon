//
// github.com/screensailor 2026
//

import Testing
#if !os(Android)
import Foundation

@Suite

struct LexiconCLICommandTests {

	@Test
	func test_tree_refs_format_and_diff_commands() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let source = directory.appendingPathComponent("source.taskpaper")
		let renamed = directory.appendingPathComponent("renamed.taskpaper")
		try Data(Self.fixture.utf8).write(to: source)

		let tree = try Self.lexicon("tree", source.path, "root", "--depth", "1", "--metadata").stdout
		#expect(tree.contains("\"id\" : \"root.item\""))
		#expect(tree.contains("\"type\" : ["))

		let refs = try Self.lexicon("refs", source.path, "root.item").stdout
		#expect(refs.contains("\"kind\" : \"type\""))
		#expect(refs.contains("\"resolved\" : \"root.type\""))

		let search = try Self.lexicon(
			"search",
			source.path,
			"root.type",
			"item",
			"--mode",
			"token",
			"--limit",
			"5",
			"--embedding-provider",
			"none"
		).stdout
		#expect(search.contains("\"query\" : \"root.type item\""))
		#expect(search.contains("\"id\" : \"root.item\""))
		#expect(search.contains("\"field\" : \"type\""))

		let fullSearch = try Self.lexicon(
			"search",
			source.path,
			"inherited",
			"--mode",
			"token",
			"--scope",
			"full",
			"--depth",
			"2",
			"--embedding-provider",
			"none"
		).stdout
		#expect(fullSearch.contains("\"id\" : \"root.item\""))
		#expect(fullSearch.contains("\"field\" : \"contextChild\""))

		let format = try Self.lexicon("format", source.path, "--check").stdout
		#expect(format.contains("\"changed\" : true"))

		_ = try Self.lexicon("rename", source.path, "root.item", "entry", "--output", renamed.path)
		let renamedOutput = try String(contentsOf: renamed, encoding: .utf8)
		#expect(renamedOutput.contains("= entry"))
		#expect(!(renamedOutput.contains("= root.entry")))
		let diff = try Self.lexicon("diff", source.path, renamed.path).stdout
		#expect(diff.contains("\"id\" : \"root.entry\""))
		#expect(diff.contains("\"id\" : \"root.item\""))
	}

	@Test
	func test_interactive_session() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let source = directory.appendingPathComponent("source.taskpaper")
		try Data(Self.fixture.utf8).write(to: source)

		let result = try Self.lexicon(
			"interactive",
			source.path,
			stdin: "ls\ninspect root.item\nrefs root.item\nquit\n"
		)
		#expect(result.stdout.contains("ready: lexicon interactive ready"))
		#expect(result.stdout.contains("root\n  alias\n  item\n  type"))
		#expect(result.stdout.contains("root.item"))
		#expect(result.stdout.contains("Outgoing:\n  type root.type -> root.type"))

		let json = try Self.lexicon(
			"interactive",
			source.path,
			"--json",
			stdin: "search root.type item --mode token\ninspect root.item\nquit\n"
		)
		#expect(json.stdout.contains("\"event\":\"ready\""))
		#expect(json.stdout.contains("\"query\":\"root.type item\""))
		#expect(json.stdout.contains("\"id\":\"root.item\""))
	}

	@Test
	func test_interactive_editing_validation_errors() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let source = directory.appendingPathComponent("source.taskpaper")
		try Data(Self.fixture.utf8).write(to: source)

		let result = try Self.lexicon(
			"interactive",
			source.path,
			stdin: """
			unset-type root.item root.missing
			set-protonym root.alias
			set-default root.item
			note add root.item
			comment remove root.item
			note clear root.item extra
			quit

			"""
		)
		#expect(result.stdout.contains("error: Node 'root.item' does not declare type 'root.missing'."))
		#expect(result.stdout.contains("error: Missing required argument: protonym reference or --clear"))
		#expect(result.stdout.contains("error: Provide a default value or --clear."))
		#expect(result.stdout.contains("error: Note add requires text."))
		#expect(result.stdout.contains("error: Comment remove requires text."))
		#expect(result.stdout.contains("error: Note clear does not take text."))
	}

	@Test
	func test_editing_commands_write_taskpaper() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let source = directory.appendingPathComponent("source.taskpaper")
		let added = directory.appendingPathComponent("added.taskpaper")
		let noted = directory.appendingPathComponent("noted.taskpaper")
		try Data(Self.fixture.utf8).write(to: source)

		_ = try Self.lexicon(
			"add",
			source.path,
			"root",
			"child",
			"--type",
			"root.type",
			"--output",
			added.path
		)
		let addOutput = try String(contentsOf: added, encoding: .utf8)
		#expect(addOutput.contains("child:"))
		#expect(addOutput.contains("+ root.type"))

		_ = try Self.lexicon("note", "add", added.path, "root.child", "agent visible", "--output", noted.path)
		let inspect = try Self.lexicon("inspect", noted.path, "root.child").stdout
		#expect(inspect.contains("\"notes\" : ["))
		#expect(inspect.contains("agent visible"))
	}

	@Test
	func test_validation_rejects_absolute_protonym_references() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let source = directory.appendingPathComponent("source.taskpaper")
		try Data("""
		root:
			item:
			alias:
			= root.item
		""".utf8).write(to: source)

		let output = try Self.lexicon("validate", source.path).stdout
		#expect(output.contains("\"valid\" : false"))
		#expect(output.contains("\"kind\" : \"unresolvedProtonym\""))

		let refs = try Self.lexicon("refs", source.path, "root.alias").stdout
		#expect(refs.contains("\"kind\" : \"protonym\""))
		#expect(refs.contains("\"exists\" : false"))
	}
}

private extension LexiconCLICommandTests {

	static let fixture = """
	root:
		type:
			inherited:
		item:
		+ root.type
		alias:
		= item
	"""

	static func lexicon(_ arguments: String..., stdin: String? = nil) throws -> (stdout: String, stderr: String) {
		try lexicon(arguments, stdin: stdin)
	}

	static func lexicon(_ arguments: [String], stdin: String? = nil) throws -> (stdout: String, stderr: String) {
		let process = Process()
		process.executableURL = packageRoot().appendingPathComponent(".build/debug/lexicon")
		process.arguments = arguments

		let stdout = Pipe()
		let stderr = Pipe()
		process.standardOutput = stdout
		process.standardError = stderr

		if let stdin {
			let input = Pipe()
			process.standardInput = input
			try process.run()
			input.fileHandleForWriting.write(Data(stdin.utf8))
			try input.fileHandleForWriting.close()
		} else {
			try process.run()
		}

		process.waitUntilExit()
		let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		guard process.terminationStatus == 0 else {
			throw "lexicon \(arguments.joined(separator: " ")) failed: \(error)\n\(output)"
		}
		return (output, error)
	}

	static func packageRoot() -> URL {
		var url = URL(fileURLWithPath: #filePath)
		for _ in 0..<3 {
			url.deleteLastPathComponent()
		}
		return url
	}
}
#endif
