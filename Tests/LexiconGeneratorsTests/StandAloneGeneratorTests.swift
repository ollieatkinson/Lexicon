//
// github.com/screensailor 2026
//

import Foundation

final class SwiftStandAloneGeneratorTests: Hopes {

	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try SwiftStandAloneGenerator.generate(json).string()

		try hope(code) == "test.swift".file().string()
	}

	func test_generated_swift_fixture() throws {
		hope(test.one.more.time.one.more.time(\.id)) == "test.one.more.time.one.more.time"

		hope(test.two.bad) == test.two.no.good
		hope(test.two.bad(\.id)) == "test.two.no.good"
	}
}

final class KotlinStandAloneGeneratorTests: Hopes {

	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try KotlinStandAloneGenerator.generate(json).string()

		try hope(code) == "test.kt".file().string()
	}
}

final class TypeScriptStandAloneGeneratorTests: Hopes {

	func test_generator() async throws {
		var json = try await "test".taskpaper().lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let code = try TypeScriptStandAloneGenerator.generate(json).string()

		try hope(code) == "test.ts".file().string()
	}
}
