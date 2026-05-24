//
// github.com/screensailor 2026
//

import Collections
import OrderedCollections

/// A dictionary that preserves keys in ascending order.
///
/// This implementation stores elements in an `OrderedDictionary`, so inserting
/// a new key finds its position with binary search but still shifts storage.
/// It is intended for small-to-medium ordered maps, not as a B-tree replacement.
public struct SortedDictionary<Key: Comparable & Hashable, Value> {

	public typealias Element = (key: Key, value: Value)

	private var storage: OrderedDictionary<Key, Value>

	public init() {
		self.storage = [:]
	}

	public init(_ dictionary: [Key: Value]) {
		self.init(uniqueKeysWithValues: dictionary)
	}

	public init<S>(uniqueKeysWithValues elements: S) where S: Sequence, S.Element == Element {
		self.storage = OrderedDictionary(
			uniqueKeysWithValues: elements.sorted { $0.key < $1.key }
		)
	}

	public var keys: OrderedSet<Key> {
		storage.keys
	}

	public var keysInOrder: OrderedSet<Key> {
		keys
	}

	public var values: OrderedDictionary<Key, Value>.Values {
		storage.values
	}

	public var valuesInKeyOrder: [Value] {
		Array(values)
	}

	public var count: Int {
		storage.count
	}

	public var isEmpty: Bool {
		storage.isEmpty
	}

	public var isNotEmpty: Bool {
		!isEmpty
	}

	public subscript(key: Key) -> Value? {
		get {
			storage[key]
		}
		set {
			guard let newValue else {
				storage.removeValue(forKey: key)
				return
			}
			updateValue(newValue, forKey: key)
		}
	}

	@discardableResult
	public mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
		let index = storage.index(forKey: key) ?? insertionIndex(for: key)
		return storage.updateValue(value, forKey: key, insertingAt: index).originalMember
	}

	@discardableResult
	public mutating func removeValue(forKey key: Key) -> Value? {
		storage.removeValue(forKey: key)
	}

	public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
		storage.removeAll(keepingCapacity: keepCapacity)
	}

	public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> [Key: T] {
		var result: [Key: T] = [:]
		for (key, value) in storage {
			result[key] = try transform(value)
		}
		return result
	}

	public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Self {
		var result = Self()
		for element in self where try isIncluded(element) {
			result[element.key] = element.value
		}
		return result
	}

	public mutating func merge<S>(
		_ other: S,
		uniquingKeysWith combine: (Value, Value) throws -> Value
	) rethrows where S: Sequence, S.Element == Element {
		for (key, value) in other {
			if let existing = self[key] {
				self[key] = try combine(existing, value)
			} else {
				self[key] = value
			}
		}
	}

	private func insertionIndex(for key: Key) -> Int {
		storage.keys.lowerBound(of: key)
	}
}

extension SortedDictionary: ExpressibleByDictionaryLiteral {

	public init(dictionaryLiteral elements: (Key, Value)...) {
		self.init(uniqueKeysWithValues: elements.map { (key: $0.0, value: $0.1) })
	}
}

extension SortedDictionary: Sequence {

	public func makeIterator() -> OrderedDictionary<Key, Value>.Iterator {
		storage.makeIterator()
	}
}

extension SortedDictionary: Equatable where Value: Equatable {}

extension SortedDictionary: Sendable where Key: Sendable, Value: Sendable {}
