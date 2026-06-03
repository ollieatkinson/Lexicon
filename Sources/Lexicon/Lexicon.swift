//
// github.com/screensailor 2021
//

import Foundation
#if canImport(Combine)
import Combine
#endif
import _Collections

@LexiconActor public final class Lexicon: ObservableObject {
	
	@Published public private(set) var graph: Graph
	@Published public private(set) var document: Document
	
	public internal(set) var dictionary: [Lemma.ID: Lemma] = [:]
	public internal(set) var roots: SortedDictionary<Lemma.Name, Lemma> = [:]
	
	private init(document: Document, graph: Graph) {
		self.document = document
		self.graph = graph
	}
}

public extension Lexicon {
	
	var root: Lemma {
		guard let root = roots[graph.root.name] else {
			preconditionFailure("Connected lexicon is missing root lemma '\(graph.root.name)'.")
		}
		return root
	}
	
	subscript(id: Lemma.ID) -> Lemma? {
		if let o = dictionary[id] {
			return o
		}
		guard let rootName = id.split(separator: ".", maxSplits: 1).first.map(String.init), let root = roots[rootName] else {
			return nil
		}
		return root[id.components(separatedBy: ".").dropFirst()]
	}
}

public extension Lexicon {
	
	static func from(_ graph: Graph) -> Lexicon {
		let document = Document(graph)
		let o = make(document: document, graph: graph)
		retainForDetachedLemmas(o)
		return o
	}

	static func from(_ document: Document, root name: Graph.Node.Name? = nil) throws -> Lexicon {
		let graph = try document.graph(root: name)
		let o = make(document: document, graph: graph)
		retainForDetachedLemmas(o)
		return o
	}

	#if EDITOR
	func reset(to graph: Graph) {
		var document = document
		document.date = graph.date
		document.roots[graph.root.name] = graph.root
		Lexicon.connect(lexicon: self, with: document, graph: graph)
	}

	func reset(to document: Document, root name: Graph.Node.Name? = nil) throws {
		try Lexicon.connect(lexicon: self, with: document, root: name)
	}
	#endif
}

extension Lexicon {

	static func temporary(from document: Document, root name: Graph.Node.Name? = nil) throws -> Lexicon {
		let graph = try document.graph(root: name)
		return make(document: document, graph: graph)
	}
}

private extension Lexicon {
	
	static var retainedLexicons: [Lexicon] = []

	static func retainForDetachedLemmas(_ lexicon: Lexicon) {
		retainedLexicons.append(lexicon)
	}

	static func make(document: Document, graph: Graph) -> Lexicon {
		let o = Lexicon(document: document, graph: graph)
		connect(lexicon: o, with: document, graph: graph)
		return o
	}
	
	static func connect(lexicon: Lexicon, with new: Graph? = nil) {
		let graph = new ?? lexicon.graph
		connect(lexicon: lexicon, with: Document(graph), graph: graph)
	}

	static func connect(lexicon: Lexicon, with document: Document, root name: Graph.Node.Name? = nil) throws {
		try connect(lexicon: lexicon, with: document, graph: document.graph(root: name))
	}

	static func connect(lexicon: Lexicon, with document: Document, graph: Graph) {
		lexicon.dictionary.removeAll(keepingCapacity: true)
		lexicon.roots.removeAll(keepingCapacity: true)
		for (name, root) in document.roots {
			lexicon.roots[name] = Lemma(name: name, node: root, parent: nil, lexicon: lexicon)
		}
		lexicon.document = document
		lexicon.graph = graph
	}

	func regenerateGraph(_ ƒ: ((Lemma) -> ())? = nil) -> Lexicon.Graph {
		Lexicon.Graph(
			root: root.regenerateNode(ƒ),
			date: .init()
		)
	}
}

#if EDITOR

// MARK: graph mutations

public extension Lexicon { // MARK: additive mutations
	
	func add(type: Lemma, to lemma: Lemma) -> Lemma? {
		
		guard
			lemma.isValid(newType: type),
			let path = lemma.graphPath
		else {
			return nil
		}
		
		var graph = graph
		graph.date = .init()
		
		graph[path].type.insert(type.id)
		
		reset(to: graph)
		return self[lemma.id] ?? root
	}

	func make(child new: Graph, to lemma: Lemma) -> Lemma? {
		
		let name = new.root.name

		guard
			lemma.isValid(newChildName: name),
			let path = lemma.graphPath
		else {
			return nil
		}
		
		var new = new
		if
			let protonym = new.root.protonym,
			!lemma.resolves(protonym.components(separatedBy: "."))
		{
			new.root.protonym = nil
		}
		
		let id = "\(lemma.id).\(name)"
		
		var graph = graph
		graph.date = .init()
		
		graph[path].children[name] = new.root
		reset(to: graph)
		
		guard let child = self[id] else {
			return root
		}

		graph[path].children[name] = child.regenerateNode { o in
			o.removeInvalidSynonymChildren()
			o.removeUnavailableOwnTypes(in: self)
		}
		
		reset(to: graph)
		return self[id] ?? root
	}
	
	func make(child name: Lemma.Name, to lemma: Lemma) -> Lemma? {
		
		guard
			lemma.isValid(newChildName: name),
			let path = lemma.graphPath
		else {
			return nil
		}
		
		var graph = graph
		graph.date = .init()

		graph[path].make(child: name)

		reset(to: graph)
		return self["\(lemma.id).\(name)"] ?? root
	}
}

public extension Lexicon { // MARK: non-additive mutations
	
