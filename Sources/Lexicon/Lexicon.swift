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
	
	private var lemma: Lemma! // TODO: serioulsy?
	
	private init(document: Document, graph: Graph) {
		self.document = document
		self.graph = graph
	}
}

public extension Lexicon {
	
	var root: Lemma { lemma! }
	
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
		all.append(o) // TODO: hard rethink
		return o
	}

	static func from(_ document: Document, root name: Graph.Node.Name? = nil) throws -> Lexicon {
		let graph = try document.graph(root: name)
		let o = make(document: document, graph: graph)
		all.append(o) // TODO: hard rethink
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
	
	static var all: [Lexicon] = []

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
		lexicon.lemma = lexicon.roots[graph.root.name]!
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

// TODO: performance
// TODO: throwing

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
		new.root.protonym = nil // TODO: allow != nil
		
		let id = "\(lemma.id).\(name)"
		
		var graph = graph
		graph.date = .init()
		
		graph[path].children[name] = new.root
		reset(to: graph)
		
		guard let child = self[id] else {
			return root
		}

		graph[path].children[name] = child.regenerateNode { o in
			for (name, child) in o.ownChildren {
				if
					let protonym = child.node.protonym,
					o[protonym.components(separatedBy: ".")] == nil
				{
					o.ownChildren.removeValue(forKey: name)
				}
			}
			for id in o.node.type where self[id] == nil {
				o.node.type.remove(name)
			}
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
		
		parent.ownChildren.removeValue(forKey: lemma.name)
		
		root.graphTraversal(.depthFirst) { o in
			for (name, type) in o.ownType where type.unwrapped.isInLineage(of: lemma) {
				o.ownType.removeValue(forKey: name) // TODO: don't like
				o.children = o.lazy_children() // TODO: don't like
				o.node.type.remove(name)
			}
		}

		let graph = regenerateGraph { o in
			for (name, child) in o.ownChildren {
				if
					let protonym = child.node.protonym,
					o[protonym.components(separatedBy: ".")] == nil
				{
					o.ownChildren.removeValue(forKey: name)
				}
			}
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
			for (name, child) in o.ownChildren {
				if
					let protonym = child.node.protonym,
					o[protonym.components(separatedBy: ".")] == nil
				{
					o.ownChildren.removeValue(forKey: name)
				}
			}
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
		
		reset(to: graph) // TODO: reconsider, as it is not strictly necessary
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
				protonym.lineage.contains(where: { $0.is(lemma) }) // TODO: measure performance without this
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

#endif
