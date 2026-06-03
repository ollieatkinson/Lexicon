//
// github.com/screensailor 2022
//

import Collections
import Foundation

public struct OrderedJSONDictionary<Value: Codable & Sendable>: Sendable {
	public var values: OrderedDictionary<String, Value>

	public init(_ values: OrderedDictionary<String, Value>) {
		self.values = values
	}

	public init<S>(uniqueKeysWithValues keysAndValues: S) where S: Sequence, S.Element == (String, Value) {
		self.values = OrderedDictionary(uniqueKeysWithValues: keysAndValues)
	}
}

extension OrderedJSONDictionary: ExpressibleByDictionaryLiteral {
	public init(dictionaryLiteral elements: (String, Value)...) {
		self.init(uniqueKeysWithValues: elements)
	}
}

extension OrderedJSONDictionary: Sequence {
	public typealias Element = (key: String, value: Value)

	public var isEmpty: Bool {
		values.isEmpty
	}

	public func makeIterator() -> AnyIterator<Element> {
		var iterator = values.makeIterator()
		return AnyIterator {
			iterator.next()
		}
	}
}

extension OrderedJSONDictionary: Codable {
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: OrderedJSONDictionaryKey.self)
		let pairs = try container.allKeys
			.sorted { $0.stringValue < $1.stringValue }
			.map { key in
				(key.stringValue, try container.decode(Value.self, forKey: key))
			}
		self.init(uniqueKeysWithValues: pairs)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: OrderedJSONDictionaryKey.self)
		for (key, value) in values {
			try container.encode(value, forKey: OrderedJSONDictionaryKey(key))
		}
	}
}

extension OrderedJSONDictionary: Equatable where Value: Equatable {}

private struct OrderedJSONDictionaryKey: CodingKey {
	var stringValue: String
	var intValue: Int?

	init(_ stringValue: String) {
		self.stringValue = stringValue
		self.intValue = nil
	}

	init?(stringValue: String) {
		self.init(stringValue)
	}

	init?(intValue: Int) {
		return nil
	}
}

public extension Lexicon.Graph {

	struct JSON: Codable, Sendable {
		public var date: Date
		public var name: Lemma.Name
		public var classes: [Node.Class.JSON]
		public var references: OrderedSet<Lemma.ID>?
	}
}

public extension Lexicon {
	
	func json() -> Graph.JSON {
		let classes = classes().values.map(\.json).sorted { $0.id < $1.id }
		return Graph.JSON(
			date: document.date,
			name: graph.root.name,
			classes: classes,
			references: classes.references
		)
	}

	func classes() -> [Lemma.ID: Graph.Node.Class] {

		var classes: [Lemma.ID: Graph.Node.Class] = [:]

		for root in roots.values {
			root.graphTraversal(.depthFirst) { lemma in
				let o = Graph.Node.Class(lemma: lemma)
				classes[o.json.id] = o
			}
		}

		for klass in classes.values {
			klass.json.supertype = Lemma.supertype(for: klass, in: &classes)
			klass.refreshReferences()
		}

		return classes
	}
}

public extension Lemma {
	
	func classes() -> [ID: Lexicon.Graph.Node.Class] {
		
		var classes: [ID: Class] = [:]
		
		graphTraversal(.depthFirst) { lemma in
			let o = Class(lemma: lemma)
			classes[o.json.id] = o
		}
		
		for klass in classes.values {
			klass.json.supertype = Self.supertype(for: klass, in: &classes)
			klass.refreshReferences()
		}
		
		return classes
	}
}

public extension Sequence where Element == Lexicon.Graph.Node.Class {
	
	func sortedByDependancy() -> [Element] {
		sorted{ l, r in l.json.id.lexicographicallyPrecedes(r.json.id) }.sorted{ l, r in
			r.is(l)
		}
	}
}

private extension Sequence where Element == Lemma {
	
	@LexiconActor func sortedByChildCount() -> [Element] {
		sorted{ l, r in
			guard l.ownChildren.count != r.ownChildren.count else {
				return l.id.lexicographicallyPrecedes(r.id)
			}
			return l.ownChildren.count > r.ownChildren.count
		}
	}
}

fileprivate extension Lemma {
	
	typealias Class = Lexicon.Graph.Node.Class
	
	static func supertype(for klass: Class, in classes: inout [ID: Class]) -> ID? {
		guard let type = klass.json.type, let first = type.first else {
			return nil
		}
		guard type.count > 1 else {
			return first
		}
		return mixin(forOrderedType: klass.orderedType, in: &classes).json.id
	}

	static func mixin(forOrderedType type: [ID], in classes: inout [ID: Class]) -> Class {
		guard type.count > 1, let first = type.first, let last = type.last else {
			fatalError()
		}
		let id = type.joined(separator: "_&_")
		if let o = classes[id] {
			return o
		}
		let supertype: Class
		if type.count > 2 {
			supertype = mixin(forOrderedType: Array(type.dropLast()), in: &classes)
		} else {
			supertype = classes[first]!
		}
		let mixin = classes[last]!
		let klass = Class(
			id: id,
			supertype: supertype.json.id,
			mixin: mixin,
			kind: supertype.kind.union(mixin.kind)
		)
		classes[klass.json.id] = klass
		return klass
	}
}

public extension Lexicon.Graph.Node {
	
	class Class: Hashable {

		public var json: JSON
		public let children: OrderedJSONDictionary<Lemma.ID>?
		let inheritedChildren: OrderedJSONDictionary<Lemma.ID>?
		public let orderedType: [Lemma.ID]
		public var kind: Set<Lemma.ID>

