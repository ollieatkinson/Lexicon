//
// github.com/screensailor 2022
//

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public extension UTType {
	static let lexicon = UTType(importedAs: "com.github.screensailor.lexicon")
	static let taskpaper = UTType(importedAs: "com.taskpaper.text")
}

public struct TaskPaper: Sendable {

	public struct Options: Sendable, Hashable {
		public var allowsPlainTextOutlines: Bool

		public init(allowsPlainTextOutlines: Bool = false) {
			self.allowsPlainTextOutlines = allowsPlainTextOutlines
		}

		public static let lexicon = Self()
		public static let plainTextOutline = Self(allowsPlainTextOutlines: true)
	}

	public struct ParseResult: Sendable {
		public var document: Lexicon.Document
		public var sourceMap: SourceMap
		public var diagnostics: [Lexicon.Diagnostic]

		public init(
			document: Lexicon.Document,
			sourceMap: SourceMap,
			diagnostics: [Lexicon.Diagnostic]
		) {
			self.document = document
			self.sourceMap = sourceMap
			self.diagnostics = diagnostics
		}
	}

	public struct ParseError: Error, Sendable, CustomStringConvertible, LocalizedError {
		public var diagnostics: [Lexicon.Diagnostic]

		public init(diagnostics: [Lexicon.Diagnostic]) {
			self.diagnostics = diagnostics
		}

		public var description: String {
			diagnostics.map(\.description).joined(separator: "\n")
		}

		public var errorDescription: String? {
			description
		}
	}

	public let string: String
	public let options: Options

	public init(_ string: String, options: Options = .lexicon) {
		self.string = string
		self.options = options
	}

	public init(_ utf8: Data, options: Options = .lexicon) throws {
		guard let string = String(data: utf8, encoding: .utf8) else {
			throw LexiconError("Data is not UTF-8")
		}
		self.init(string, options: options)
	}

	public func parse() -> ParseResult {
		var parser = Parser(string: string, options: options)
		return parser.parse()
	}

	public func decodeDocument() throws -> Lexicon.Document {
		let result = parse()
		let errors = result.diagnostics.filter { $0.severity == .error }
		guard errors.isEmpty else {
			throw ParseError(diagnostics: errors)
		}
		return result.document
	}

	public func decodeGraph(root: Lemma.Name) throws -> Lexicon.Graph {
		try decodeDocument().graph(root: root)
	}

	public func sourceMap() -> SourceMap {
		parse().sourceMap
	}
}

public extension TaskPaper {

	struct SourceMap: Sendable {
		public var lines: [Line]

		public init(lines: [Line]) {
			self.lines = lines
		}

		public var references: [Line] {
			lines.filter { $0.reference != nil }
		}

		public struct Line: Sendable, Hashable {
			public enum Content: Sendable, Hashable {
				case lemma(name: Lemma.Name)
				case type(reference: Lemma.ID)
				case protonym(reference: Lemma.RelativeID)
				case defaultReference(reference: Lemma.ID)
			}

			public var line: Int
			public var depth: Int
			public var nodeID: Lemma.ID?
			public var content: Content
			public var sourceRange: Lexicon.SourceRange
			public var referenceRange: Range<Int>?

			public var nodePath: String? {
				nodeID?.description
			}

			public var reference: String? {
				switch content {
					case .lemma:
						nil
					case .type(let reference):
						reference.description
					case .protonym(let reference):
						reference.description
					case .defaultReference(let reference):
						reference.description
				}
			}

			public init(
				line: Int,
				depth: Int,
				nodeID: Lemma.ID?,
				content: Content,
				sourceRange: Lexicon.SourceRange,
				referenceRange: Range<Int>? = nil
			) {
				self.line = line
				self.depth = depth
				self.nodeID = nodeID
				self.content = content
				self.sourceRange = sourceRange
				self.referenceRange = referenceRange
			}
		}
	}

	static func encode(
		_ node: Lexicon.Graph.Node,
		named name: Lemma.Name,
		date: Date = Lexicon.Document.unspecifiedDate
	) -> String {
		encode(Lexicon.Graph(rootName: name, root: node, date: date))
	}

