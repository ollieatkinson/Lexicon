//
// github.com/screensailor 2021
//

import Foundation
#if canImport(Combine)
import Combine
#endif
import _Collections

@LexiconActor
public final class Lexicon: ObservableObject {

	nonisolated public static let version = "0.3.0"

	public struct Identity: Hashable, Codable, Sendable, CustomStringConvertible {
		public let rawValue: UUID

		public init(rawValue: UUID = UUID()) {
			self.rawValue = rawValue
		}

		public var description: String {
			rawValue.uuidString
		}
	}

	public struct Revision: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
		public let rawValue: UInt64

		public init(rawValue: UInt64) {
			self.rawValue = rawValue
		}

		public static let initial = Self(rawValue: 0)

		public var description: String {
			String(rawValue)
		}

		public static func < (lhs: Self, rhs: Self) -> Bool {
			lhs.rawValue < rhs.rawValue
		}

		func next() throws -> Self {
			guard rawValue < UInt64.max else {
				throw LexiconError("Lexicon revision overflow")
			}
			return Self(rawValue: rawValue + 1)
		}
	}

	nonisolated public let identity: Identity

	@Published public private(set) var document: Document
	@Published public private(set) var selectedRoot: Lemma.Name
	@Published public private(set) var revision: Revision

	private var generation: Generation

	public init(
		document: Document,
		selectedRoot: Lemma.Name
	) throws {
		let document = try document.validated()
		guard document.roots[selectedRoot] != nil else {
			throw LexiconError("The document does not declare selected root '\(selectedRoot)'")
		}
		let identity = Identity()
		let revision = Revision.initial
		self.identity = identity
		self.document = document
		self.selectedRoot = selectedRoot
		self.revision = revision
		self.generation = Generation(
			lexiconID: identity,
			revision: revision,
			document: document
		)
	}

	public convenience init(graph: Graph) throws {
		try self.init(document: Document(graph), selectedRoot: graph.rootName)
	}

	public var graph: Graph {
		guard let graph = try? document.graph(root: selectedRoot) else {
			preconditionFailure("The selected root '\(selectedRoot)' is missing.")
		}
		return graph
	}

	public var root: Lemma {
		generation.lemma(Lemma.ID(root: selectedRoot))
	}

	public var roots: SortedDictionary<Lemma.Name, Lemma> {
		var roots: SortedDictionary<Lemma.Name, Lemma> = [:]
		for rootName in document.roots.keys {
			roots[rootName] = generation.lemma(Lemma.ID(root: rootName))
		}
		return roots
	}

	public subscript(id: Lemma.ID) -> Lemma? {
		guard generation.resolve(id) != nil else {
			return nil
		}
		return generation.lemma(id)
	}

	public func selectRoot(_ root: Lemma.Name) throws {
		guard document.roots[root] != nil else {
			throw LexiconError("The document does not declare root '\(root)'")
		}
		selectedRoot = root
	}

	public func replaceDocument(
		with document: Document,
		selectedRoot: Lemma.Name
	) throws {
		let document = try document.validated()
		guard document.roots[selectedRoot] != nil else {
			throw LexiconError("The document does not declare selected root '\(selectedRoot)'")
		}
		try commit(document, selectedRoot: selectedRoot)
	}

	func requireCurrent(_ lemma: Lemma) throws {
		guard lemma.lexiconID == identity else {
			throw LexiconError("Lemma '\(lemma.id)' belongs to a different lexicon")
		}
		guard lemma.revision == revision else {
			throw LexiconError(
				"Lemma '\(lemma.id)' is stale (revision \(lemma.revision), current \(revision))"
			)
		}
		guard generation.resolve(lemma.id) != nil else {
			throw LexiconError("Lemma '\(lemma.id)' is not present in the current generation")
		}
	}

	func commit(_ document: Document, selectedRoot: Lemma.Name) throws {
		let revision = try revision.next()
		let generation = Generation(
			lexiconID: identity,
			revision: revision,
			document: document
		)
		self.document = document
		self.selectedRoot = selectedRoot
		self.revision = revision
		self.generation = generation
	}
}

extension Lexicon {

	static func temporary(from document: Document, root name: Lemma.Name) throws -> Lexicon {
		try Lexicon(document: document, selectedRoot: name)
	}
}

