//
// github.com/screensailor 2022
//

import Foundation
import Synchronization
import _JSON

public struct Event: Sendable, Hashable, Identifiable, CustomStringConvertible {

	private static let count = Mutex(UInt(0))

	public let id: UInt
	public let description: String
	public let values: [String: Value]
	/// An explicit payload, independent of contextual values on the event's key.
	/// Nil retains the original convention of reading a value at the event lemma.
	public let value: Value?

	public var l: L { k(\.L) }
	public let k: any KProtocol

	public init(_ l: L) {
		self.init(K(l))
	}

	public init(_ l: L, value: Value) {
		self.init(K(l), value: value)
	}

	public init<A: L>(_ k: K<A>) {
		self.init(k, payload: .none)
	}

	/// Keeps the complete native key for matching while carrying a separate value.
	public init<A: L>(_ k: K<A>, value: Value) {
		self.init(k, payload: .some(value))
	}

	private init<A: L>(_ k: K<A>, payload: Value?) {

		self.id = Self.count.withLock { count in
			count += 1
			return count
		}

		self.description = payload.map { k.__ + " => " + $0.eventDescription } ?? k.__
		self.value = payload
		self.values = Dictionary(uniqueKeysWithValues: k.____.map { key, value in
			(key.__, value)
		})
		self.k = k
	}

	public var snapshot: Snapshot {
		Snapshot(id: id, description: description, lemma: l.__, values: values, value: value)
	}

	public var detail: EventDetail {
		EventDetail(id: l.__, data: values)
	}

	/// Returns whether this event has the same lemma and any values specified by `i`.
	public func matches(_ i: any I) -> Bool {
		switch i {
			case let i as L:
				return k(\.L) == i

			case let i as any KProtocol:
				return k(\.L) == i(\.L) && i.____.allSatisfy { key, value in
					k.____[key] == value
				}

			default:
				return false
		}
	}

	/// Returns whether this event's lemma is an instance of `type`.
	public func matches<A>(_: A.Type) -> Bool {
		k(\.L) is A
	}

	/// Returns whether this event has the same lemma and bracketed values as `a`.
	public func matches<A>(_ a: K<A>) -> Bool {
		k(\.L) == a(\.L) && a.____.allSatisfy { key, value in
			k.____[key] == value
		}
	}
}

public extension Event {

	typealias Value = JSON

	struct Snapshot: Hashable, Sendable, Codable {
		public var id: UInt
		public var description: String
		public var lemma: String
		public var values: [String: Value]
		public var value: Value?

		init(id: UInt, description: String, lemma: String, values: [String: Value], value: Value?) {
			self.id = id; self.description = description; self.lemma = lemma
			self.values = values; self.value = value
		}

		private enum CodingKeys: String, CodingKey { case id, description, lemma, values, value }
		public init(from decoder: any Decoder) throws {
			let fields = try decoder.container(keyedBy: CodingKeys.self)
			id = try fields.decode(UInt.self, forKey: .id)
			description = try fields.decode(String.self, forKey: .description)
			lemma = try fields.decode(String.self, forKey: .lemma)
			values = try fields.decode([String: Value].self, forKey: .values)
			// Explicit JSON null is a payload; an absent field uses the original
			// value-at-lemma convention. decodeIfPresent would conflate the two.
			value = try fields.contains(.value) ? .some(fields.decode(Value.self, forKey: .value)) : .none
		}
	}
}

public extension JSON {

	var base: Any {
		any
	}

	var eventDescription: String {
		if isNull {
			return "null"
		}
		if let bool {
			return "\(bool)"
		}
		if let int {
			return "\(int)"
		}
		if let double {
			return "\(double)"
		}
		if let string {
			return string
		}
		if array != nil || object != nil, let data = try? data(options: [.fragmentsAllowed, .sortedKeys]) {
			return String(decoding: data, as: UTF8.self)
		}
		return String(describing: any)
	}

	func value<Output>(
		as type: Output.Type = Output.self,
		using decoder: JSONDecoder = JSONDecoder()
	) throws -> Output where Output: Decodable {
		do {
			return try decoder.decode(Output.self, from: data())
		} catch {
			throw JSONError("Could not decode event value '\(eventDescription)' as \(Output.self): \(error)")
		}
	}
}

public extension Event {
	subscript() -> Any? {
		if let value { return value.base }
		return k[]
	}
	subscript(key: L) -> Any? { k[key] }
	subscript<Output>(
		type as: Output.Type = Output.self,
		using decoder: JSONDecoder = JSONDecoder()
	) -> Output where Output: Decodable {
		get throws {
			if let value { return try value.value(as: Output.self, using: decoder) }
			return try k[as: Output.self, using: decoder]
		}
	}
	subscript<Output>(
		key: L,
		as type: Output.Type = Output.self,
		using decoder: JSONDecoder = JSONDecoder()
	) -> Output where Output: Decodable {
		get throws { try k[key, as: Output.self, using: decoder] }
	}
}

public extension Event {

	static func == (lhs: Event, rhs: Event) -> Bool {
		lhs.id == rhs.id
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}
