//
// github.com/screensailor 2026
//

import Testing
#if !os(Android)
import Foundation
import Lexicon

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
	func test_readme_imported_types_survive_add_and_rename_edits() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let examples = Self.packageRoot()
			.appendingPathComponent("Tests/LexiconTests/Resources/READMEExamples")
		for filename in [
			"commerce.lexicon",
			"shared-commerce.lexicon",
			"data-types.lexicon",
			"storefront-api.lexicon",
			"product-ui.lexicon",
		] {
			try FileManager.default.copyItem(
				at: examples.appendingPathComponent(filename),
				to: directory.appendingPathComponent(filename)
			)
		}

		let source = directory.appendingPathComponent("commerce.lexicon")
		let added = directory.appendingPathComponent("added.lexicon")
		let renamed = directory.appendingPathComponent("renamed.lexicon")
		_ = try Self.lexicon(
			"add",
			source.path,
			"commerce.api",
			"imported_entry",
			"--type",
			"commerce.db.type.string",
			"--output",
			added.path
		)
		_ = try Self.lexicon(
			"rename",
			added.path,
			"commerce.api.imported_entry",
			"renamed_entry",
			"--output",
			renamed.path
		)

		let output = try String(contentsOf: renamed, encoding: .utf8)
		#expect(output.contains("renamed_entry:"))
		#expect(output.contains("+ commerce.db.type.string"))
		#expect(!output.contains("imported_entry:"))
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

		let validation = try Self.lexiconResult(["validate", source.path])
		#expect(validation.status == 1)
		#expect(validation.stdout.contains("\"valid\" : false"))
		#expect(validation.stdout.contains("\"kind\" : \"unresolvedProtonym\""))
		#expect(validation.stderr.isEmpty)

		let refs = try Self.lexicon("refs", source.path, "root.alias").stdout
		#expect(refs.contains("\"kind\" : \"protonym\""))
		#expect(refs.contains("\"exists\" : false"))
	}

	@Test
	func test_validate_and_lint_compose_imports_unless_source_only() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let base = directory.appendingPathComponent("base.lexicon")
		let source = directory.appendingPathComponent("source.lexicon")
		try Data("""
		root:
			type:
		""".utf8).write(to: base)
		try Data("""
		@ ./base.lexicon

		root:
			item:
			+ root.type
		""".utf8).write(to: source)

		for command in ["validate", "lint"] {
			let composed = try Self.lexiconResult([command, source.path])
			#expect(composed.status == 0)
			#expect(composed.stdout.contains("\"valid\" : true"))

			let sourceOnly = try Self.lexiconResult([command, source.path, "--source-only"])
			#expect(sourceOnly.status == 1)
			#expect(sourceOnly.stdout.contains("\"valid\" : false"))
			#expect(sourceOnly.stdout.contains("\"kind\" : \"unresolvedType\""))
			#expect(sourceOnly.stderr.isEmpty)
		}
	}

	@Test
	func test_input_paths_beginning_with_http_are_local_files() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		for filename in ["http-notes.lexicon", "https-notes.lexicon"] {
			let source = directory.appendingPathComponent(filename)
			try Data("root:\n".utf8).write(to: source)

			let result = try Self.lexiconResult(
				["validate", filename, "--source-only"],
				currentDirectoryURL: directory
			)
			#expect(result.status == 0)
			#expect(result.stdout.contains("\"valid\" : true"))
			#expect(result.stderr.isEmpty)
		}
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
		let result = try lexiconResult(arguments, stdin: stdin)
		guard result.status == 0 else {
			throw LexiconError("lexicon \(arguments.joined(separator: " ")) failed: \(result.stderr)\n\(result.stdout)")
		}
		return (result.stdout, result.stderr)
	}

	static func lexiconResult(
		_ arguments: [String],
		stdin: String? = nil,
		currentDirectoryURL: URL? = nil
	) throws -> (status: Int32, stdout: String, stderr: String) {
		let process = Process()
		process.executableURL = packageRoot().appendingPathComponent(".build/debug/lexicon")
		process.arguments = arguments
		process.currentDirectoryURL = currentDirectoryURL

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
		return (process.terminationStatus, output, error)
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