	static func encode(_ graph: Lexicon.Graph) -> String {
		encode(Lexicon.Document(graph))
	}

	static func encode(_ document: Lexicon.Document) -> String {
		var lines: [String] = []

		for comment in document.comments {
			lines.append("# \(comment)")
		}
		for note in document.notes {
			lines.append("> \(note)")
		}
		for `import` in document.imports {
			lines.append("@ \(`import`.reference)")
		}

		for (rootName, root) in document.roots {
			root.traverse(id: Lemma.ID(root: rootName)) { item in
				let tabs = "\t" * (item.id.components.count - 1)
				lines.append("\(tabs)\(item.name):")
				for comment in item.node.comments {
					lines.append("\(tabs)# \(comment)")
				}
				for note in item.node.notes {
					lines.append("\(tabs)> \(note)")
				}
				if let defaultValue = item.node.defaultValue {
					lines.append("\(tabs)? \(encode(defaultValue))")
				}
				for connection in item.node.connections {
					lines.append("\(tabs)@ \(connection.reference)")
				}
				if let protonym = item.node.protonym {
					lines.append("\(tabs)= \(protonym)")
				} else {
					for type in item.node.type.sorted() {
						lines.append("\(tabs)+ \(type)")
					}
				}
			}
		}

		return lines.joined(separator: "\n")
	}
}

private extension TaskPaper {

	struct Parser {
		var string: String
		var options: Options
		var document = Lexicon.Document()
		var diagnostics: [Lexicon.Diagnostic] = []
		var sourceLines: [SourceMap.Line] = []
		var activeID: Lemma.ID?
		var hasSeenRoot = false

		mutating func parse() -> ParseResult {
			var utf16Offset = 0
			for (lineNumber, original) in string
				.split(separator: "\n", omittingEmptySubsequences: false)
				.map(String.init)
				.enumerated()
			{
				let text = original.hasSuffix("\r") ? String(original.dropLast()) : original
				parseLine(text, line: lineNumber, utf16Offset: utf16Offset)
				utf16Offset += original.utf16.count + 1
			}
			return ParseResult(
				document: document,
				sourceMap: SourceMap(lines: sourceLines),
				diagnostics: diagnostics
			)
		}

		mutating func parseLine(_ text: String, line: Int, utf16Offset: Int) {
			guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
				return
			}

			let depth = text.prefix(while: { $0 == "\t" }).count
			let contentStart = text.index(text.startIndex, offsetBy: depth)
			let rawContent = String(text[contentStart...])
			let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
			let contentColumn = depth
			let lineRange = range(
				line: line,
				column: contentColumn,
				length: rawContent.utf16.count,
				offset: utf16Offset
			)

			if rawContent.first?.isWhitespace == true {
				diagnostics.append(.init(
					code: .leadingSpaces,
					message: "Indentation must use tabs only",
					sourceRange: lineRange
				))
				return
			}

			if let metadata = metadata(content) {
				parseMetadata(
					metadata,
					depth: depth,
					line: line,
					utf16Offset: utf16Offset,
					contentColumn: contentColumn,
					lineRange: lineRange
				)
				return
			}

			if let rawName = lemmaName(content) {
				parseLemma(
					rawName,
					depth: depth,
					line: line,
					lineRange: lineRange
				)
				return
			}

			diagnostics.append(.init(
				code: .unknownLine,
				message: "Unrecognized TaskPaper line '\(content)'",
				sourceRange: lineRange
			))
		}

