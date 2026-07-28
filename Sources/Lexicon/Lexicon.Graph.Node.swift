//
// github.com/screensailor 2021
//

import _Collections

public extension Lexicon.Graph.Node {
	typealias ID = Lemma.ID
	typealias Name = Lemma.Name
	typealias Protonym = Lemma.RelativeID
	typealias Children = SortedDictionary<Name, Lexicon.Graph.Node>
}

public extension Lexicon.Graph {

	struct Node: Sendable, Equatable {

		public var type: Set<ID>
		public var protonym: Protonym?
		public var defaultValue: DefaultValue?
		public var connections: [Lexicon.Import]
		public var notes: [String]
		public var comments: [String]
		public var children: Children

		public init(
			children: [Name: Node] = [:],
			type: Set<ID> = [],
			protonym: Protonym? = nil,
			defaultValue: DefaultValue? = nil,
			connections: [Lexicon.Import] = [],
			notes: [String] = [],
			comments: [String] = []
		) {
			self.type = type
			self.protonym = protonym
			self.defaultValue = defaultValue
			self.connections = connections
			self.notes = notes
			self.comments = comments
			self.children = Children(children)
		}

		@discardableResult
		public mutating func make(child name: Name) -> Node {
			if let child = children[name] {
				return child
			}
			let child = Node()
			children[name] = child
			return child
		}
	}
}

internal extension Lexicon.Graph.Node {

	/// - note: This is not an optional subscript.
	subscript(_ name: Name) -> Lexicon.Graph.Node {
		get {
			guard let node = children[name] else {
				preconditionFailure("Missing graph child '\(name)'.")
			}
			return node
		}
		set { children[name] = newValue }
	}
}

public extension Lexicon.Graph.Node {

	func traverse(
		id: ID,
		yield: ((id: ID, name: Name, node: Lexicon.Graph.Node)) -> Void
	) {
		yield((id, id.name, self))
		for (name, child) in children {
			child.traverse(id: id.appending(name), yield: yield)
		}
	}
}