	func delete(_ lemma: Lemma, alwaysReturningParent: Bool = false) -> Lemma? {
		
		guard
			lemma.isGraphNode,
			let parent = lemma.parent
		else {
			return nil
		}
		
		let children = Array(parent.ownChildren.keys)
		
		let sibling: Lemma.Name? = children
			.firstIndex(of: lemma.name)
			.flatMap { i in
				switch (i, children.count > 1) {
					case (_, false): return nil
					case (0, _):     return children[1]
					case (_, _):     return children[i - 1]
				}
		}
		
		parent.removeOwnChild(named: lemma.name)

		root.graphTraversal(.depthFirst) { o in
			o.removeOwnTypesReferencing(lemma)
		}

		let graph = regenerateGraph { o in
			o.removeInvalidSynonymChildren()
		}

		reset(to: graph)
		
		guard let parent = self[parent.id] else {
			return root
		}
		guard !alwaysReturningParent, let name = sibling, let sibling = parent[name] else {
			return parent
		}
		return sibling
	}
	
	func remove(type: Lemma, from lemma: Lemma) -> Lemma? {

		guard let path = lemma.graphPath else {
			return nil
		}
		
		var graph = graph

		guard graph[path].type.remove(type.id) != nil else {
			return nil
		}

		reset(to: graph)
		
		graph = regenerateGraph { o in
			o.removeInvalidSynonymChildren()
		}
		
		reset(to: graph)
		return self[lemma.id] ?? root
	}
	
	func removeProtonym(of lemma: Lemma) -> Lemma? {
		
		guard
			lemma.node.protonym != nil,
			let path = lemma.graphPath
		else {
			return nil
		}
		
		var graph = graph
		graph.date = .init()

		graph[path].protonym = nil
		
		reset(to: graph)
		return self[lemma.id] ?? root
	}

	func rename(_ lemma: Lemma, to name: Lemma.Name) -> Lemma? {
		
		guard lemma.isValid(newName: name) else {
			return nil
		}
		
		let old = (
			id: lemma.id,
			name: lemma.name
		)
		
		let new = (
			id: String(lemma.id.dropLast(old.name.count)) + name,
			name: name
		)
		
		lemma.node.name = new.name
		lemma.parent?.ownChildren.removeValue(forKey: old.name)
		lemma.parent?.ownChildren[new.name] = lemma

		root.graphTraversal(.breadthFirst) { o in
			if
				let protonym = o.protonym?.unwrapped,
				protonym.lineageReferences(type: lemma)
			{
				o.node.protonym = protonym.lineage
					.prefix(while: { $0 != o.parent })
					.reversed()
					.map(\.node.name)
					.joined(separator: ".")
			}
			else {
				for id in o.node.type where id.starts(with: old.id) {
					o.node.type.remove(id)
					o.node.type.insert(
						new.id + String(id.dropFirst(old.id.count))
					)
				}
			}
		}

		let graph = regenerateGraph()
		
		reset(to: graph)
		return self[new.id] ?? root
	}

	func set(protonym: Lemma, of lemma: Lemma) -> Lemma? {
		
		guard let protonym = lemma.validated(protonym: protonym) else {
			return nil
		}
		
		let id = lemma.id
		
		guard let parent = delete(lemma, alwaysReturningParent: true) else {
			return nil
		}
		
		guard let path = parent.graphPath else {
			return parent
		}

		var graph = graph
		graph.date = .init()

		let node = Lexicon.Graph.Node(name: lemma.name, protonym: protonym)
		
		graph[path].children[node.name] = node
				
		reset(to: graph)
		
		return self[id] ?? root
	}
}

private extension Lemma {

	func removeOwnChild(named name: Name) {
		ownChildren.removeValue(forKey: name)
		children = lazy_children()
	}

	func removeInvalidSynonymChildren() {
		for name in Array(ownChildren.keys) {
			guard
				let protonym = ownChildren[name]?.node.protonym,
				!resolves(protonym.components(separatedBy: "."))
			else {
				continue
			}
			ownChildren.removeValue(forKey: name)
		}
	}

	func removeUnavailableOwnTypes(in lexicon: Lexicon) {
		for id in Array(node.type) where lexicon[id] == nil {
			node.type.remove(id)
		}
	}

	func removeOwnTypesReferencing(_ deleted: Lemma) {
		var didRemove = false
		for (id, type) in Array(ownType) where type.unwrapped.isInLineage(of: deleted) {
			ownType.removeValue(forKey: id)
			node.type.remove(id)
			didRemove = true
		}
		if didRemove {
			children = lazy_children()
		}
	}

	func lineageReferences(type: Lemma) -> Bool {
		lineage.contains { $0.is(type) }
	}

	func resolves<Components>(_ components: Components) -> Bool where Components: Collection, Components.Element == Name {
		var visited: Set<ID> = []
		return resolve(components[...], visited: &visited) != nil
	}

	func resolve<Components>(_ components: Components, visited: inout Set<ID>) -> Lemma? where Components: Collection, Components.Element == Name {
		guard let name = components.first else {
			return self
		}
		guard visited.insert(id).inserted else {
			return nil
		}
		let remaining = components.dropFirst()
		if let child = ownChildren[name]?.source {
			return child.resolve(remaining, visited: &visited)
		}
		for (_, type) in ownType {
			var branchVisited = visited
			if let child = type.unwrapped.resolve([name], visited: &branchVisited)?.source {
				return child.resolve(remaining, visited: &branchVisited)
			}
		}
		return nil
	}
}

#endif
