//
// github.com/screensailor 2021
//

import _Collections

public extension Lexicon.Graph.Node {
	typealias ID = Lemma.ID
	typealias Name = String
	typealias Protonym = String
	typealias Children = SortedDictionary<Name, Lexicon.Graph.Node>
}

public extension Lexicon.Graph {

	struct Node: Sendable {

		public var name: Name
		public var type: Set<ID>
		public var protonym: Protonym?
		public var defaultValue: DefaultValue?
		public var connections: [Lexicon.Import]
		public var notes: [String]
		public var comments: [String]
		public var children: Children

		public init(
			name: Name,
			protonym: Protonym,
			defaultValue: DefaultValue? = nil,
			connections: [Lexicon.Import] = [],
			notes: [String] = [],
			comments: [String] = []
		) {
			self.name = name
			self.type = []
			self.protonym = protonym
			self.defaultValue = defaultValue
			self.connections = connections
			self.notes = notes
			self.comments = comments
			self.children = [:]
		}

		public init(
			name: Name,
			children: [Name: Node] = [:],
			type: Set<ID> = [],
			defaultValue: DefaultValue? = nil,
			connections: [Lexicon.Import] = [],
			notes: [String] = [],
			comments: [String] = []
		) {
			self.name = name
			self.type = type
			self.protonym = nil
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
			let child = Node(name: name)
			children[name] = child
			return child
		}
	}
}

internal extension Lexicon.Graph.Node {

	/// - note: This is not an optional subscript!
	subscript(child: String) -> Lexicon.Graph.Node {
		get {
			guard let node = children[child] else {
				preconditionFailure("Missing graph child '\(child)' under '\(name)'.")
			}
			return node
		}
		set { children[child] = newValue }
	}
}

extension Lexicon.Graph.Node: CustomStringConvertible {

	public var description: String {
		name
	}
}

extension Lexicon.Graph.Node: Equatable {}

public extension Lexicon.Graph.Node {

	func traverse(parent: ID? = nil, name: Name? = nil, yield: ((id: ID, name: Name, node: Lexicon.Graph.Node)) -> ()) {
		let path = parent
			.map { $0.split(separator: ".").map(Name.init) }
			?? []
		traverse(path: path + [name ?? self.name], yield: yield)
	}

	private func traverse(path: [Name], yield: ((id: ID, name: Name, node: Lexicon.Graph.Node)) -> ()) {
		let id = path.joined(separator: ".")
		yield((id, path.last ?? name, self))
		for (name, child) in children {
			child.traverse(path: path + [name], yield: yield)
		}
	}
}