#if EDITOR
public extension Lexicon {

	@discardableResult
	func addChild(
		named name: Lemma.Name,
		to parent: Lemma
	) throws -> Lemma {
		try requireCurrent(parent)
		var editor = try Document.Editor(document)
		let id = try editor.addChild(named: name, to: parent.id)
		try commit(editor.document, selectedRoot: selectedRoot)
		return try committedLemma(id)
	}

	@discardableResult
	func insert(
		_ graph: Graph,
		under parent: Lemma
	) throws -> Lemma {
		try requireCurrent(parent)
		var editor = try Document.Editor(document)
		let id = try editor.insert(graph, under: parent.id)
		try commit(editor.document, selectedRoot: selectedRoot)
		return try committedLemma(id)
	}

	@discardableResult
	func rename(
		_ lemma: Lemma,
		to name: Lemma.Name
	) throws -> Lemma {
		try requireCurrent(lemma)
		var editor = try Document.Editor(document)
		let id = try editor.rename(lemma.id, to: name)
		let root = lemma.id.parent == nil && selectedRoot == lemma.id.root
			? name
			: selectedRoot
		try commit(editor.document, selectedRoot: root)
		return try committedLemma(id)
	}

	@discardableResult
	func move(
		_ lemma: Lemma,
		under parent: Lemma
	) throws -> Lemma {
		try requireCurrent(lemma)
		try requireCurrent(parent)
		var editor = try Document.Editor(document)
		let id = try editor.move(lemma.id, under: parent.id)
		let root = editor.document.roots[selectedRoot] == nil
			? try firstRoot(in: editor.document)
			: selectedRoot
		try commit(editor.document, selectedRoot: root)
		return try committedLemma(id)
	}

	func delete(_ lemma: Lemma) throws {
		try requireCurrent(lemma)
		var editor = try Document.Editor(document)
		try editor.delete(lemma.id)
		let root = editor.document.roots[selectedRoot] == nil
			? try firstRoot(in: editor.document)
			: selectedRoot
		try commit(editor.document, selectedRoot: root)
	}

	@discardableResult
	func addType(
		_ type: Lemma,
		to lemma: Lemma
	) throws -> Lemma {
		try requireCurrent(type)
		try requireCurrent(lemma)
		var editor = try Document.Editor(document)
		try editor.addType(type.id, to: lemma.id)
		try commit(editor.document, selectedRoot: selectedRoot)
		return try committedLemma(lemma.id)
	}

	@discardableResult
	func removeType(
		_ type: Lemma,
		from lemma: Lemma
	) throws -> Lemma {
		try requireCurrent(type)
		try requireCurrent(lemma)
		var editor = try Document.Editor(document)
		try editor.removeType(type.id, from: lemma.id)
		try commit(editor.document, selectedRoot: selectedRoot)
		return try committedLemma(lemma.id)
	}

	@discardableResult
	func setProtonym(
		_ protonym: Lemma,
		of lemma: Lemma
	) throws -> Lemma {
		try requireCurrent(protonym)
		try requireCurrent(lemma)
		var editor = try Document.Editor(document)
		try editor.setProtonym(protonym.id, of: lemma.id)
		try commit(editor.document, selectedRoot: selectedRoot)
		return try committedLemma(lemma.id)
	}

	@discardableResult
	func clearProtonym(of lemma: Lemma) throws -> Lemma {
		try requireCurrent(lemma)
		var editor = try Document.Editor(document)
		try editor.clearProtonym(of: lemma.id)
		try commit(editor.document, selectedRoot: selectedRoot)
		return try committedLemma(lemma.id)
	}
}

private extension Lexicon {

	func committedLemma(_ id: Lemma.ID) throws -> Lemma {
		guard let lemma = self[id] else {
			throw LexiconError("Committed generation is missing lemma '\(id)'")
		}
		return lemma
	}

	func firstRoot(in document: Document) throws -> Lemma.Name {
		guard document.roots.count == 1, let root = document.roots.keys.first else {
			throw LexiconError(
				"An edit that removes the selected root requires exactly one unambiguous replacement root"
			)
		}
		return root
	}
}
#endif
