//
// github.com/screensailor 2021
//

import Foundation
import _Collections

@LexiconActor
public struct Lemma: Hashable, CustomStringConvertible, Sendable {

	public typealias Description = String
	public typealias Children = SortedDictionary<Name, Lemma>
	public typealias Types = SortedDictionary<ID, Lemma>

	nonisolated public let id: ID
	nonisolated public let lexiconID: Lexicon.Identity
	nonisolated public let revision: Lexicon.Revision

	private let generation: Lexicon.Generation

	nonisolated internal init(id: ID, generation: Lexicon.Generation) {
		self.id = id
		self.lexiconID = generation.lexiconID
		self.revision = generation.revision
		self.generation = generation
	}

	nonisolated public var name: Name { id.name }
	nonisolated public var breadcrumbs: [Name] { id.components }

	public var isGraphNode: Bool {
		generation.rawNodes[id] != nil
	}

	public var node: Lexicon.Graph.Node {
		guard let resolution = generation.resolve(id) else {
			preconditionFailure("Generation is missing lemma '\(id)'.")
		}
		return generation.node(for: resolution)
	}

	public var graphNode: Lexicon.Graph.Node? {
		generation.rawNodes[id]
	}

	public var parent: Lemma? {
		id.parent.flatMap(generation.lemma)
	}

	public var ownChildren: Children {
		guard let resolution = generation.resolve(id) else {
			return [:]
		}
		var children: Children = [:]
		for name in generation.node(for: resolution).children.keys {
			let childID = id.appending(name)
			if generation.resolve(childID) != nil {
				children[name] = generation.lemma(childID)
			}
		}
		return children
	}

	public var children: Children {
		guard let resolution = generation.resolve(id) else {
			return [:]
		}
		var children: Children = [:]
		for name in generation.visibleChildNames(of: resolution) {
			let childID = id.appending(name)
			if generation.resolve(childID) != nil {
				children[name] = generation.lemma(childID)
			}
		}
		return children
	}

	public var protonym: Lemma? {
		guard
			let resolution = generation.resolve(id),
			let source = generation.directProtonym(of: resolution)
		else {
			return nil
		}
		return generation.lemma(source.requestedID)
	}

	public var sourceProtonym: Lemma? {
		guard
			let resolution = generation.resolve(id),
			generation.directProtonym(of: resolution) != nil,
			let source = generation.source(of: resolution),
			source.nodeID != id
		else {
			return nil
		}
		return generation.lemma(source.nodeID)
	}

	public var source: Lemma {
		guard
			let resolution = generation.resolve(id),
			let source = generation.source(of: resolution),
			source.nodeID != id
		else {
			return self
		}
		return generation.lemma(source.nodeID)
	}

	public var isSynonym: Bool {
		protonym != nil
	}

	public var ownType: Types {
		guard let resolution = generation.resolve(id) else {
			return [:]
		}
		var types: Types = [:]
		for type in generation.directTypeIDs(of: resolution) {
			types[type] = generation.lemma(type)
		}
		return types
	}

	public var type: Types {
		guard let resolution = generation.resolve(id) else {
			return [:]
		}
		var types: Types = [:]
		for type in generation.allTypeIDs(of: resolution) {
			types[type] = generation.lemma(type)
		}
		return types
	}

	public var defaultValue: Lexicon.Graph.Node.DefaultValue? {
		guard let resolution = generation.resolve(id) else {
			return nil
		}
		return generation.defaultValue(of: resolution)
	}

	public var graph: Lexicon.Graph {
		Lexicon.Graph(
			rootName: name,
			root: node,
			date: generation.document.date
		)
	}

	public var document: Lexicon.Document {
		generation.document
	}

	public subscript(descendant: Name...) -> Lemma? {
		self[descendant]
	}

	public subscript<Descendant>(descendant: Descendant) -> Lemma?
	where Descendant: Collection, Descendant.Element == Name {
		var current = self
		for name in descendant {
			guard let child = current.children[name] else {
				return nil
			}
			current = child
		}
		return current
	}

	public func `is`(_ type: Lemma) -> Bool {
		self.type[type.id] != nil
	}

	public func isAncestor(of other: Lemma) -> Bool {
		id.isAncestor(of: other.id)
	}

	public func isDescendant(of other: Lemma) -> Bool {
		id.isDescendant(of: other.id)
	}

