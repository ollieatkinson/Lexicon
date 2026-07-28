import ArgumentParser
import Foundation
import Lexicon
import LexiconGenerators

@main
struct CodeGeneratorCommand: AsyncParsableCommand {

	static let configuration = CommandConfiguration(
		commandName: "lexicon-generate",
		abstract: "A utility for generating code from lexicon documents.",
		version: Lexicon.version
	)

	@Argument(help: "File path or URL to the lexicon")
	var input: URL

	@Option(
		name: .shortAndLong,
		help: "Output path excluding extension, if not specified the same directory and name of the lexicon will be used"
	)
	var output: URL?

	@Option(help: "Root lemma to generate. Required when the composed document declares multiple roots.")
	var root: String?

	@Option(
		name: .shortAndLong,
		help:
		"""
		Types of code to generate. Comma separated.

		Generators:
			\(LexiconSourceGenerators.all.commandHelp)

		Example:
			--type swift,kotlin
		"""
	)
	var type: [String]

	@Flag(name: .shortAndLong)
	var quiet: Bool = false

	@Option(help: "Package name to use for generated Go source.")
	var goPackage: String = "lexicon"

	@Option(help: "Prefix to use for generated class names in Swift, Kotlin, and TypeScript source.")
	var classPrefix: String = StandAloneTypePrefixes.default.classPrefix

	@Option(help: "Prefix to use for generated protocol/interface names in Swift, Kotlin, and TypeScript source.")
	var protocolPrefix: String = StandAloneTypePrefixes.default.protocolPrefix

	private var isLogging: Bool { !quiet }
	private var typePrefixes: StandAloneTypePrefixes {
		.init(class: classPrefix, protocol: protocolPrefix)
	}

	mutating func run() async throws {
		let name = input.deletingPathExtension().lastPathComponent
		if isLogging {
			print("\(name) lexicon")
		}
			let plan = try TaskPaper(Data(contentsOf: input))
				.decodeDocument()
				.composed(resolving: FileLexiconImportResolver(
					baseURL: input.deletingLastPathComponent(),
					rootURL: input
				))
		guard plan.conflicts.isEmpty else {
			throw LexiconError(plan.conflicts.map(\.description).joined(separator: "\n"))
		}
		let selectedRoot: Lemma.Name
		if let root {
			selectedRoot = try Lemma.Name(validating: root)
			guard plan.document.roots[selectedRoot] != nil else {
				throw ValidationError("The composed document does not declare root '\(selectedRoot)'.")
			}
		} else {
			guard plan.document.roots.count == 1, let onlyRoot = plan.document.roots.keys.first else {
				throw ValidationError(
					plan.document.roots.isEmpty
						? "The composed document does not declare a root lemma."
						: "The composed document declares multiple roots; provide --root."
				)
			}
			selectedRoot = onlyRoot
		}
		let lexicon = try await Lexicon(document: plan.document, selectedRoot: selectedRoot)
		let json = await lexicon.json()
		let code = try type.map { command -> (URL, Data) in
			guard let generator = LexiconSourceGenerators.all.find(command) else {
				throw ValidationError(
					"Unknown generator '\(command)'. Expected one of: \(LexiconSourceGenerators.all.commandHelp)."
				)
			}
			guard let `extension` = generator.utType.preferredFilenameExtension else {
				throw ValidationError(
					"Generator '\(command)' does not declare a preferred filename extension."
				)
			}
			let data: Data
			switch command {
				case GoStandAloneGenerator.command:
					data = Data(try GoStandAloneGenerator.generateSource(json, packageName: goPackage).utf8)
				case SwiftLexiconGenerator.command:
					data = Data(try SwiftLexiconGenerator.generateSource(json, prefixes: typePrefixes).utf8)
				case SwiftStandAloneGenerator.command:
					data = Data(try SwiftStandAloneGenerator.generateSource(json, prefixes: typePrefixes).utf8)
				case KotlinStandAloneGenerator.command:
					data = Data(try KotlinStandAloneGenerator.generateSource(json, prefixes: typePrefixes).utf8)
				case TypeScriptStandAloneGenerator.command:
					data = Data(try TypeScriptStandAloneGenerator.generateSource(json, prefixes: typePrefixes).utf8)
				default:
					data = try generator.generate(json)
			}
			return (
				file: output?.appendingPathExtension(`extension`)
					?? input.deletingLastPathComponent()
						.appendingPathComponent(name)
						.appendingPathExtension(`extension`),
				data: data
			)
		}
		let duplicateOutputs = Dictionary(grouping: code) { $0.0.standardizedFileURL }
			.filter { $0.value.count > 1 }
			.keys
			.sorted { $0.path < $1.path }
		guard duplicateOutputs.isEmpty else {
			throw ValidationError(
				"Multiple generators target the same output: \(duplicateOutputs.map(\.path).joined(separator: ", "))."
			)
		}
		for (file, data) in code {
			if isLogging { print(file.path) }
			try data.write(to: file, options: .atomic)
		}
	}
}

#if compiler(>=6.0)
extension URL: @retroactive ExpressibleByArgument {

	public init?(argument: String) {
		if argument.hasPrefix("http") {
			self.init(string: argument)
		} else {
			self.init(fileURLWithPath: argument)
		}
	}
}
#else
extension URL: ExpressibleByArgument {

	public init?(argument: String) {
		if argument.hasPrefix("http") {
			self.init(string: argument)
		} else {
			self.init(fileURLWithPath: argument)
		}
	}
}
#endif

#if compiler(>=6.0)
extension Array: @retroactive ExpressibleByArgument where Element: ExpressibleByArgument {

	public init?(argument: String) {
		self = argument.split(separator: ",").compactMap { substring in
			Element(argument: String(substring))
		}
	}
}
#else
extension Array: ExpressibleByArgument where Element: ExpressibleByArgument {

	public init?(argument: String) {
		self = argument.split(separator: ",").compactMap { substring in
			Element(argument: String(substring))
		}
	}
}
#endif
