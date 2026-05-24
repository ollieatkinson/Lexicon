//
// github.com/screensailor 2026
//

import Foundation
import Collections
import _Collections

public extension Lexicon {

	struct Document: Sendable {
		public typealias Roots = _Collections.SortedDictionary<Graph.Node.Name, Graph.Node>

		public var date: Date
		public var roots: Roots
		public var imports: [Import]
		public var notes: [String]
		public var comments: [String]

		public init(
			date: Date = .init(),
			roots: [Graph.Node.Name: Graph.Node] = [:],
			imports: [Import] = [],
			notes: [String] = [],
			comments: [String] = []
		) {
			self.date = date
			self.roots = Roots(roots)
			self.imports = imports
			self.notes = notes
			self.comments = comments
		}

		public init(_ graph: Graph) {
			self.init(
				date: graph.date,
				roots: [graph.root.name: graph.root]
			)
		}

		public var root: Graph.Node? {
			roots.values.first
		}

		public func graph(root name: Graph.Node.Name? = nil) throws -> Graph {
			let node: Graph.Node?
			if let name = name {
				node = roots[name]
			} else {
				node = root
			}
			guard let root = node else {
				throw "The document does not declare a root lemma"
			}
			return Graph(root: root, date: date)
		}
	}

	struct Import: Hashable, Codable, Sendable, CustomStringConvertible {
		public enum Location: String, Codable, Sendable {
			case local
			case remote
		}

		public var reference: String
		public var location: Location

		public init(_ reference: String) {
			self.reference = reference
			self.location = reference.lowercased().hasPrefix("http") ? .remote : .local
		}

		public init(reference: String, location: Location) {
			self.reference = reference
			self.location = location
		}

		public var description: String {
			reference
		}
	}
}

public extension Lexicon.Document {

	struct JSON: Codable {
		public var date: Date
		public var roots: [Lexicon.Graph.Node.JSON]?
		public var imports: [Lexicon.Import]?
		public var notes: [String]?
		public var comments: [String]?

		public init(_ document: Lexicon.Document) {
			self.date = document.date
			self.roots = document.roots.values
				.map(Lexicon.Graph.Node.JSON.init)
				.unlessEmpty
			self.imports = document.imports
				.sorted { $0.reference < $1.reference }
				.unlessEmpty
			self.notes = document.notes.unlessEmpty
			self.comments = document.comments.unlessEmpty
		}
	}

	var json: JSON {
		JSON(self)
	}

	init(_ json: JSON) {
		self.init(
			date: json.date,
			roots: Dictionary(
				(json.roots ?? []).map { ($0.name, Lexicon.Graph.Node($0)) },
				uniquingKeysWith: { _, last in last }
			),
			imports: json.imports ?? [],
			notes: json.notes ?? [],
			comments: json.comments ?? []
		)
	}
}

public extension Lexicon.Graph.Node {

	struct JSON: Codable {
		public var name: Name
		public var type: OrderedSet<ID>?
		public var protonym: Protonym?
		public var defaultValue: DefaultValue.JSON?
		public var connections: [Lexicon.Import]?
		public var notes: [String]?
		public var comments: [String]?
		public var children: [Self]?

		public init(_ node: Lexicon.Graph.Node) {
			self.name = node.name
			self.type = node.type
				.sorted()
				.unlessEmpty
				.map(OrderedSet.init)
			self.protonym = node.protonym
			self.defaultValue = node.defaultValue.map(DefaultValue.JSON.init)
			self.connections = node.connections
				.sorted { $0.reference < $1.reference }
				.unlessEmpty
			self.notes = node.notes.unlessEmpty
			self.comments = node.comments.unlessEmpty
			self.children = node.children.values
				.map(Self.init)
				.unlessEmpty
		}
	}

	init(_ json: JSON) {
		self.init(
			name: json.name,
			children: Dictionary(
				(json.children ?? []).map { ($0.name, Self($0)) },
				uniquingKeysWith: { _, last in last }
			),
			type: Set(json.type ?? []),
			defaultValue: json.defaultValue.map(DefaultValue.init),
			connections: json.connections ?? [],
			notes: json.notes ?? [],
			comments: json.comments ?? []
		)
	}
}