	public func isInLineage(of other: Lemma) -> Bool {
		id.isInLineage(of: other.id)
	}

	public var lineage: AnySequence<Lemma> {
		AnySequence(sequence(first: self) { $0.parent })
	}

	public func regenerateNode() -> Lexicon.Graph.Node {
		node
	}

	nonisolated public static func == (lhs: Lemma, rhs: Lemma) -> Bool {
		lhs.lexiconID == rhs.lexiconID &&
		lhs.revision == rhs.revision &&
		lhs.id == rhs.id
	}

	nonisolated public func hash(into hasher: inout Hasher) {
		hasher.combine(lexiconID)
		hasher.combine(revision)
		hasher.combine(id)
	}

	nonisolated public var description: String {
		id.description
	}
}

public extension Lemma {

	nonisolated static func isValid(name: String) -> Bool {
		Name.isValid(name)
	}

	nonisolated static func isValid<S>(
		character: Character,
		appendingTo input: S
	) -> Bool where S: StringProtocol {
		Name.isValidPrefix(String(input) + String(character))
	}

	nonisolated var displayName: String {
		name.rawValue
			.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
			.replacingOccurrences(of: "_", with: " ")
	}
}

extension Lexicon {

	final class Generation: Sendable {

		struct Resolution: Hashable, Sendable {
			var requestedID: Lemma.ID
			var nodeID: Lemma.ID
		}

		enum Visit: Hashable {
			case resolve(Lemma.ID)
			case source(Lemma.ID)
			case child(Lemma.ID, Lemma.Name)
		}

		let lexiconID: Identity
		let revision: Revision
		let document: Document
		let rawNodes: [Lemma.ID: Graph.Node]

		init(lexiconID: Identity, revision: Revision, document: Document) {
			self.lexiconID = lexiconID
			self.revision = revision
			self.document = document
			var rawNodes: [Lemma.ID: Graph.Node] = [:]
			for (rootName, root) in document.roots {
				root.traverse(id: Lemma.ID(root: rootName)) { item in
					rawNodes[item.id] = item.node
				}
			}
			self.rawNodes = rawNodes
		}

		func lemma(_ id: Lemma.ID) -> Lemma {
			Lemma(id: id, generation: self)
		}

		func node(for resolution: Resolution) -> Graph.Node {
			guard let node = rawNodes[resolution.nodeID] else {
				preconditionFailure("Generation is missing source node '\(resolution.nodeID)'.")
			}
			return node
		}

		func resolve(_ id: Lemma.ID) -> Resolution? {
			var visiting: Set<Visit> = []
			return resolve(id, visiting: &visiting)
		}

		private func resolve(_ id: Lemma.ID, visiting: inout Set<Visit>) -> Resolution? {
			let visit = Visit.resolve(id)
			guard visiting.insert(visit).inserted else {
				return nil
			}
			defer { visiting.remove(visit) }

			let rootID = Lemma.ID(root: id.root)
			guard rawNodes[rootID] != nil else {
				return nil
			}
			var current = Resolution(requestedID: rootID, nodeID: rootID)
			for name in id.components.dropFirst() {
				guard let child = resolveChild(name, of: current, visiting: &visiting) else {
					return nil
				}
				current = child
			}
			return current
		}

		func source(of resolution: Resolution) -> Resolution? {
			var visiting: Set<Visit> = []
			return source(of: resolution, visiting: &visiting)
		}

		private func source(
			of resolution: Resolution,
			visiting: inout Set<Visit>
		) -> Resolution? {
			let visit = Visit.source(resolution.nodeID)
			guard visiting.insert(visit).inserted else {
				return nil
			}
			defer { visiting.remove(visit) }

			guard let target = directProtonym(of: resolution, visiting: &visiting) else {
				return resolution
			}
			return source(of: target, visiting: &visiting)
		}

		func directProtonym(of resolution: Resolution) -> Resolution? {
			var visiting: Set<Visit> = []
			return directProtonym(of: resolution, visiting: &visiting)
		}

		private func directProtonym(
			of resolution: Resolution,
			visiting: inout Set<Visit>
		) -> Resolution? {
			let node = node(for: resolution)
			guard let protonym = node.protonym, let parentID = resolution.nodeID.parent else {
				return nil
			}
			return resolve(parentID.appending(protonym), visiting: &visiting)
		}

