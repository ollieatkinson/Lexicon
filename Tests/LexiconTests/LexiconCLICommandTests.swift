//
// github.com/screensailor 2026
//

#if !os(Android)
import Foundation

final class LexiconCLICommandTests: Hopes {

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
		hope.true(tree.contains("\"id\" : \"root.item\""))
		hope.true(tree.contains("\"type\" : ["))

		let refs = try Self.lexicon("refs", source.path, "root.item").stdout
		hope.true(refs.contains("\"kind\" : \"type\""))
		hope.true(refs.contains("\"resolved\" : \"root.type\""))

		let format = try Self.lexicon("format", source.path, "--check").stdout
		hope.true(format.contains("\"changed\" : true"))

		_ = try Self.lexicon("rename", source.path, "root.item", "entry", "--output", renamed.path)
		let diff = try Self.lexicon("diff", source.path, renamed.path).stdout
		hope.true(diff.contains("\"id\" : \"root.entry\""))
		hope.true(diff.contains("\"id\" : \"root.item\""))
	}

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
		hope.true(result.stdout.contains("ready: lexicon interactive ready"))
		hope.true(result.stdout.contains("root\n  alias\n  item\n  type"))
		hope.true(result.stdout.contains("root.item"))
		hope.true(result.stdout.contains("Outgoing:\n  type root.type -> root.type"))

		let json = try Self.lexicon(
			"interactive",
			source.path,
			"--json",
			stdin: "inspect root.item\nquit\n"
		)
		hope.true(json.stdout.contains("\"event\":\"ready\""))
		hope.true(json.stdout.contains("\"id\":\"root.item\""))
	}

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
		hope.true(addOutput.contains("child:"))
		hope.true(addOutput.contains("+ root.type"))

		_ = try Self.lexicon("note", "add", added.path, "root.child", "agent visible", "--output", noted.path)
		let inspect = try Self.lexicon("inspect", noted.path, "root.child").stdout
		hope.true(inspect.contains("\"notes\" : ["))
		hope.true(inspect.contains("agent visible"))
	}
}

private extension LexiconCLICommandTests {

	static let fixture = """
	root:
		type:
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
