//
// github.com/screensailor 2026
//
import Testing
@_exported import Lexicon
@_exported import LexiconGenerators

@Suite

struct LexiconGeneratorsTests {

	@Test
	func test_registry_exposes_generator_values() throws {

		let swift = try generator("Swift")
		let swiftStandAlone = try generator("Swift Stand-Alone")
		let kotlin = try generator("Kotlin Stand-Alone")
		let go = try generator("Go Stand-Alone")
		let typeScript = try generator("TypeScript Stand-Alone")
		let json = try generator("JSON Classes & Mixins")
		let skos = try generator("SKOS JSON-LD")

		#expect(swift.command == "swift")
		#expect(swiftStandAlone.command == "swift-standalone")
		#expect(kotlin.command == "kotlin")
		#expect(go.command == "go")
		#expect(typeScript.command == "ts")
		#expect(json.command == "json")
		#expect(skos.command == "json-ld")
		#expect(swift.utType.preferredFilenameExtension == "swift")
		#expect(swiftStandAlone.utType.preferredFilenameExtension == "swift")
		#expect(kotlin.utType.preferredFilenameExtension == "kt")
		#expect(go.utType.preferredFilenameExtension == "go")
		#expect(typeScript.utType.preferredFilenameExtension == "ts")
		#expect(json.utType.preferredFilenameExtension == "json")
		#expect(skos.utType.preferredFilenameExtension == "jsonld")
	}

	@Test
	func test_registry_finds_generators_by_command() throws {
		let generator = try LexiconSourceGenerators.all.find("swift-standalone").try()

		#expect(generator.command == "swift-standalone")
		#expect(LexiconSourceGenerators.all.commandHelp == "swift, swift-standalone, kotlin, go, ts, json, json-ld")
	}

	@Test
	func test_json_registry_alias_matches_source_generator_registry() throws {
		#expect(Lexicon.Graph.JSON.generators.keys.map(\.self) == LexiconSourceGenerators.all.keys.map(\.self))
	}

	private func generator(_ name: String) throws -> LexiconSourceGenerator {
		try LexiconSourceGenerators.all[name].try()
	}
}
