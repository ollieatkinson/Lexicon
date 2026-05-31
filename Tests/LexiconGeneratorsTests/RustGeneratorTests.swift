//
// github.com/screensailor 2026
//

import Testing
import Foundation

@Suite

struct RustGeneratorTests {

	@Test
	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try RustStandAloneGenerator.generate(json).string()

		#expect(code == (try "test.rs".file().string()))
	}

	@Test
	func test_generated_selectors_preserve_lexicon_case_and_raw_keywords() async throws {
		let source = """
		type:
			camelCase:
				PascalCase:
			fn:
			struct:
		"""
		var json = try await Lexicon.from(TaskPaper(source).decode()).json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try RustStandAloneGenerator.generate(json).string()

		#expect(code.contains("pub fn l() -> Lexicon"))
		#expect(code.contains("pub r#type: L_type,"))
		#expect(code.contains("pub fn r#type() -> L_type"))
		#expect(code.contains("pub camelCase: L_type_camelCase,"))
		#expect(code.contains("pub PascalCase: L_type_camelCase_PascalCase,"))
		#expect(code.contains("pub r#fn: L_type_fn,"))
		#expect(code.contains("pub r#struct: L_type_struct,"))
		#expect(code.contains("(type.fn) => {"))
		#expect(code.contains("l().r#type.r#fn"))
		#expect(code.contains("pub(crate) use __lexicon_l as l;"))
		#expect(!code.contains("pub type_:"))
		#expect(!code.contains("pub fn type_()"))
		#expect(!code.contains("self_"))
		#expect(!code.contains("struct_"))
	}

	@Test
	func test_generated_type_names_preserve_path_separators() async throws {
		let source = """
		root:
			foo_bar:
			foo:
				bar:
		"""
		var json = try await Lexicon.from(TaskPaper(source).decode()).json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try RustStandAloneGenerator.generate(json).string()

		#expect(code.contains("pub struct L_root_foo__bar"))
		#expect(code.contains("pub struct L_root_foo_bar"))
	}

	@Test
	func test_unsupported_path_keywords_fail_instead_of_renaming() async throws {
		let source = """
		test:
			self:
		"""
		var json = try await Lexicon.from(TaskPaper(source).decode()).json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		do {
			_ = try RustStandAloneGenerator.generate(json).string()
			Issue.record("Expected unsupported Rust path keyword to throw.")
		} catch {
			let description = String(describing: error)
			#expect(description.contains("Rust cannot generate exact member syntax for 'self'"))
			#expect(!description.contains("self_"))
		}
	}

	@Test
	func test_generated_code_formats_and_compiles() async throws {
		guard Self.hasCommand("rustc"), Self.hasCommand("rustfmt") else {
			return
		}

		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)
		let code = try RustStandAloneGenerator.generate(json)

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconRustStandAloneTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		try code.write(to: directory.appendingPathComponent("lexicon.rs"))
		try Data(Self.rustMain.utf8)
			.write(to: directory.appendingPathComponent("main.rs"))
		try Data(Self.rustInvalidMacroMain.utf8)
			.write(to: directory.appendingPathComponent("bad.rs"))

		try Self.run("rustfmt lexicon.rs main.rs", in: directory)
		try Self.run("rustc --edition=2021 main.rs", in: directory)
		do {
			try Self.run("rustc --edition=2021 bad.rs", in: directory)
			Issue.record("Expected invalid l! path to fail at compile time.")
		} catch {
			#expect(String(describing: error).contains("unknown Lexicon path: test.type.even.bed"))
		}
	}
}

private extension RustGeneratorTests {

	static let rustMain = """
	mod lexicon;

	use lexicon::{l, I};

	fn main() {
		let root = l();

		assert_eq!(root.test.one.more.time.id(), "test.one.more.time");
		assert_eq!(
			root.test.one.more.time.one().more.time.id(),
			"test.one.more.time.one.more.time"
		);
		assert_eq!(root.test.r#type.even.bad.id(), "test.type.even.no.good");
		assert_eq!(
			root.test.one.more.time.r#type().even.id(),
			"test.one.more.time.type.even"
		);
		assert_eq!(root.test.two.bad().id(), "test.two.no.good");
		assert_eq!(l!(test).id(), "test");
		assert_eq!(l!(test.type.even.bad).id(), "test.type.even.no.good");
		assert_eq!(l!(test.two.bad).id(), "test.two.no.good");
		assert_eq!(
			l!(test.one.more.time.type.even.bad).id(),
			"test.one.more.time.type.even.no.good"
		);
		assert_eq!(lexicon::test().r#type.even.bad.id(), "test.type.even.no.good");
	}
	"""

	static let rustInvalidMacroMain = """
	mod lexicon;

	use lexicon::l;

	fn main() {
		let _ = l!(test.type.even.bed);
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