		mutating func parseLemma(
			_ rawName: String,
			depth: Int,
			line: Int,
			lineRange: Lexicon.SourceRange
		) {
			let name: Lemma.Name
			do {
				name = try Lemma.Name(validating: rawName)
			} catch {
				diagnostics.append(.init(
					code: .invalidName,
					message: "Invalid lemma name '\(rawName)'",
					sourceRange: lineRange
				))
				return
			}

			let id: Lemma.ID
			if depth == 0 {
				hasSeenRoot = true
				id = Lemma.ID(root: name)
				guard document.roots[name] == nil else {
					diagnostics.append(.init(
						code: .duplicateRoot,
						message: "Duplicate root lemma '\(name)'",
						path: id,
						sourceRange: lineRange
					))
					activeID = nil
					return
				}
				document.roots[name] = .init()
			} else {
				guard let activeID else {
					diagnostics.append(.init(
						code: .indentationJump,
						message: "A child lemma requires an active parent",
						sourceRange: lineRange
					))
					return
				}
				let activeDepth = activeID.components.count - 1
				guard depth <= activeDepth + 1 else {
					diagnostics.append(.init(
						code: .indentationJump,
						message: "Indentation may increase by at most one level",
						path: activeID,
						sourceRange: lineRange
					))
					return
				}
				guard depth <= activeID.components.count else {
					diagnostics.append(.init(
						code: .indentationJump,
						message: "Could not determine a parent at depth \(depth)",
						sourceRange: lineRange
					))
					return
				}
				let parentComponents = Array(activeID.components.prefix(depth))
				guard let parentID = try? Lemma.ID(components: parentComponents) else {
					diagnostics.append(.init(
						code: .indentationJump,
						message: "A child lemma requires an active root",
						sourceRange: lineRange
					))
					return
				}
				id = parentID.appending(name)
				do {
					try document.taskPaperUpdateNode(parentID) { parent in
						guard parent.children[name] == nil else {
							throw DuplicateChild()
						}
						parent.children[name] = .init()
					}
				} catch is DuplicateChild {
					diagnostics.append(.init(
						code: .duplicateChild,
						message: "Duplicate child lemma '\(name)'",
						path: id,
						sourceRange: lineRange
					))
					return
				} catch {
					diagnostics.append(.init(
						code: .indentationJump,
						message: error.localizedDescription,
						sourceRange: lineRange
					))
					return
				}
			}

			activeID = id
			sourceLines.append(.init(
				line: line,
				depth: depth,
				nodeID: id,
				content: .lemma(name: name),
				sourceRange: lineRange
			))
		}

