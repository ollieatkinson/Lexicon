//
// github.com/screensailor 2026
//

import Foundation
import Lexicon

public struct LexiconPosition: Codable, Equatable, Sendable {
	public var line: Int
	public var character: Int

	public init(line: Int, character: Int) {
		self.line = line
		self.character = character
	}
}

public struct LexiconTextRange: Codable, Equatable, Sendable {
	public var start: LexiconPosition
	public var end: LexiconPosition

	public init(start: LexiconPosition, end: LexiconPosition) {
		self.start = start
		self.end = end
	}
}

public struct LexiconCompletion: Equatable, Sendable {
	public var label: String
	public var insertText: String

	public init(label: String, insertText: String) {
		self.label = label
		self.insertText = insertText
	}
}

public struct LexiconCompletionResult: Equatable, Sendable {
	public var range: LexiconTextRange
	public var items: [LexiconCompletion]

	public init(range: LexiconTextRange, items: [LexiconCompletion]) {
		self.range = range
		self.items = items
	}
}

public struct LexiconDiagnostic: Equatable, Sendable {
	public var range: LexiconTextRange
	public var message: String

	public init(range: LexiconTextRange, message: String) {
		self.range = range
		self.message = message
	}
}

public struct LexiconPathIndex: Sendable {
	public var paths: Set<String>

	public init(paths: Set<String> = []) {
		self.paths = paths
	}

	public init(
		lexiconText: String,
		baseURL: URL? = nil,
		resolver: (any LexiconImportResolving)? = nil
	) throws {
		var document = TaskPaper(lexiconText).parse().document
		if let resolver {
			document = try Self.composed(document, resolving: resolver)
			} else if let baseURL {
				document = try Self.composed(document, resolving: FileLexiconImportResolver(baseURL: baseURL))
		}
		self.init(document: document)
	}

	public init(lexiconURL: URL, resolver: (any LexiconImportResolving)? = nil) throws {
		let document = try TaskPaper(Data(contentsOf: lexiconURL)).decodeDocument()
			self.init(document: try Self.composed(
				document,
				resolving: resolver ?? FileLexiconImportResolver(
					baseURL: lexiconURL.deletingLastPathComponent(),
					rootURL: lexiconURL
				)
			))
	}

	public init(document: Lexicon.Document) {
		self.paths = LexiconPathGraph(document: document).paths()
	}

	public func contains(_ path: String) -> Bool {
		paths.contains(path)
	}

	public func completions(for prefix: String) -> [LexiconCompletion] {
		let pathPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
		let split = Self.split(pathPrefix)
		let segments = paths.compactMap { path -> String? in
			guard path.hasPrefix(split.base) else {
				return nil
			}
			let remaining = path.dropFirst(split.base.count)
			guard let segment = remaining.split(separator: ".", maxSplits: 1).first else {
				return nil
			}
			let value = String(segment)
			return value.hasPrefix(split.partial) ? value : nil
		}
		return Array(Set(segments))
			.sorted()
			.map { LexiconCompletion(label: $0, insertText: $0) }
	}

	static func split(_ prefix: String) -> (base: String, partial: String) {
		guard let dot = prefix.lastIndex(of: ".") else {
			return ("", prefix)
		}
		let base = String(prefix[...dot])
		let partial = String(prefix[prefix.index(after: dot)...])
		return (base, partial)
	}

	private static func composed(
		_ document: Lexicon.Document,
		resolving resolver: any LexiconImportResolving
	) throws -> Lexicon.Document {
		let plan = try document.composed(resolving: resolver)
		guard plan.conflicts.isEmpty else {
			throw LexiconPathIndexError.compositionConflicts(plan.conflicts.map(\.description))
		}
		return plan.document
	}
}

public enum LexiconPathIndexError: Error, CustomStringConvertible, Sendable {
	case compositionConflicts([String])

	public var description: String {
		switch self {
		case .compositionConflicts(let conflicts):
			conflicts.joined(separator: "\n")
		}
	}
}

private struct LexiconPathGraph {
	private struct Entry {
		var id: String
		var parentID: String?
		var node: Lexicon.Graph.Node
	}

	private var entries: [String: Entry] = [:]
	private var roots: [String] = []

	init(document: Lexicon.Document) {
		for (name, root) in document.roots {
			root.traverse(id: Lemma.ID(root: name)) { item in
				let id = item.id.description
				entries[id] = Entry(
					id: id,
					parentID: item.id.parent?.description,
					node: item.node
				)
			}
			roots.append(name.description)
		}
	}

	func paths() -> Set<String> {
		var paths: Set<String> = []
		for root in roots.sorted() {
			emit(path: root, sourceID: root, active: [], into: &paths)
		}
		return paths
	}

	private func emit(path: String, sourceID: String, active: Set<String>, into paths: inout Set<String>) {
		paths.insert(path)
		guard active.contains(sourceID) == false else {
			return
		}
		let active = active.union([sourceID])
		for (name, childSourceID) in childSources(for: sourceID, active: [sourceID]).sorted(by: { $0.key < $1.key }) {
			emit(path: "\(path).\(name)", sourceID: childSourceID, active: active, into: &paths)
		}
	}

