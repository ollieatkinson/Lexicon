//
// github.com/screensailor 2026
//

import Foundation
import CoreFoundation

public extension Lexicon.Graph.Node {

	enum DefaultValue: Hashable, Sendable {
		case literal(JSONValue)
		case reference(Lemma.ID)
	}
}

public extension Lexicon.Graph.Node.DefaultValue {

	struct JSON: Codable, Hashable, Sendable {
		public var literal: JSONValue.JSON?
		public var reference: Lemma.ID?

		public init(_ value: Lexicon.Graph.Node.DefaultValue) {
			switch value {
				case .literal(let value):
					self.literal = JSONValue.JSON(value)
					self.reference = nil
				case .reference(let id):
					self.literal = nil
					self.reference = id
			}
		}
	}

	init(_ json: JSON) {
		if let reference = json.reference {
			self = .reference(reference)
		} else {
			self = .literal(json.literal.map(JSONValue.init) ?? .null)
		}
	}
}

public enum JSONValue: Hashable, Sendable {
	case string(String)
	case number(Double)
	/// A signed platform integer that cannot be represented exactly as Double.
	case integer(Int)
	case bool(Bool)
	case array([JSONValue])
	case object([String: JSONValue])
	case null
}

public extension JSONValue {
	static func == (lhs: Self, rhs: Self) -> Bool {
		switch (lhs, rhs) {
			case (.string(let lhs), .string(let rhs)): return lhs == rhs
			case (.number(let lhs), .number(let rhs)): return lhs == rhs
			case (.integer(let lhs), .integer(let rhs)): return lhs == rhs
			case (.integer(let integer), .number(let number)), (.number(let number), .integer(let integer)):
				return Int(exactly: number) == integer
			case (.bool(let lhs), .bool(let rhs)): return lhs == rhs
			case (.array(let lhs), .array(let rhs)): return lhs == rhs
			case (.object(let lhs), .object(let rhs)): return lhs == rhs
			case (.null, .null): return true
			default: return false
		}
	}

	func hash(into hasher: inout Hasher) {
		switch self {
			case .string(let value):
				hasher.combine(0)
				hasher.combine(value)
			case .number(let value):
				hasher.combine(1)
				hasher.combine(value)
			case .integer(let value):
				hasher.combine(1)
				hasher.combine(Double(value))
			case .bool(let value):
				hasher.combine(2)
				hasher.combine(value)
			case .array(let value):
				hasher.combine(3)
				hasher.combine(value)
			case .object(let value):
				hasher.combine(4)
				hasher.combine(value)
			case .null:
				hasher.combine(5)
		}
	}

	struct JSON: Codable, Hashable, Sendable {
		public var string: String?
		public var number: Double?
		public var integer: Int?
		public var bool: Bool?
		public var array: [Self]?
		public var object: [String: Self]?
		public var null: Bool?

		public init(_ value: JSONValue) {
			switch value {
				case .string(let value):
					self.string = value
				case .number(let value):
					self.number = value
				case .integer(let value):
					self.integer = value
				case .bool(let value):
					self.bool = value
				case .array(let value):
					self.array = value.map(Self.init)
				case .object(let value):
					self.object = value.mapValues(Self.init)
				case .null:
					self.null = true
			}
		}
	}

	init(_ json: JSON) {
		if let value = json.string {
			self = .string(value)
		} else if let value = json.integer {
			self = .integer(value)
		} else if let value = json.number {
			self = .number(value)
		} else if let value = json.bool {
			self = .bool(value)
		} else if let value = json.array {
			self = .array(value.map(JSONValue.init))
		} else if let value = json.object {
			self = .object(value.mapValues(JSONValue.init))
		} else {
			self = .null
		}
	}

	static func parse(_ string: String) -> JSONValue {
		let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
		guard
			let data = trimmed.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
			let value = JSONValue(jsonObject: object)
		else {
			return .string(string)
		}
		return value
	}

	var jsonObject: Any {
		switch self {
			case .string(let value):
				return value
			case .number(let value):
				return value
			case .integer(let value):
				return value
			case .bool(let value):
				return value
			case .array(let value):
				return value.map(\.jsonObject)
			case .object(let value):
				return value.mapValues(\.jsonObject)
			case .null:
				return NSNull()
		}
	}

	init?(jsonObject: Any) {
		switch jsonObject {
			case _ as NSNull:
				self = .null
			case let value as NSNumber:
				// NSNumber(0/1) also bridges to Bool. Inspect the Foundation
				// type before choosing the JSON case, including nested values.
				if CFGetTypeID(value) == CFBooleanGetTypeID() {
					self = .bool(value.boolValue)
				} else {
					let integer = value.int64Value
					let decimal = (value as? NSDecimalNumber) ?? NSDecimalNumber(string: value.stringValue)
					if let exact = Int(exactly: integer),
					   decimal.compare(NSDecimalNumber(value: integer)) == .orderedSame,
					   Int(exactly: Double(exact)) != exact {
						self = .integer(exact)
					} else {
						self = .number(value.doubleValue)
					}
				}
			case let value as String:
				self = .string(value)
			case let value as [Any]:
				let values = value.compactMap(Self.init(jsonObject:))
				guard values.count == value.count else {
					return nil
				}
				self = .array(values)
			case let value as [String: Any]:
				let values = value.compactMapValues(Self.init(jsonObject:))
				guard values.count == value.count else {
					return nil
				}
				self = .object(values)
			default:
				return nil
		}
	}
}
