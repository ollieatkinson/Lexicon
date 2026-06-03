import ArgumentParser
import Foundation
import Lexicon
import LexiconGenerators

@main
struct CodeGeneratorCommand: AsyncParsableCommand {

	static let configuration = CommandConfiguration(
		commandName: "lexicon-generate",
		abstract: "A utility for generating code from lexicon documents.",
		version: "1.0.0"
	)

	@Argument(help: "File path or URL to the lexicon")
	var input: URL

	@Option(
		name: .shortAndLong,
		help: "Output path excluding extension, if not specified the same directory and name of the lexicon will be used"
	)
	var output: URL?

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

	private var isLogging: Bool { !quiet }

	mutating func run() async throws {
		let name = String(input.lastPathComponent.split(separator: ".")[0])
		if isLogging {
			print("\(name) lexicon")
		}
		let plan = try TaskPaper(Data(contentsOf: input))
			.decodeDocument()
			.composed(resolving: FileLexiconImportResolver(baseURL: input.deletingLastPathComponent()))
		guard plan.conflicts.isEmpty else {
			throw LexiconError(plan.conflicts.map(\.description).joined(separator: "\n"))
		}
		let lexicon = try await Lexicon.from(plan.document)
		let json = await lexicon.json()
		let code = try type.map { command -> (URL, Data) in
			guard let generator = LexiconSourceGenerators.all.find(command) else {
				fatalError("Unable to find a generator for \(command)")
			}
			guard let `extension` = generator.utType.preferredFilenameExtension else {
				fatalError("\(command) does not have a valid uniform type identifier: \(generator.utType)")
			}
			let data = command == GoStandAloneGenerator.command
				? Data(try GoStandAloneGenerator.generateSource(json, packageName: goPackage).utf8)
				: try generator.generate(json)
			return (
				file: output?.appendingPathExtension(`extension`)
					?? input.deletingLastPathComponent()
						.appendingPathComponent(name)
						.appendingPathExtension(`extension`),
				data: data
			)
		}
		for (file, data) in code {
			if isLogging { print(file.path) }
			try data.write(to: file)
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
