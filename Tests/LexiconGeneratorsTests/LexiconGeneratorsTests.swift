//
// github.com/screensailor 2026
//

@_exported import Hope
@_exported import Lexicon
@_exported import LexiconGenerators

final class LexiconGeneratorsTests: Hopes {

	func test_registry_exposes_generator_values() throws {

		let swift = try generator("Swift")
		let swiftStandAlone = try generator("Swift Stand-Alone")
		let kotlin = try generator("Kotlin Stand-Alone")
		let go = try generator("Go Stand-Alone")
		let typeScript = try generator("TypeScript Stand-Alone")

		hope(swift.command) == "swift"
		hope(swiftStandAlone.command) == "swift-standalone"
		hope(kotlin.command) == "kotlin"
		hope(go.command) == "go"
		hope(typeScript.command) == "ts"
		hope(swift.utType.preferredFilenameExtension) == "swift"
		hope(swiftStandAlone.utType.preferredFilenameExtension) == "swift"
		hope(kotlin.utType.preferredFilenameExtension) == "kt"
		hope(go.utType.preferredFilenameExtension) == "go"
		hope(typeScript.utType.preferredFilenameExtension) == "ts"
	}

	private func generator(_ name: String) throws -> LexiconSourceGenerator {
		try Lexicon.Graph.JSON.generators[name].try()
	}
}