	private func childSources(for sourceID: String, active: Set<String>) -> [String: String] {
		guard let entry = entries[sourceID] else {
			return [:]
		}
		if let protonym = entry.node.protonym {
			guard let protonymSourceID = resolvedSourceID(
				protonym.description,
				fromParentOf: sourceID
			) else {
				return [:]
			}
			guard active.contains(protonymSourceID) == false else {
				return [:]
			}
			return childSources(for: protonymSourceID, active: active.union([protonymSourceID]))
		}

		var children = Dictionary(
			uniqueKeysWithValues: entry.node.children.keys.map { name in
				(name.description, "\(sourceID).\(name)")
			}
		)
		for typedID in entry.node.type.sorted() {
			let typeID = typedID.description
			guard active.contains(typeID) == false else {
				continue
			}
			for (name, childSourceID) in childSources(
				for: typeID,
				active: active.union([typeID])
			)
				where children[name] == nil
			{
				children[name] = childSourceID
			}
		}
		return children
	}

	private func resolvedSourceID(_ reference: String, fromParentOf sourceID: String) -> String? {
		guard let parentID = entries[sourceID]?.parentID else {
			return nil
		}
		return self.sourceID(forPath: "\(parentID).\(reference)")
	}

	private func sourceID(forPath path: String) -> String? {
		let components = path.split(separator: ".").map(String.init)
		guard let root = components.first, entries[root] != nil else {
			return nil
		}
		var sourceID = root
		var active: Set<String> = []
		for name in components.dropFirst() {
			guard active.contains(sourceID) == false else {
				return nil
			}
			active.insert(sourceID)
			guard let next = childSources(for: sourceID, active: [sourceID])[name] else {
				return nil
			}
			sourceID = next
		}
		return sourceID
	}
}

public struct LexiconLSPService: Sendable {
	public var index: LexiconPathIndex

	public init(index: LexiconPathIndex) {
		self.index = index
	}

	public func completion(in text: String, line: Int, character: Int) -> LexiconCompletionResult? {
		guard let context = CompletionContext(text: text, line: line, character: character) else {
			return nil
		}
		let itemsByLabel = context.prefixes
			.flatMap { index.completions(for: $0) }
			.reduce(into: [:]) { (items: inout [String: LexiconCompletion], item) in
				items[item.label] = item
			}
		let items = itemsByLabel.values.sorted { $0.label < $1.label }
		return LexiconCompletionResult(range: context.replacementRange, items: items)
	}

	public func diagnostics(in text: String, lexiconDocument: Bool = false) -> [LexiconDiagnostic] {
		let pathDiagnostics = (
			CodeReferenceSyntax.all.flatMap { $0.references(text) }
				+ (lexiconDocument ? LexiconDocumentSyntax.references(in: text, index: index) : [])
		)
			.filter { !$0.path.hasSuffix(".") }
			.filter { !index.contains($0.path) }
			.map {
				LexiconDiagnostic(
					range: $0.range,
					message: "Unknown Lexicon path '\($0.path)'."
				)
			}
		return lexiconDocument
			? LexiconDocumentSyntax.syntaxDiagnostics(in: text) + pathDiagnostics
			: pathDiagnostics
	}
}

extension String {
	func index(line targetLine: Int, utf16Character targetCharacter: Int) -> Index? {
		var line = 0
		var character = 0
		var index = startIndex
		while index < endIndex {
			if line == targetLine, character == targetCharacter {
				return index
			}
			let next = self.index(after: index)
			if self[index] == "\n" {
				line += 1
				character = 0
			} else {
				character += self[index..<next].utf16.count
			}
			index = next
		}
		return line == targetLine && character == targetCharacter ? endIndex : nil
	}

	func index(_ index: Index, offsetByUTF16 offset: Int) -> Index? {
		let currentOffset = utf16.distance(from: utf16.startIndex, to: index.samePosition(in: utf16)!)
		let nextOffset = currentOffset + offset
		guard nextOffset >= 0, nextOffset <= utf16.count else {
			return nil
		}
		let utf16Index = utf16.index(utf16.startIndex, offsetBy: nextOffset)
		return Index(utf16Index, within: self)
	}

	func position(for index: Index) -> LexiconPosition {
		let offset = utf16.distance(from: utf16.startIndex, to: index.samePosition(in: utf16)!)
		return position(forUTF16Offset: offset)
	}

	func position(forUTF16Offset offset: Int) -> LexiconPosition {
		var line = 0
		var character = 0
		for codeUnit in utf16.prefix(max(0, min(offset, utf16.count))) {
			if codeUnit == 10 {
				line += 1
				character = 0
			} else {
				character += 1
			}
		}
		return LexiconPosition(line: line, character: character)
	}
}
