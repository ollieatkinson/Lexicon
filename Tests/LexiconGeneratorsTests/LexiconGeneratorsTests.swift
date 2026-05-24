//
// github.com/screensailor 2026
//

@_exported import Hope
@_exported import Lexicon
@_exported import LexiconGenerators

final class LexiconGeneratorsTests: Hopes {

	func test_registry_exposes_generator_values() throws {

		let swift = try generator("Swift Stand-Alone")
		let kotlin = try generator("Kotlin Stand-Alone")
		let typeScript = try generator("TypeScript Stand-Alone")

		hope(swift.command) == "swift-standalone"
		hope(kotlin.command) == "kotlin"
		hope(typeScript.command) == "ts"
		hope(swift.utType.preferredFilenameExtension) == "swift"
		hope(kotlin.utType.preferredFilenameExtension) == "kt"
		hope(typeScript.utType.preferredFilenameExtension) == "ts"
	}

	private func generator(_ name: String) throws -> LexiconSourceGenerator {
		try Lexicon.Graph.JSON.generators[name].try()
	}
}