		mutating func parseMetadata(
			_ metadata: Metadata,
			depth: Int,
			line: Int,
			utf16Offset: Int,
			contentColumn: Int,
			lineRange: Lexicon.SourceRange
		) {
			if !hasSeenRoot {
				guard depth == 0 else {
					diagnostics.append(.init(
						code: .misplacedMetadata,
						message: "Document metadata before the first root must not be indented",
						sourceRange: lineRange
					))
					return
				}
				switch metadata {
					case .comment(let value):
						document.comments.append(value)
					case .note(let value):
						document.notes.append(value)
					case .import(let reference):
						let value = Lexicon.Import(reference)
						guard !document.imports.contains(value) else {
							diagnostics.append(.init(
								code: .duplicateImport,
								message: "Duplicate document import '\(reference)'",
								reference: reference,
								sourceRange: lineRange
							))
							return
						}
						document.imports.append(value)
					case .type, .protonym, .defaultValue:
						diagnostics.append(.init(
							code: .misplacedMetadata,
							message: "Node metadata cannot appear before the first root",
							sourceRange: lineRange
						))
				}
				return
			}

			guard let currentID = activeID else {
				diagnostics.append(.init(
					code: .misplacedMetadata,
					message: "Metadata requires an active lemma",
					sourceRange: lineRange
				))
				return
			}
			let activeDepth = currentID.components.count - 1
			guard depth == activeDepth else {
				diagnostics.append(.init(
					code: .misplacedMetadata,
					message: "Metadata must use the active lemma's indentation depth",
					path: currentID,
					sourceRange: lineRange
				))
				return
			}
			let activeID = currentID

			do {
				switch metadata {
					case .comment(let value):
						try document.taskPaperUpdateNode(activeID) {
							$0.comments.append(value)
						}
					case .note(let value):
						try document.taskPaperUpdateNode(activeID) {
							$0.notes.append(value)
						}
					case .import(let reference):
						let value = Lexicon.Import(reference)
						try document.taskPaperUpdateNode(activeID) {
							guard !$0.connections.contains(value) else {
								throw DuplicateConnection()
							}
							$0.connections.append(value)
						}
					case .type(let rawReference):
						let reference = try Lemma.ID(parsing: rawReference)
						try document.taskPaperUpdateNode(activeID) {
							guard $0.type.insert(reference).inserted else {
								throw DuplicateType()
							}
						}
						appendReferenceLine(
							.type(reference: reference),
							rawReference: rawReference,
							symbol: "+",
							nodeID: activeID,
							depth: depth,
							line: line,
							utf16Offset: utf16Offset,
							contentColumn: contentColumn,
							lineRange: lineRange
						)
					case .protonym(let rawReference):
						let reference = try Lemma.RelativeID(parsing: rawReference)
						try document.taskPaperUpdateNode(activeID) {
							guard $0.protonym == nil else {
								throw DuplicateProtonym()
							}
							$0.protonym = reference
						}
						appendReferenceLine(
							.protonym(reference: reference),
							rawReference: rawReference,
							symbol: "=",
							nodeID: activeID,
							depth: depth,
							line: line,
							utf16Offset: utf16Offset,
							contentColumn: contentColumn,
							lineRange: lineRange
						)
					case .defaultValue(let rawValue):
						let parsed = try parseDefault(rawValue)
						try document.taskPaperUpdateNode(activeID) {
							guard $0.defaultValue == nil else {
								throw DuplicateDefault()
							}
							$0.defaultValue = parsed.value
						}
						if let reference = parsed.reference {
							appendReferenceLine(
								.defaultReference(reference: reference),
								rawReference: reference.description,
								symbol: "? @",
								nodeID: activeID,
								depth: depth,
								line: line,
								utf16Offset: utf16Offset,
								contentColumn: contentColumn,
								lineRange: lineRange
							)
						}
				}
			} catch is DuplicateType {
				appendDuplicate(.duplicateType, metadata: metadata, path: activeID, range: lineRange)
			} catch is DuplicateConnection {
				appendDuplicate(.duplicateConnection, metadata: metadata, path: activeID, range: lineRange)
			} catch is DuplicateProtonym {
				appendDuplicate(.duplicateProtonym, metadata: metadata, path: activeID, range: lineRange)
			} catch is DuplicateDefault {
				appendDuplicate(.duplicateDefault, metadata: metadata, path: activeID, range: lineRange)
			} catch {
				diagnostics.append(.init(
					code: .invalidReference,
					message: error.localizedDescription,
					path: activeID,
					sourceRange: lineRange
				))
			}
		}

		func lemmaName(_ content: String) -> String? {
			if options.allowsPlainTextOutlines {
				return content.hasSuffix(":")
					? String(content.dropLast()).trimmingCharacters(in: .whitespaces)
					: content
			}
			guard content.hasSuffix(":") else {
				return nil
			}
			return String(content.dropLast()).trimmingCharacters(in: .whitespaces)
		}

		func metadata(_ content: String) -> Metadata? {
			if content.hasPrefix("# ") {
				return .comment(String(content.dropFirst(2)))
			}
			if content.hasPrefix("> ") {
				return .note(String(content.dropFirst(2)))
			}
			if content.hasPrefix("@ ") {
				return .import(String(content.dropFirst(2)))
			}
			let symbol: Character
			if content.hasPrefix("+ ") {
				symbol = "+"
			} else if content.hasPrefix("= ") {
				symbol = "="
			} else if content.hasPrefix("? ") {
				symbol = "?"
			} else {
				return nil
			}
			let rawValue = content.dropFirst(2)
			guard rawValue.first?.isWhitespace != true else {
				return nil
			}
			let value = rawValue.trimmingCharacters(in: .whitespaces)
			switch symbol {
				case "+": return .type(value)
				case "=": return .protonym(value)
				case "?": return .defaultValue(value)
				default: return nil
			}
		}