		private func resolveChild(
			_ name: Lemma.Name,
			of parent: Resolution,
			visiting: inout Set<Visit>
		) -> Resolution? {
			let visit = Visit.child(parent.nodeID, name)
			guard visiting.insert(visit).inserted else {
				return nil
			}
			defer { visiting.remove(visit) }

			guard let effective = source(of: parent, visiting: &visiting) else {
				return nil
			}
			let node = node(for: effective)
			if node.children[name] != nil {
				return Resolution(
					requestedID: parent.requestedID.appending(name),
					nodeID: effective.nodeID.appending(name)
				)
			}
			for typeID in node.type.sorted() {
				guard
					let type = resolve(typeID, visiting: &visiting),
					let inherited = resolveChild(name, of: type, visiting: &visiting)
				else {
					continue
				}
				return Resolution(
					requestedID: parent.requestedID.appending(name),
					nodeID: inherited.nodeID
				)
			}
			return nil
		}

		func visibleChildNames(of resolution: Resolution) -> [Lemma.Name] {
			var visiting: Set<Visit> = []
			guard let effective = source(of: resolution, visiting: &visiting) else {
				return []
			}
			var names = Set(node(for: effective).children.keys)
			collectInheritedChildNames(of: effective, names: &names, visiting: &visiting)
			return names.sorted()
		}

		private func collectInheritedChildNames(
			of resolution: Resolution,
			names: inout Set<Lemma.Name>,
			visiting: inout Set<Visit>
		) {
			let resolvedNode = node(for: resolution)
			for typeID in resolvedNode.type.sorted() {
				guard
					let type = resolve(typeID, visiting: &visiting),
					let source = source(of: type, visiting: &visiting)
				else {
					continue
				}
				names.formUnion(self.node(for: source).children.keys)
				collectInheritedChildNames(of: source, names: &names, visiting: &visiting)
			}
		}

		func directTypeIDs(of resolution: Resolution) -> [Lemma.ID] {
			if rawNodes[resolution.requestedID] == nil {
				guard let source = source(of: resolution) else {
					return []
				}
				return [source.nodeID]
			}
			guard let source = source(of: resolution) else {
				return []
			}
			return node(for: source).type.sorted()
		}

		func allTypeIDs(of resolution: Resolution) -> [Lemma.ID] {
			guard let source = source(of: resolution) else {
				return []
			}
			if source.nodeID != resolution.nodeID {
				return allTypeIDs(of: source)
			}
			var result: Set<Lemma.ID> = [resolution.requestedID]
			if rawNodes[resolution.requestedID] == nil {
				result.insert(source.nodeID)
			}
			var visiting: Set<Lemma.ID> = []
			collectTypes(of: source, into: &result, visiting: &visiting)
			return result.sorted()
		}

		private func collectTypes(
			of resolution: Resolution,
			into result: inout Set<Lemma.ID>,
			visiting: inout Set<Lemma.ID>
		) {
			guard visiting.insert(resolution.nodeID).inserted else {
				return
			}
			defer { visiting.remove(resolution.nodeID) }
			for typeID in node(for: resolution).type.sorted() {
				result.insert(typeID)
				if let type = resolve(typeID), let source = source(of: type) {
					collectTypes(of: source, into: &result, visiting: &visiting)
				}
			}
		}

		func defaultValue(of resolution: Resolution) -> Graph.Node.DefaultValue? {
			var visiting: Set<Lemma.ID> = []
			return defaultValue(of: resolution, visiting: &visiting)
		}

		private func defaultValue(
			of resolution: Resolution,
			visiting: inout Set<Lemma.ID>
		) -> Graph.Node.DefaultValue? {
			guard visiting.insert(resolution.nodeID).inserted else {
				return nil
			}
			defer { visiting.remove(resolution.nodeID) }

			guard let source = source(of: resolution) else {
				return nil
			}
			if source.nodeID != resolution.nodeID {
				return defaultValue(of: source, visiting: &visiting)
			}
			let node = node(for: source)
			if let value = node.defaultValue {
				return value
			}
			for typeID in node.type.sorted() {
				if
					let type = resolve(typeID),
					let value = defaultValue(of: type, visiting: &visiting)
				{
					return value
				}
			}
			return nil
		}
	}
}
