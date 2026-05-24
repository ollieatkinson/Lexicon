//
// github.com/screensailor 2026
//

import Foundation

public extension Lexicon.Graph.Node {

	enum DefaultValue: Hashable, Codable, Sendable {
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
	case bool(Bool)
	case array([JSONValue])
	case object([String: JSONValue])
	case null
}

public extension JSONValue {

	struct JSON: Codable, Hashable, Sendable {
		public var string: String?
		public var number: Double?
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
			case let value as Bool:
				self = .bool(value)
			case let value as NSNumber:
				self = .number(value.doubleValue)
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
