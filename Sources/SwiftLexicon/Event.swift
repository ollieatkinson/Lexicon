//
// github.com/screensailor 2022
//

import Foundation
import Synchronization
import _JSON

public struct Event: Sendable, Hashable, Identifiable, CustomStringConvertible {

	private static let count = Mutex(UInt(0))
	private let storage: Storage

	public let id: UInt
	public let description: String
	public let values: [String: Value]

	public var l: L { storage.l }
	public var k: any KProtocol { storage.k }

	public init(_ l: L) {
		self.init(K(l))
	}

	public init<A: L>(_ k: K<A>) {

		self.id = Self.count.withLock { count in
			count += 1
			return count
		}

		self.description = k.__
		self.values = Dictionary(uniqueKeysWithValues: k.____.map { key, value in
			(key.__, value)
		})
		self.storage = Storage(l: k.___, k: k)
	}

	public var snapshot: Snapshot {
		Snapshot(id: id, description: description, lemma: l.__, values: values)
	}

	public func `is`(_ i: I) -> Bool {
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

	public func `is`<A>(_: A.Type) -> Bool {
		k(\.L) is A
	}

	public func `is`<A>(_ a: K<A>) -> Bool {
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
		if let array {
			return "[" + array.map(\.eventDescription).joined(separator: ", ") + "]"
		}
		if let object {
			return "{" + object.sortedEntries.map { "\($0.key): \($0.value.eventDescription)" }.joined(separator: ", ") + "}"
		}
		return String(describing: any)
	}

	func value<Output>(as type: Output.Type = Output.self) throws -> Output {
		if Output.self == JSON.self {
			return self as! Output
		}
		if let bool, Output.self == Bool.self {
			return bool as! Output
		}
		if let int, Output.self == Int.self {
			return int as! Output
		}
		if let double, Output.self == Double.self {
			return double as! Output
		}
		if let string, Output.self == String.self {
			return string as! Output
		}
		if let array, Output.self == Array.self {
			return array as! Output
		}
		if let object, Output.self == Object.self {
			return object as! Output
		}
		if let type = Output.self as? any Decodable.Type,
		   let value = try JSONDecoder().decode(type, from: data()) as? Output {
			return value
		}
		if Output.self == String.self {
			return eventDescription as! Output
		}
		throw JSONError("Could not decode event value '\(eventDescription)' as \(Output.self)")
	}
}

private extension Event {

	// The Sendable event surface is id/description/values. The live lexicon
	// objects are retained for the existing synchronous matching API.
	final class Storage: Sendable {
		let l: L
		let k: any KProtocol

		init(l: L, k: any KProtocol) {
			self.l = l
			self.k = k
		}
	}
}

public extension Event {
	subscript() -> Any? { k[] }
	subscript(key: L) -> Any? { k[key] }
	subscript<Output>(type as: Output.Type = Output.self) -> Output { get throws { try k[as: Output.self] } }
	subscript<Output>(key: L, as: Output.Type = Output.self) -> Output { get throws { try k[key, as: Output.self] } }
}

public extension Event {

	static func == <A: L>(lhs: A, rhs: Event) -> Bool {
		Event(lhs) == rhs
	}

	static func == <A: L>(lhs: Event, rhs: A) -> Bool {
		lhs == Event(rhs)
	}

	static func == <A: L>(lhs: K<A>, rhs: Event) -> Bool {
		Event(lhs) == rhs
	}

	static func == <A: L>(lhs: Event, rhs: K<A>) -> Bool {
		lhs == Event(rhs)
	}

	static func == (lhs: Event, rhs: Event) -> Bool {
		lhs.id == rhs.id
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}
