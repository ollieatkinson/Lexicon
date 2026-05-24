//
// github.com/screensailor 2026
//

public extension JSON {
	init(from decoder: Decoder) throws {
		if let container = try? decoder.singleValueContainer() {
			if container.decodeNil() {
				self = .null
				return
			}
			if let value = try? container.decode(Bool.self) {
				self.init(value)
				return
			}
			if let value = try? container.decode(Int.self) {
				self.init(value)
				return
			}
			if let value = try? container.decode(Double.self) {
				self.init(value)
				return
			}
			if let value = try? container.decode(String.self) {
				self.init(value)
				return
			}
		}

		if var array = try? decoder.unkeyedContainer() {
			var values: Array = []
			while !array.isAtEnd {
				values.append(try array.decode(JSON.self))
			}
			self.init(values)
			return
		}

		let object = try decoder.container(keyedBy: AnyCodingKey.self)
		var values: Object = [:]
		for key in object.allKeys {
			values[key.stringValue] = try object.decode(JSON.self, forKey: key)
		}
		self.init(values)
	}

	func encode(to encoder: Encoder) throws {
		switch rawValue {
		case is Null:
			var container = encoder.singleValueContainer()
			try container.encodeNil()
		case let value as Bool:
			var container = encoder.singleValueContainer()
			try container.encode(value)
		case let value as Int:
			var container = encoder.singleValueContainer()
			try container.encode(value)
		case let value as Double:
			var container = encoder.singleValueContainer()
			try container.encode(value)
		case let value as String:
			var container = encoder.singleValueContainer()
			try container.encode(value)
		case let values as Array:
			var container = encoder.unkeyedContainer()
			for value in values {
				try container.encode(value)
			}
		case let values as Object:
			var container = encoder.container(keyedBy: AnyCodingKey.self)
			for (key, value) in values.sortedEntries {
				try container.encode(value, forKey: AnyCodingKey(key))
			}
		default:
			throw EncodingError.invalidValue(
				rawValue,
				.init(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON value.")
			)
		}
	}
}

private struct AnyCodingKey: CodingKey {
	let stringValue: String
	let intValue: Int?

	init(_ stringValue: String) {
		self.stringValue = stringValue
		self.intValue = nil
	}

	init?(stringValue: String) {
		self.init(stringValue)
	}

	init?(intValue: Int) {
		self.stringValue = String(intValue)
		self.intValue = intValue
	}
}
