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
			try Data(string.utf8).write(to: output)
			try AgentJSON.print(WriteOutput(written: true, output: output.path))
		} else {
			print(string)
		}
	}
}

extension Lexicon.SearchMode {

	init(agentArgument value: String) throws {
		guard let mode = Self(rawValue: value) else {
			throw ValidationError("Unknown search mode '\(value)'. Expected hybrid, token, lexical, or semantic.")
		}
		self = mode
	}
}

extension Lexicon.SearchScope {

	init(agentArgument value: String) throws {
		guard let scope = Self(rawValue: value) else {
			throw ValidationError("Unknown search scope '\(value)'. Expected own, live, or full.")
		}
		self = scope
	}
}

extension URL: @retroactive ExpressibleByArgument {

	public init?(argument: String) {
		if argument.hasPrefix("http") {
			self.init(string: argument)
		} else {
			self.init(fileURLWithPath: argument)
		}
	}

	func lexiconDocument() throws -> Lexicon.Document {
		try TaskPaper(Data(contentsOf: self)).decodeDocument()
	}

	func composedLexiconDocument() throws -> Lexicon.Document {
		let plan = try lexiconDocument().composed(resolving: FileLexiconImportResolver(
			baseURL: deletingLastPathComponent()
		))
		guard plan.conflicts.isEmpty else {
			throw ValidationError(plan.conflicts.map(\.description).joined(separator: "\n"))
		}
		return plan.document
	}
}

extension Lexicon.Document.Roots {

	mutating func mutate(
		_ key: Lexicon.Graph.Node.Name,
		body: (inout Lexicon.Graph.Node) throws -> Void
	) throws {
		guard var value = self[key] else {
			throw ValidationError("Could not find lemma: \(key)")
		}
		try body(&value)
		self[key] = value
	}
}

extension Set where Element == String {

	func resolves(_ reference: String, fromParentOf id: String) -> Bool {
		if contains(reference) {
			return true
		}
		let components = id.pathComponents
		guard components.count > 1 else {
			return false
		}
		let parent = components.dropLast().joined(separator: ".")
		return contains("\(parent).\(reference)")
	}

	func resolvesRelative(_ reference: String, fromParentOf id: String) -> Bool {
		reference.resolvedRelative(fromParentOf: id, in: self) != nil
	}
}

extension String {

	var pathComponents: [String] {
		components(separatedBy: ".").filter { !$0.isEmpty }
	}

	func isSameOrDescendant(of ancestor: String) -> Bool {
		self == ancestor || hasPrefix("\(ancestor).")
	}

	func resolved(fromParentOf id: String, in index: Set<String>) -> String? {
		if index.contains(self) {
			return self
		}
		let components = id.pathComponents
		guard components.count > 1 else {
			return nil
		}
		let parent = components.dropLast().joined(separator: ".")
		let relative = "\(parent).\(self)"
		return index.contains(relative) ? relative : nil
	}

	func resolvedRelative(fromParentOf id: String, in index: Set<String>) -> String? {
		let components = id.pathComponents
		guard components.count > 1 else {
			return nil
		}
		let parent = components.dropLast().joined(separator: ".")
		let relative = "\(parent).\(self)"
		return index.contains(relative) ? relative : nil
	}

	func rewritingReference(from oldID: String, to newID: String, at id: String, index: Set<String>) -> String {
		if isSameOrDescendant(of: oldID) {
			return newID + dropFirst(oldID.count)
		}
		guard let resolved = resolved(fromParentOf: id, in: index), resolved.isSameOrDescendant(of: oldID) else {
			return self
		}
		return newID + resolved.dropFirst(oldID.count)
	}

	func relativeReference(fromParentOf id: String) -> String {
		let components = id.pathComponents
		guard components.count > 1 else {
			return self
		}
		let parent = components.dropLast().joined(separator: ".")
		if self == parent {
			return ""
		}
		let prefix = "\(parent)."
		guard hasPrefix(prefix) else {
			return self
		}
		return String(dropFirst(prefix.count))
	}

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
