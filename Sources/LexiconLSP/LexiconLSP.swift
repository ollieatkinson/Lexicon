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

	public init(lexiconText: String, baseURL: URL? = nil) throws {
		var document = try TaskPaper(lexiconText).decodeDocument()
		if let baseURL {
			document = try Self.composed(document, baseURL: baseURL)
		}
		self.init(document: document)
	}

	public init(lexiconURL: URL) throws {
		let document = try TaskPaper(Data(contentsOf: lexiconURL)).decodeDocument()
		self.init(document: try Self.composed(
			document,
			baseURL: lexiconURL.deletingLastPathComponent()
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

	private static func composed(_ document: Lexicon.Document, baseURL: URL) throws -> Lexicon.Document {
		let plan = try document.composed(resolving: FileLexiconImportResolver(baseURL: baseURL))
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
			root.traverse(name: name) { item in
				let parentComponents = item.id.split(separator: ".").dropLast()
				let parentID = parentComponents.isEmpty ? nil : parentComponents.joined(separator: ".")
				entries[item.id] = Entry(id: item.id, parentID: parentID, node: item.node)
			}
			roots.append(name)
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
			guard let protonymSourceID = resolvedSourceID(protonym, fromParentOf: sourceID) else {
				return [:]
			}
			guard active.contains(protonymSourceID) == false else {
				return [:]
			}
			return childSources(for: protonymSourceID, active: active.union([protonymSourceID]))
		}

		var children = Dictionary(
			uniqueKeysWithValues: entry.node.children.keys.map { name in
				(name, "\(sourceID).\(name)")
			}
		)
		for typeID in entry.node.type.sorted() where active.contains(typeID) == false {
			for (name, childSourceID) in childSources(for: typeID, active: active.union([typeID]))
				where children[name] == nil
			{
				children[name] = childSourceID
			}
		}
		return children
	}

	private func resolvedSourceID(_ reference: String, fromParentOf sourceID: String) -> String? {
		if let sourceID = self.sourceID(forPath: reference) {
			return sourceID
		}
		guard let parentID = entries[sourceID]?.parentID else {
			return self.sourceID(forPath: reference)
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

	public func diagnostics(in text: String) -> [LexiconDiagnostic] {
		(
			Self.matches(in: text, pattern: #"\bl\("([^"\\]*(?:\\.[^"\\]*)*)"\)"#)
				+ Self.matches(in: text, pattern: #"\bl!\(([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\)"#)
				+ Self.lexiconDocumentReferences(in: text, index: index)
		)
			.filter { !$0.path.hasSuffix(".") }
			.filter { !index.contains($0.path) }
			.map {
				LexiconDiagnostic(
					range: $0.range,
					message: "Unknown Lexicon path '\($0.path)'."
				)
			}
	}

	private static func matches(in text: String, pattern: String) -> [(path: String, range: LexiconTextRange)] {
		let regex = try! NSRegularExpression(pattern: pattern)
		let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
		return regex.matches(in: text, range: nsRange).compactMap { match in
			guard
				let pathRange = Range(match.range(at: 1), in: text)
			else {
				return nil
			}
			return (
				path: String(text[pathRange]),
				range: LexiconTextRange(
					start: text.position(forUTF16Offset: match.range(at: 1).location),
					end: text.position(forUTF16Offset: match.range(at: 1).location + match.range(at: 1).length)
				)
			)
		}
	}

	private static func lexiconDocumentReferences(in text: String, index: LexiconPathIndex) -> [(path: String, range: LexiconTextRange)] {
		var references: [(path: String, range: LexiconTextRange)] = []
		var path: [String] = []
		var utf16Offset = 0
		for lineText in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
			defer { utf16Offset += lineText.utf16.count + 1 }
			let depth = lineText.prefix { $0 == "\t" }.count
			let trimmed = lineText.trimmingCharacters(in: .whitespaces)
			if let name = Self.lemmaName(in: trimmed) {
				if depth < path.count {
					path.removeLast(path.count - depth)
				}
				path.append(name)
				continue
			}
			let marker: String
			guard trimmed.hasPrefix("+ ") || trimmed.hasPrefix("= ") else {
				continue
			}
			marker = String(trimmed.prefix(2))
			let rawReference = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
			guard rawReference.isEmpty == false else {
				continue
			}
			let resolved = marker == "= "
				? Self.resolvedProtonym(rawReference, from: path, index: index)
				: rawReference
			let leadingWhitespace = lineText.prefix { $0 == "\t" || $0 == " " }.utf16.count
			let startOffset = utf16Offset + leadingWhitespace + marker.utf16.count
			references.append((
				path: resolved,
				range: LexiconTextRange(
					start: text.position(forUTF16Offset: startOffset),
					end: text.position(forUTF16Offset: startOffset + rawReference.utf16.count)
				)
			))
		}
		return references
	}

	fileprivate static func lemmaName(in trimmedLine: String) -> String? {
		let name = trimmedLine.hasSuffix(":") ? String(trimmedLine.dropLast()) : trimmedLine
		return Lemma.isValid(name: name) ? name : nil
	}

	private static func resolvedProtonym(_ reference: String, from path: [String], index: LexiconPathIndex) -> String {
		if index.contains(reference) {
			return reference
		}
		let parent = path.dropLast().joined(separator: ".")
		return parent.isEmpty ? reference : "\(parent).\(reference)"
	}
}

private struct CompletionContext {
	var prefixes: [String]
	var replacementRange: LexiconTextRange

	init?(text: String, line: Int, character: Int) {
		guard let cursor = text.index(line: line, utf16Character: character) else {
			return nil
		}
		let beforeCursor = String(text[..<cursor])
		let context: (rawPrefix: String, prefixes: [String])?
		if let range = beforeCursor.range(of: #"l(""#, options: .backwards) {
			let value = String(beforeCursor[range.upperBound...])
			context = value.contains("\n") || value.contains("\"") ? nil : (value, [value])
		} else if let range = beforeCursor.range(of: "l!(", options: .backwards) {
			let value = String(beforeCursor[range.upperBound...])
			context = value.contains("\n") || value.contains(")") ? nil : (value, [value])
		} else {
			context = Self.lexiconReferenceContext(beforeCursor)
		}
		guard let context else {
			return nil
		}
		self.prefixes = context.prefixes
		let partial = LexiconPathIndex.split(context.rawPrefix).partial
		let start = text.index(cursor, offsetByUTF16: -partial.utf16.count) ?? cursor
		self.replacementRange = LexiconTextRange(
			start: text.position(for: start),
			end: text.position(for: cursor)
		)
	}

	static func lexiconReferenceContext(_ beforeCursor: String) -> (rawPrefix: String, prefixes: [String])? {
		let lines = beforeCursor.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let line = lines.last ?? ""
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		if trimmed.hasPrefix("+ ") {
			let rawPrefix = String(trimmed.dropFirst(2))
			return (rawPrefix, [rawPrefix])
		}
		guard trimmed.hasPrefix("= ") else {
			return nil
		}
		let rawPrefix = String(trimmed.dropFirst(2))
		let parent = parentLexiconPath(lines: lines.dropLast())
		guard parent.isEmpty == false else {
			return (rawPrefix, [rawPrefix])
		}
		return (rawPrefix, [rawPrefix, "\(parent).\(rawPrefix)"])
	}

	static func parentLexiconPath<S: Sequence>(lines: S) -> String where S.Element == String {
		var path: [String] = []
		for lineText in lines {
			let depth = lineText.prefix { $0 == "\t" }.count
			let trimmed = lineText.trimmingCharacters(in: .whitespaces)
			guard let name = LexiconLSPService.lemmaName(in: trimmed) else {
				continue
			}
			if depth < path.count {
				path.removeLast(path.count - depth)
			}
			path.append(name)
		}
		return path.dropLast().joined(separator: ".")
	}
}

private extension String {
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
