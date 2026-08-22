//
// github.com/screensailor 2026
//

public struct CastingError: Swift.Error, CustomStringConvertible, Sendable {
	public let description: String
	public let valueType: Any.Type
	public let type: Any.Type

	public init<Value>(value: Any?, to type: Value.Type) {
		let valueType = value.map { Swift.type(of: $0) } ?? Optional<Any>.self
		self.valueType = valueType
		self.type = type
		self.description = "\(CastingError.self)(from: \(valueType), to: \(Value.self), value: \(value as Any))"
	}
}

public enum JSONMutationError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
	case arrayIndexOutOfBounds(index: Int, count: Int)

	public var description: String {
		switch self {
		case .arrayIndexOutOfBounds(let index, let count):
			"JSON array index \(index) is outside the replace-or-append range 0...\(count)."
		}
	}
}

private extension JSON {
	func cast<Value>(to type: Value.Type = Value.self) throws -> Value {
		if Value.self == JSON.self {
			return self as! Value
		}
		guard let value = rawValue as? Value else {
			throw CastingError(value: rawValue, to: Value.self)
		}
		return value
	}
}

public extension JSON {
	func value<Path>(at path: Path) -> JSON? where Path: Collection, Path.Element == CodingIndex {
		var current = self
		for component in path {
			switch component {
			case .key(let key):
				guard let object = current.object, let value = object[key] else {
					return nil
				}
				current = value
			case .index(let index):
				guard let array = current.array, let index = array.resolvedIndex(index) else {
					return nil
				}
				current = array[index]
			}
		}
		return current
	}

	subscript(_ path: CodingIndex...) -> JSON {
		self[path]
	}

	subscript<Path>(_ path: Path) -> JSON where Path: Collection, Path.Element == CodingIndex {
		var current = self
		for component in path {
			current = current[component]
		}
		return current
	}

	subscript<Value>(_ path: CodingIndex..., as type: Value.Type = Value.self) -> Value {
		get throws {
			try self[path].cast(to: Value.self)
		}
	}

	subscript<Value, Path>(
		_ path: Path,
		as type: Value.Type = Value.self
	) -> Value where Path: Collection, Path.Element == CodingIndex {
		get throws {
			try self[path].cast(to: Value.self)
		}
	}

	subscript(component: CodingIndex) -> JSON {
		switch component {
		case .key(let key):
			return self[key]
		case .index(let index):
			return self[index]
		}
	}

	subscript(key: String) -> JSON {
		get {
			guard let object else {
				return .null
			}
			return object[key] ?? .null
		}
		set {
			var object = object ?? [:]
			object[key] = newValue
			self = JSON(object)
		}
	}

	subscript(index: Int) -> JSON {
		guard let array, let index = array.resolvedIndex(index) else {
			return .null
		}
		return array[index]
	}

	/// Replaces a value at `path`, creating keyed containers and appending only at an array's end.
	///
	/// Negative indexes address existing elements from the end. Sparse array writes throw
	/// without changing the receiver.
	mutating func set<Path>(_ newValue: JSON, at path: Path) throws
	where Path: Collection, Path.Element == CodingIndex {
		guard let head = path.first else {
			self = newValue
			return
		}

		switch head {
		case .key(let key):
			var object = object ?? [:]
			var child = object[key] ?? .container(for: path.dropFirst().first)
			try child.set(newValue, at: path.dropFirst())
			object[key] = child
			self = .object(object)

		case .index(let requestedIndex):
			var array = array ?? []
			let index: Int
			if requestedIndex < 0 {
				guard let resolved = array.resolvedIndex(requestedIndex) else {
					throw JSONMutationError.arrayIndexOutOfBounds(index: requestedIndex, count: array.count)
				}
				index = resolved
			} else if requestedIndex < array.count {
				index = requestedIndex
			} else if requestedIndex == array.count {
				array.append(.container(for: path.dropFirst().first))
				index = requestedIndex
			} else {
				throw JSONMutationError.arrayIndexOutOfBounds(index: requestedIndex, count: array.count)
			}

			var child = array[index]
			try child.set(newValue, at: path.dropFirst())
			array[index] = child
			self = .array(array)
		}
	}
}

private extension JSON {
	static func container(for component: CodingIndex?) -> JSON {
		switch component {
		case .some(.index):
			.array([])
		case .some(.key), .none:
			.object([:])
		}
	}
}

package extension Array where Element == JSON {
	func resolvedIndex(_ index: Int) -> Int? {
		if indices.contains(index) {
			return index
		}
		guard index < 0, !isEmpty else {
			return nil
		}
		let resolved = count + index
		guard indices.contains(resolved) else {
			return nil
		}
		return resolved
	}
}
