//
// github.com/screensailor 2026
//

import Foundation
import Collections
import _Collections

public extension Lexicon {

	struct Document: Sendable, Equatable {
		public typealias Roots = _Collections.SortedDictionary<Lemma.Name, Graph.Node>

		public static let unspecifiedDate = Date(timeIntervalSinceReferenceDate: 0)

		public var date: Date
		public var roots: Roots
		public var imports: [Import]
		public var notes: [String]
		public var comments: [String]

		public init(
			date: Date = Self.unspecifiedDate,
			roots: [Lemma.Name: Graph.Node] = [:],
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
				roots: [graph.rootName: graph.root]
			)
		}

		public func graph(root name: Lemma.Name) throws -> Graph {
			guard let root = roots[name] else {
				throw LexiconError("The document does not declare root lemma '\(name)'")
			}
			return Graph(rootName: name, root: root, date: date)
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
			if
				let url = URL(string: reference),
				["http", "https"].contains(url.scheme?.lowercased()),
				url.host != nil
			{
				self.location = .remote
			} else {
				self.location = .local
			}
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

	struct JSON: Codable, Sendable {
		public var date: Date
		public var roots: [Lexicon.Graph.Node.JSON]?
		public var imports: [Lexicon.Import]?
		public var notes: [String]?
		public var comments: [String]?

		public init(_ document: Lexicon.Document) {
			self.date = document.date
			self.roots = document.roots
				.map { Lexicon.Graph.Node.JSON(name: $0.key, node: $0.value) }
				.unlessEmpty
			self.imports = document.imports.unlessEmpty
			self.notes = document.notes.unlessEmpty
			self.comments = document.comments.unlessEmpty
		}
	}

	var json: JSON {
		JSON(self)
	}

	init(_ json: JSON) throws {
		var roots: [Lemma.Name: Lexicon.Graph.Node] = [:]
		for rootJSON in json.roots ?? [] {
			guard roots[rootJSON.name] == nil else {
				throw LexiconError("Duplicate root lemma '\(rootJSON.name)' in JSON document")
			}
			roots[rootJSON.name] = try Lexicon.Graph.Node(rootJSON)
		}
		self.init(
			date: json.date,
			roots: roots,
			imports: json.imports ?? [],
			notes: json.notes ?? [],
			comments: json.comments ?? []
		)
	}
}

public extension Lexicon.Graph.Node {

	struct JSON: Codable, Sendable {
		public var name: Name
		public var type: OrderedSet<ID>?
		public var protonym: Protonym?
		public var defaultValue: DefaultValue.JSON?
		public var connections: [Lexicon.Import]?
		public var notes: [String]?
		public var comments: [String]?
		public var children: [Self]?

		public init(name: Name, node: Lexicon.Graph.Node) {
			self.name = name
			self.type = node.type
				.sorted()
				.unlessEmpty
				.map(OrderedSet.init)
			self.protonym = node.protonym
			self.defaultValue = node.defaultValue.map(DefaultValue.JSON.init)
			self.connections = node.connections.unlessEmpty
			self.notes = node.notes.unlessEmpty
			self.comments = node.comments.unlessEmpty
			self.children = node.children
				.map { Self(name: $0.key, node: $0.value) }
				.unlessEmpty
		}
	}

	init(_ json: JSON) throws {
		var children: [Name: Self] = [:]
		for childJSON in json.children ?? [] {
			guard children[childJSON.name] == nil else {
				throw LexiconError("Duplicate child lemma '\(childJSON.name)' in JSON node")
			}
			children[childJSON.name] = try Self(childJSON)
		}
		self.init(
			children: children,
			type: Set(json.type ?? []),
			protonym: json.protonym,
			defaultValue: json.defaultValue.map(DefaultValue.init),
			connections: json.connections ?? [],
			notes: json.notes ?? [],
			comments: json.comments ?? []
		)
	}
}
