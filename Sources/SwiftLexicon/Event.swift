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
	subscript<Output>(
		type as: Output.Type = Output.self,
		using decoder: JSONDecoder = JSONDecoder()
	) -> Output where Output: Decodable {
		get throws { try k[as: Output.self, using: decoder] }
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