		mutating func appendDuplicate(
			_ code: Lexicon.Diagnostic.Code,
			metadata: Metadata,
			path: Lemma.ID,
			range: Lexicon.SourceRange
		) {
			diagnostics.append(.init(
				code: code,
				message: "Duplicate \(metadata.kind) metadata",
				path: path,
				sourceRange: range
			))
		}

		mutating func appendReferenceLine(
			_ content: SourceMap.Line.Content,
			rawReference: String,
			symbol: String,
			nodeID: Lemma.ID,
			depth: Int,
			line: Int,
			utf16Offset: Int,
			contentColumn: Int,
			lineRange: Lexicon.SourceRange
		) {
			let prefixLength = symbol.utf16.count + 1
			let referenceStart = utf16Offset + contentColumn + prefixLength
			let referenceRange = referenceStart..<(referenceStart + rawReference.utf16.count)
			sourceLines.append(.init(
				line: line,
				depth: depth,
				nodeID: nodeID,
				content: content,
				sourceRange: lineRange,
				referenceRange: referenceRange
			))
		}

			func parseDefault(
				_ content: String
			) throws -> (value: Lexicon.Graph.Node.DefaultValue, reference: Lemma.ID?) {
				if content.hasPrefix("@") {
					guard
						content.hasPrefix("@ "),
						let first = content.dropFirst(2).first,
						!first.isWhitespace
					else {
						throw LexiconError(
							"A default reference must use exactly one space after '@'"
						)
					}
					let rawReference = String(content.dropFirst(2))
					let reference = try Lemma.ID(parsing: rawReference)
					return (.reference(reference), reference)
				}
			return (.literal(.parse(content)), nil)
		}

		func range(
			line: Int,
			column: Int,
			length: Int,
			offset: Int
		) -> Lexicon.SourceRange {
			.init(
				lowerBound: .init(
					line: line,
					utf16Column: column,
					utf16Offset: offset + column
				),
				upperBound: .init(
					line: line,
					utf16Column: column + length,
					utf16Offset: offset + column + length
				)
			)
		}

		enum Metadata {
			case comment(String)
			case note(String)
			case `import`(String)
			case type(String)
			case protonym(String)
			case defaultValue(String)

			var kind: String {
				switch self {
					case .comment: "comment"
					case .note: "note"
					case .import: "import"
					case .type: "type"
					case .protonym: "protonym"
					case .defaultValue: "default"
				}
			}
		}

		struct DuplicateChild: Error {}
		struct DuplicateType: Error {}
		struct DuplicateConnection: Error {}
		struct DuplicateProtonym: Error {}
		struct DuplicateDefault: Error {}
	}
}

private extension Lexicon.Document {

	mutating func taskPaperUpdateNode(
		_ id: Lemma.ID,
		_ body: (inout Lexicon.Graph.Node) throws -> Void
	) throws {
		guard var root = roots[id.root] else {
			throw LexiconError("Could not find root '\(id.root)'")
		}
		try root.taskPaperMutate(path: id.components.dropFirst(), body)
		roots[id.root] = root
	}
}

private extension Lexicon.Graph.Node {

	mutating func taskPaperMutate<Path>(
		path: Path,
		_ body: (inout Self) throws -> Void
	) throws where Path: Collection, Path.Element == Lemma.Name {
		guard let name = path.first else {
			try body(&self)
			return
		}
		guard var child = children[name] else {
			throw LexiconError("Could not find lemma path component '\(name)'")
		}
		try child.taskPaperMutate(path: path.dropFirst(), body)
		children[name] = child
	}
}

private extension TaskPaper {

	static func encode(_ value: Lexicon.Graph.Node.DefaultValue) -> String {
		switch value {
			case .reference(let id):
				return "@ \(id)"
			case .literal(let value):
				return encode(value)
		}
	}

	static func encode(_ value: JSONValue) -> String {
		guard
			let data = try? JSONSerialization.data(
				withJSONObject: value.jsonObject,
				options: [.fragmentsAllowed, .sortedKeys]
			),
			let string = String(data: data, encoding: .utf8)
		else {
			assertionFailure("JSONValue produced an invalid JSON object")
			return "null"
		}
		return string
	}
}
