//
// github.com/screensailor 2026
//

import Testing
import Foundation

@Suite

struct SwiftLexiconGeneratorTests {

	@Test
	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try SwiftLexiconGenerator.generate(json).string()

		#expect(code == (try "swift-lexicon.swift".file().string()))
	}

	@Test
	func test_custom_type_prefixes() async throws {
		let code = try await swiftLexicon(prefixes: .init(class: "Node", protocol: "Kind"))

		#expect(code.contains(#"public let test = Node_test("test")"#))
		#expect(code.contains("public final class Node_test: L, Kind_test"))
		#expect(code.contains("public protocol Kind_test: I {}"))
	}

	@Test
	func test_keyword_root_is_escaped() async throws {
		var json = try await "class:".lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try SwiftLexiconGenerator.generateSource(json)

		#expect(code.contains(#"public let `class` = L_class("class")"#))
	}

	@Test
	func test_reserved_swift_member_is_rejected_before_emitting_invalid_source() async throws {
		for member in ["debugDescription"] {
			let json = try await "root:\n\t\(member):".lexicon().json()
			#expect(throws: StandAloneGenerationError.reservedMember(
				language: "Swift",
				owner: "root",
				name: try Lemma.Name(validating: member)
			)) {
				try SwiftLexiconGenerator.generateSource(json)
			}
		}
	}

	private func swiftLexicon(prefixes: StandAloneTypePrefixes) async throws -> String {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)
		return try SwiftLexiconGenerator.generateSource(json, prefixes: prefixes)
	}
}

@Suite

struct SwiftStandAloneGeneratorTests {

	@Test
	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try SwiftStandAloneGenerator.generate(json).string()

