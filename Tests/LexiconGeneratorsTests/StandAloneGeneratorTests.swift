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
				class L_root_inherited extends L implements I_root_inherited {
				  child!: L_root_type_child;
				}
				interface I_root_inherited extends I_root_type {
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
				class L_root_combined extends L implements I_root_combined {
				  one!: L_root_first_one;
				  two!: L_root_second_two;
				}
				interface I_root_combined extends I_root_first, I_root_second {
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
}
