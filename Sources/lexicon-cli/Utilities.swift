import ArgumentParser
import Foundation
import Lexicon
import LexiconGenerators

enum AgentJSON {

	static func print<Value: Encodable>(_ value: Value) throws {
		try Swift.print(string(value, pretty: true))
	}

	static func printLine<Value: Encodable>(_ value: Value) throws {
		try Swift.print(string(value, pretty: false))
	}

	static func string<Value: Encodable>(_ value: Value, pretty: Bool) throws -> String {
		let encoder = JSONClasses.Encoder()
		encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
		let data = try encoder.encode(value)
		guard let string = String(data: data, encoding: .utf8) else {
			throw ValidationError("Could not encode JSON output as UTF-8.")
		}
		return string
	}
}

enum AgentWriter {

	static func write(_ document: Lexicon.Document, output: URL?) throws {
		try write(TaskPaper.encode(document), output: output)
	}

	static func write(_ string: String, output: URL?) throws {
		if let output {
			try Data(string.utf8).write(to: output, options: .atomic)
			try AgentJSON.print(WriteOutput(written: true, output: output.path))
		} else {
			print(string)
		}
	}

}

struct ValidationInput {
	var document: Lexicon.Document
	var diagnostics: [AgentDiagnostic]
}

extension Lexicon.Search.Mode {

	init(agentArgument value: String) throws {
		var mode: Self = []
		for component in value.split(whereSeparator: { $0 == "," || $0 == "+" }) {
			switch component.trimmingCharacters(in: .whitespacesAndNewlines) {
				case "hybrid":
					mode.formUnion(.hybrid)
				case "token":
					mode.formUnion(.token)
				case "lexical":
					mode.formUnion(.lexical)
				case "semantic":
					mode.formUnion(.semantic)
				default:
					throw ValidationError("Unknown search mode '\(value)'. Expected hybrid, token, lexical, semantic, or a comma-separated combination.")
			}
		}
		guard mode.isEmpty == false else {
			throw ValidationError("Search mode cannot be empty.")
		}
		self = mode
	}
}

extension Lexicon.Search.Scope {

	init(agentArgument value: String) throws {
		guard let scope = Self(rawValue: value) else {
			throw ValidationError("Unknown search scope '\(value)'. Expected own, live, or full.")
		}
		self = scope
	}
}

extension URL: @retroactive ExpressibleByArgument {

	public init?(argument: String) {
		if
			let remoteURL = URL(string: argument),
			["http", "https"].contains(remoteURL.scheme?.lowercased()),
			remoteURL.host != nil
		{
			self = remoteURL
		} else {
			self.init(fileURLWithPath: argument)
		}
	}

	func lexiconDocument() throws -> Lexicon.Document {
		try TaskPaper(Data(contentsOf: self)).decodeDocument()
	}

	func validationInput(sourceOnly: Bool) throws -> ValidationInput {
		let result = try TaskPaper(Data(contentsOf: self)).parse()
		var diagnostics = result.diagnostics.map(AgentDiagnostic.init)
		guard
			!sourceOnly,
			!result.diagnostics.contains(where: { $0.severity == .error })
		else {
			return ValidationInput(
				document: result.document,
				diagnostics: diagnostics
			)
		}

			let plan = try result.document.composed(resolving: FileLexiconImportResolver(
				baseURL: deletingLastPathComponent(),
				rootURL: self
			))
		diagnostics.append(contentsOf: plan.conflicts.map(AgentDiagnostic.init))
		return ValidationInput(document: plan.document, diagnostics: diagnostics)
	}

	func composedLexiconDocument() throws -> Lexicon.Document {
			let plan = try lexiconDocument().composed(resolving: FileLexiconImportResolver(
				baseURL: deletingLastPathComponent(),
				rootURL: self
			))
		guard plan.conflicts.isEmpty else {
			throw ValidationError(plan.conflicts.map(\.description).joined(separator: "\n"))
		}
		return plan.document
	}
}

extension String {

	func shellWords() throws -> [String] {
		var words: [String] = []
		var current = ""
		var quote: Character?
		var isEscaped = false

		for character in self {
			if isEscaped {
				current.append(character)
				isEscaped = false
				continue
			}
			if character == "\\" {
				isEscaped = true
				continue
			}
			if let activeQuote = quote {
				if character == activeQuote {
					quote = nil
				} else {
					current.append(character)
				}
				continue
			}
			if character == "\"" || character == "'" {
				quote = character
			} else if character.isWhitespace {
				if current.isNotEmpty {
					words.append(current)
					current.removeAll()
				}
			} else {
				current.append(character)
			}
		}
		if quote != nil {
			throw ValidationError("Unterminated quote in command.")
		}
		if current.isNotEmpty {
			words.append(current)
		}
		return words
	}
}

extension Array where Element == String {

	func required(_ index: Int, named name: String) throws -> String {
		guard indices.contains(index) else {
			throw ValidationError("Missing required argument: \(name)")
		}
		return self[index]
	}
}