		#expect(code == (try "test.swift".file().string()))
	}

	@Test
	func test_generated_swift_fixture() throws {
		#expect(test.one.more.time.one.more.time(\.id) == "test.one.more.time.one.more.time")

		#expect(test.two.bad == test.two.no.good)
		#expect(test.two.bad(\.id) == "test.two.no.good")
	}

	@Test
	func test_custom_type_prefixes() async throws {
		let code = try await swiftStandAlone(prefixes: .init(class: "Node", protocol: "Kind"))

		#expect(code.contains(#"public let test = Node_test("test")"#))
		#expect(code.contains("public final class Node_test: L, Kind_test"))
		#expect(code.contains("public protocol Kind_test: I {}"))
	}

	@Test
	func test_keyword_root_is_escaped() async throws {
		var json = try await "class:".lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try SwiftStandAloneGenerator.generateSource(json)

		#expect(code.contains(#"public let `class` = L_class("class")"#))
	}

	@Test
	func test_scaffold_root_names_are_rejected() async throws {
		for name in [
			"CallAsFunctionExtensions",
			"LexiconActor",
			"SourceCodeIdentifiable",
			"TypeLocalized",
		] {
			let json = try await "\(name):".lexicon().json()
			#expect(throws: StandAloneGenerationError.reservedRoot(
				language: "Swift",
				name: try Lemma.Name(validating: name)
			)) {
				try SwiftStandAloneGenerator.generateSource(json)
			}
		}
	}

	@Test
	func test_reserved_scaffold_members_are_rejected() async throws {
		for member in ["debugDescription"] {
			let json = try await "root:\n\t\(member):".lexicon().json()
			#expect(throws: StandAloneGenerationError.reservedMember(
				language: "Swift",
				owner: "root",
				name: try Lemma.Name(validating: member)
			)) {
				try SwiftStandAloneGenerator.generateSource(json)
			}
		}
	}

	@Test
	func test_protonym_chain_compiles_and_resolves_to_canonical_id() async throws {
		guard Self.hasCommand("swiftc") else {
			return
		}
		let source = try SwiftStandAloneGenerator.generateSource(
			try await """
			root:
				target:
				alias1:
				= target
				alias2:
				= alias1
			""".lexicon().json()
		)
		#expect(source.contains("public typealias L_root_alias2 = L_root_target"))
		#expect(source.contains("var `alias2`: L_root_alias2 { target }"))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconSwiftStandAloneTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		try Data("""
		\(source)

		@main struct RuntimeCheck {
			@MainActor static func main() async {
				let id = await root.alias2.__
				precondition(id == "root.target")
			}
		}
		""".utf8).write(to: directory.appendingPathComponent("main.swift"))
		try Self.run(
			"swiftc -parse-as-library main.swift -o runtime && ./runtime",
			in: directory
		)
	}

	private func swiftStandAlone(prefixes: StandAloneTypePrefixes) async throws -> String {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)
		return try SwiftStandAloneGenerator.generateSource(json, prefixes: prefixes)
	}

	private static func hasCommand(_ command: String) -> Bool {
		(try? run("command -v \(command) >/dev/null 2>&1")) != nil
	}

	private static func run(_ command: String, in directory: URL? = nil) throws {
		let process = Process()
		let standardError = Pipe()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-lc", command]
		process.currentDirectoryURL = directory
		process.standardError = standardError
		try process.run()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else {
			let error = String(
				data: standardError.fileHandleForReading.readDataToEndOfFile(),
				encoding: .utf8
			) ?? ""
			throw LexiconError("Command failed: \(command)\n\(error)")
		}
	}
}

@Suite

struct KotlinStandAloneGeneratorTests {

	@Test
	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try KotlinStandAloneGenerator.generate(json).string()

		#expect(code == (try "test.kt".file().string()))
	}

	@Test
	func test_custom_type_prefixes() async throws {
		let code = try await kotlin(prefixes: .init(class: "Node", protocol: "Kind"))

		#expect(code.contains(#"val test = Node_test("test")"#))
		#expect(code.contains("data class Node_test(override val identifier: String): L(identifier = identifier), Kind_test"))
		#expect(code.contains("interface Kind_test: I"))
	}

	@Test
	func test_keyword_root_is_escaped() async throws {
		var json = try await "class:".lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try KotlinStandAloneGenerator.generateSource(json)

		#expect(code.contains(#"val `class` = L_class("class")"#))
	}

	@Test
	func test_reserved_kotlin_member_is_rejected_before_emitting_invalid_source() async throws {
		for member in ["debugDescription", "identifier", "localized"] {
			let json = try await "root:\n\t\(member):".lexicon().json()
			#expect(throws: StandAloneGenerationError.reservedMember(
				language: "Kotlin",
				owner: "root",
				name: try Lemma.Name(validating: member)
			)) {
				try KotlinStandAloneGenerator.generateSource(json)
			}
		}
	}

	private func kotlin(prefixes: StandAloneTypePrefixes) async throws -> String {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)
		return try KotlinStandAloneGenerator.generateSource(json, prefixes: prefixes)
	}
}

@Suite

struct TypeScriptStandAloneGeneratorTests {

	@Test
	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try TypeScriptStandAloneGenerator.generate(json).string()

		#expect(code == (try "test.ts".file().string()))
	}

	@Test
	func test_custom_type_prefixes() async throws {
		let code = try await typeScript(prefixes: .init(class: "Node", protocol: "Kind"))

		#expect(code.contains(#"export const test = new Node_test("test");"#))
		#expect(code.contains("export class Node_test extends L implements Kind_test"))
		#expect(code.contains("export interface Kind_test extends I"))
	}

	@Test
	func test_generated_symbols_are_es_module_exports() async throws {
		let code = try await typeScript(
			"""
			root:
				base:
				alias:
				= base
			"""
		)

		#expect(code.contains("export interface I { }"))
		#expect(code.contains("export class L implements I"))
		#expect(code.contains("export class L_root extends L implements I_root"))
		#expect(code.contains("export interface I_root extends I"))
		#expect(code.contains("export type L_root_alias"))
		#expect(code.contains(#"export const root = new L_root("root");"#))
	}

	@Test
	func test_keyword_root_uses_an_es_module_export_alias() async throws {
		let code = try await typeScript("class:")
		let strictFutureKeyword = try await typeScript("implements:")
		let strictRestrictedBinding = try await typeScript("arguments:")

		#expect(code.contains(#"const __lexicon_root = new L_class("class");"#))
		#expect(code.contains("export { __lexicon_root as class };"))
		#expect(!code.contains("export const class"))
		#expect(strictFutureKeyword.contains(
			#"const __lexicon_root = new L_implements("implements");"#
		))
		#expect(strictFutureKeyword.contains("export { __lexicon_root as implements };"))
		#expect(!strictFutureKeyword.contains("export const implements"))
		#expect(strictRestrictedBinding.contains(
			#"const __lexicon_root = new L_arguments("arguments");"#
		))
		#expect(strictRestrictedBinding.contains("export { __lexicon_root as arguments };"))
		#expect(!strictRestrictedBinding.contains("export const arguments"))
	}

	@Test
	func test_reserved_typescript_member_is_rejected_before_emitting_invalid_source() async throws {
		for member in ["constructor", "id"] {
			let json = try await "root:\n\t\(member):".lexicon().json()
			do {
				_ = try TypeScriptStandAloneGenerator.generateSource(json)
				Issue.record("Expected TypeScript member '\(member)' to be rejected.")
			} catch let error as StandAloneGenerationError {
				#expect(error == .reservedMember(
					language: "TypeScript",
					owner: "root",
					name: try Lemma.Name(validating: member)
				))
			}
		}
	}

	@Test
	func test_generated_es_module_compiles_and_can_be_imported() async throws {
		let compiler = Self.packageRoot()
			.appendingPathComponent("Editors/VSCode/lexicon/node_modules/.bin/tsc")
		guard FileManager.default.isExecutableFile(atPath: compiler.path),
			  Self.hasCommand("node")
		else {
			return
		}

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("LexiconTypeScriptStandAloneTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		try Data(try await typeScript(prefixes: .default).utf8)
			.write(to: directory.appendingPathComponent("lexicon.ts"))
		try Data(try await typeScript(
			"""
			root:
				target:
				alias1:
				= target
				alias2:
				= alias1
			"""
		).utf8).write(to: directory.appendingPathComponent("chain.ts"))
		try Data("""
		import { test } from "./lexicon.js";
		import { root } from "./chain.js";

		if (test.one.more.__ !== "test.one.more") {
			throw new Error("generated ES module did not preserve the lexicon path");
		}
		if (test.one.good.__ !== "test.one.good") {
			throw new Error("type members were not initialized at runtime");
		}
		if (test.one.more.time.type.__ !== "test.one.more.time.type") {
			throw new Error("inherited members were not initialized at runtime");
		}
		if (test.two.bad.__ !== "test.two.no.good") {
			throw new Error("type synonyms did not resolve to their canonical path");
		}
		if (root.alias2.__ !== "root.target") {
			throw new Error("protonym chains did not resolve to their canonical path");
		}
		""".utf8).write(to: directory.appendingPathComponent("consumer.ts"))
		try Data("""
		{
		  "type": "module"
		}
		""".utf8).write(to: directory.appendingPathComponent("package.json"))
		try Data("""
		{
		  "compilerOptions": {
		    "module": "NodeNext",
		    "moduleResolution": "NodeNext",
		    "strict": true,
		    "target": "ES2022"
		  },
		  "include": ["*.ts"]
		}
		""".utf8).write(to: directory.appendingPathComponent("tsconfig.json"))

		try Self.run(compiler, arguments: ["--project", "tsconfig.json"], in: directory)
		try Self.run(
			URL(fileURLWithPath: "/usr/bin/env"),
			arguments: ["node", "consumer.js"],
			in: directory
		)
	}

	@Test
	func test_empty_type_inherits_dotted_supertype_members() async throws {
		let code = try await typeScript(
			"""
			root:
				type:
					child:
				inherited:
				+ root.type
			"""
		)

		#expect(
			code.contains(
				"""
				export class L_root_inherited extends L implements I_root_inherited {
				  get child() { return new L_root_type_child(`${this.__}.child`); }
				}
				export interface I_root_inherited extends I_root_type {
				}
				"""
			)
		)
	}

	@Test
	func test_empty_type_inherits_mixin_protocols() async throws {
		let code = try await typeScript(
			"""
			root:
				first:
					one:
				second:
					two:
				combined:
				+ root.first
				+ root.second
			"""
		)

		#expect(
			code.contains(
				"""
				export class L_root_combined extends L implements I_root_combined {
				  get one() { return new L_root_first_one(`${this.__}.one`); }
				  get two() { return new L_root_second_two(`${this.__}.two`); }
				}
				export interface I_root_combined extends I_root_first, I_root_second {
				}
				"""
			)
		)
	}

	private func typeScript(_ taskpaper: String) async throws -> String {
		var json = try await taskpaper.lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)
		return try TypeScriptStandAloneGenerator.generate(json).string()
	}

	private func typeScript(prefixes: StandAloneTypePrefixes) async throws -> String {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)
		return try TypeScriptStandAloneGenerator.generateSource(json, prefixes: prefixes)
	}

	private static func packageRoot() -> URL {
		var url = URL(fileURLWithPath: #filePath)
		for _ in 0..<3 {
			url.deleteLastPathComponent()
		}
		return url
	}

	private static func hasCommand(_ command: String) -> Bool {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["sh", "-c", "command -v \"$1\" >/dev/null 2>&1", "lexicon-test", command]
		do {
			try process.run()
			process.waitUntilExit()
			return process.terminationStatus == 0
		} catch {
			return false
		}
	}

	private static func run(_ executable: URL, arguments: [String], in directory: URL) throws {
		let process = Process()
		let standardOutput = Pipe()
		let standardError = Pipe()
		process.executableURL = executable
		process.arguments = arguments
		process.currentDirectoryURL = directory
		process.standardOutput = standardOutput
		process.standardError = standardError
		try process.run()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else {
			let output = String(
				data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
				encoding: .utf8
			) ?? ""
			let error = String(
				data: standardError.fileHandleForReading.readDataToEndOfFile(),
				encoding: .utf8
			) ?? ""
			throw LexiconError(
				"\(executable.lastPathComponent) \(arguments.joined(separator: " ")) failed:\n\(error)\n\(output)"
			)
		}
	}
}
