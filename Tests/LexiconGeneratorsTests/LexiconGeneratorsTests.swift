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
		let json = try generator("JSON Classes & Mixins")
		let skos = try generator("SKOS JSON-LD")

		hope(swift.command) == "swift"
		hope(swiftStandAlone.command) == "swift-standalone"
		hope(kotlin.command) == "kotlin"
		hope(go.command) == "go"
		hope(typeScript.command) == "ts"
		hope(json.command) == "json"
		hope(skos.command) == "json-ld"
		hope(swift.utType.preferredFilenameExtension) == "swift"
		hope(swiftStandAlone.utType.preferredFilenameExtension) == "swift"
		hope(kotlin.utType.preferredFilenameExtension) == "kt"
		hope(go.utType.preferredFilenameExtension) == "go"
		hope(typeScript.utType.preferredFilenameExtension) == "ts"
		hope(json.utType.preferredFilenameExtension) == "json"
		hope(skos.utType.preferredFilenameExtension) == "jsonld"
	}

	func test_registry_finds_generators_by_command() throws {
		let generator = try LexiconSourceGenerators.all.find("swift-standalone").try()

		hope(generator.command) == "swift-standalone"
		hope(LexiconSourceGenerators.all.commandHelp) == "swift, swift-standalone, kotlin, go, ts, json, json-ld"
	}

	func test_json_registry_alias_matches_source_generator_registry() throws {
		hope(Lexicon.Graph.JSON.generators.keys.map(\.self)) == LexiconSourceGenerators.all.keys.map(\.self)
	}

	private func generator(_ name: String) throws -> LexiconSourceGenerator {
		try LexiconSourceGenerators.all[name].try()
	}
}