		@LexiconActor init(lemma: Lemma) {
			let type = lemma.ownType
				.keys
				.unlessEmpty
			let children = lemma.ownChildren
				.filter(\.value.protonym.isNil)
				.map { (name, lemma) in (name, lemma.id) }
				.sorted { $0.0 < $1.0 }
				.unlessEmpty
				.map(OrderedJSONDictionary.init(uniqueKeysWithValues:))
			let inheritedChildren = lemma.node.protonym.isNil
				? lemma.children
					.filter(\.value.protonym.isNil)
					.map { (name, lemma) in (name, lemma.id) }
					.sorted { $0.0 < $1.0 }
					.unlessEmpty
					.map(OrderedJSONDictionary.init(uniqueKeysWithValues:))
				: nil
			let synonyms = lemma.ownChildren
				.compactMap { (name, lemma) in lemma.node.protonym.map { protonym in (name, protonym) } }
				.sorted { $0.0 < $1.0 }
				.unlessEmpty
				.map(OrderedJSONDictionary.init(uniqueKeysWithValues:))

			self.json = JSON(
				id: lemma.id,
				protonym: lemma.protonym?.id,
				type: type,
				children: children.map { OrderedSet($0.values.keys) },
				synonyms: synonyms,
				defaultValue: lemma.jsonDefaultValue.map(Lexicon.Graph.Node.DefaultValue.JSON.init),
				notes: lemma.node.notes.unlessEmpty
			)

			self.children = children
			self.inheritedChildren = inheritedChildren
			self.orderedType = lemma.ownType.values
				.map(\.unwrapped)
				.sortedByChildCount()
				.map(\.id)
			self.kind = Set(lemma.type.keys)
			refreshReferences()
		}

		init(id: Lemma.ID, supertype: Lemma.ID, mixin: Lexicon.Graph.Node.Class, kind: Set<Lemma.ID>) {

			self.json = JSON(
				id: id,
				supertype: supertype,
				mixin: JSON.Mixin(
					type: mixin.json.id,
					children: mixin.inheritedChildren
				)
			)

			self.children = nil
			self.inheritedChildren = nil
			self.orderedType = []
			self.kind = kind
			refreshReferences()
		}

		func refreshReferences() {
			json.references = json.referencedIDs
		}

		@inlinable public func `is`(_ type: Class) -> Bool {
			self.kind.contains(type.json.id)
		}
		
		public func hash(into hasher: inout Hasher) {
			hasher.combine(json.id)
		}
		
		public static func == (lhs: Class, rhs: Class) -> Bool {
			lhs.json.id == rhs.json.id
		}
	}
}

extension Lexicon.Graph.Node.Class: Encodable {

	public struct JSON: Codable, Sendable {
		public var id: Lemma.ID
		public var protonym: Lemma.ID?
		public var type: OrderedSet<Lemma.ID>?
		public var children: OrderedSet<Lemma.Name>?
		public var synonyms: OrderedJSONDictionary<Lemma.Protonym>?
		public var defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?
		public var notes: [String]?
		public var supertype: Lemma.ID?
		public var mixin: Mixin?
		public var references: OrderedSet<Lemma.ID>?
	}
	
	@inlinable public func encode(to encoder: Encoder) throws {
		try json.encode(to: encoder)
	}
}

public extension Lexicon.Graph.Node.Class.JSON {

	struct Mixin: Codable, Sendable {
		public var type: Lemma.ID
		public var children: OrderedJSONDictionary<Lemma.ID>?
	}
}

public extension Lexicon.Graph.Node.Class.JSON {
	
	var hasProperties: Bool {
		!hasNoProperties
	}
	
	var hasNoProperties: Bool {
		(children?.isEmpty ?? true) && (synonyms?.isEmpty ?? true) && (mixin?.children?.isEmpty ?? true)
	}

	var referencedIDs: OrderedSet<Lemma.ID>? {
		var references: OrderedSet<Lemma.ID> = []
		if let protonym {
			references.append(protonym)
		}
		for type in type ?? [] {
			references.append(type)
		}
		for child in children ?? [] {
			references.append("\(id).\(child)")
		}
		for (_, protonym) in synonyms ?? [:] {
			references.append("\(id).\(protonym)")
		}
		if let reference = defaultValue?.reference {
			references.append(reference)
		}
		if let supertype {
			references.append(supertype)
		}
		if let mixin {
			references.append(mixin.type)
			for (_, child) in mixin.children ?? [:] {
				references.append(child)
			}
		}
		return references.unlessEmpty
	}
}

private extension Sequence where Element == Lexicon.Graph.Node.Class.JSON {

	var references: OrderedSet<Lemma.ID>? {
		OrderedSet(flatMap { $0.references ?? [] }).unlessEmpty
	}
}

private extension Lemma {

	var jsonDefaultValue: Lexicon.Graph.Node.DefaultValue? {
		guard let defaultValue = defaultValue else {
			return nil
		}

		switch defaultValue {
			case .literal(let value):
				return value.filtered(matching: self).map(Lexicon.Graph.Node.DefaultValue.literal)

			case .reference(let id):
				guard jsonFields.values.contains(where: { $0.id == id }) else {
					return nil
				}
				return .reference(id)
		}
	}

	var jsonFields: Children {
		children.filter { !$0.value.isSynonym }
	}
}

private extension JSONValue {

	@LexiconActor func filtered(matching lemma: Lemma) -> JSONValue? {
		let fields = lemma.jsonFields

		switch self {
			case .object(let object) where fields.isNotEmpty:
				let values = object.reduce(into: [String: JSONValue]()) { values, field in
					guard
						let lemma = fields[field.key],
						let value = field.value.filtered(matching: lemma)
					else {
						return
					}
					values[field.key] = value
				}
				return values.unlessEmpty.map(JSONValue.object)

			case .object:
				return self

			default:
				return fields.isEmpty ? self : nil
		}
	}
}
