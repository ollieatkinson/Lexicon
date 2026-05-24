//
// github.com/screensailor 2026
//

import Foundation

public extension Lexicon {

	struct Document {
		public var date: Date
		public var roots: [Graph.Node.Name: Graph.Node]
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
			self.roots = roots
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
			roots.sortedByLocalizedStandard(by: \.key).first?.value
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

	struct Import: Hashable, Codable, CustomStringConvertible {
		public enum Location: String, Codable {
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

extension Lexicon.Document: Codable {

	private enum CodingKeys: String, CodingKey {
		case date
		case roots
		case imports
		case notes
		case comments
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			date: try container.decode(Date.self, forKey: .date),
			roots: try container.decode([String: Lexicon.Graph.Node].self, forKey: .roots),
			imports: try container.decodeIfPresent([Lexicon.Import].self, forKey: .imports) ?? [],
			notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? [],
			comments: try container.decodeIfPresent([String].self, forKey: .comments) ?? []
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(date, forKey: .date)
		try container.encode(roots, forKey: .roots)
		try container.encodeIfPresent(imports.unlessEmpty, forKey: .imports)
		try container.encodeIfPresent(notes.unlessEmpty, forKey: .notes)
		try container.encodeIfPresent(comments.unlessEmpty, forKey: .comments)
	}
}

extension Lexicon.Graph.Node: Codable {

	private enum CodingKeys: String, CodingKey {
		case name
		case stableID
		case type
		case protonym
		case defaultValue
		case connections
		case notes
		case comments
		case children
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			name: try container.decode(Name.self, forKey: .name),
			children: try container.decodeIfPresent([Name: Self].self, forKey: .children) ?? [:],
			type: try container.decodeIfPresent(Set<ID>.self, forKey: .type) ?? [],
			stableID: try container.decodeIfPresent(ID.self, forKey: .stableID),
			defaultValue: try container.decodeIfPresent(DefaultValue.self, forKey: .defaultValue),
			connections: try container.decodeIfPresent([Lexicon.Import].self, forKey: .connections) ?? [],
			notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? [],
			comments: try container.decodeIfPresent([String].self, forKey: .comments) ?? []
		)
		self.protonym = try container.decodeIfPresent(Protonym.self, forKey: .protonym)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encodeIfPresent(stableID, forKey: .stableID)
		try container.encodeIfPresent(type.unlessEmpty, forKey: .type)
		try container.encodeIfPresent(protonym, forKey: .protonym)
		try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
		try container.encodeIfPresent(connections.unlessEmpty, forKey: .connections)
		try container.encodeIfPresent(notes.unlessEmpty, forKey: .notes)
		try container.encodeIfPresent(comments.unlessEmpty, forKey: .comments)
		try container.encodeIfPresent(children.unlessEmpty, forKey: .children)
	}
}
