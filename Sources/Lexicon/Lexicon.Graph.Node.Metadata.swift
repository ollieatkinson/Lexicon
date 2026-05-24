//
// github.com/screensailor 2026
//

import Foundation

public extension Lexicon.Graph.Node {

	enum DefaultValue: Hashable, Codable {
		case literal(JSONValue)
		case reference(Lemma.ID)

		private enum CodingKeys: String, CodingKey {
			case literal
			case reference
		}

		public init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			if let reference = try container.decodeIfPresent(Lemma.ID.self, forKey: .reference) {
				self = .reference(reference)
			} else {
				self = .literal(try container.decode(JSONValue.self, forKey: .literal))
			}
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			switch self {
				case .literal(let value):
					try container.encode(value, forKey: .literal)
				case .reference(let id):
					try container.encode(id, forKey: .reference)
			}
		}
	}
}

public enum JSONValue: Hashable, Codable {
	case string(String)
	case number(Double)
	case bool(Bool)
	case array([JSONValue])
	case object([String: JSONValue])
	case null

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? container.decode(Double.self) {
			self = .number(value)
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else if let value = try? container.decode([JSONValue].self) {
			self = .array(value)
		} else {
			self = .object(try container.decode([String: JSONValue].self))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
			case .string(let value):
				try container.encode(value)
			case .number(let value):
				try container.encode(value)
			case .bool(let value):
				try container.encode(value)
			case .array(let value):
				try container.encode(value)
			case .object(let value):
				try container.encode(value)
			case .null:
				try container.encodeNil()
		}
	}
}

public extension JSONValue {

	static func parse(_ string: String) -> JSONValue {
		let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
		guard
			let data = trimmed.data(using: .utf8),
			let value = try? JSONDecoder().decode(JSONValue.self, from: data)
		else {
			return .string(string)
		}
		return value
	}
}
