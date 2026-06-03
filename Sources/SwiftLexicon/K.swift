//
// github.com/screensailor 2022
//

import Foundation
import Lexicon

public extension I where Self: L {

	subscript<Value>(value: Value) -> K<Self> where Value: Sendable, Value: Hashable, Value: Codable {
		K(self, [self: eventValue(value)])
	}
}

@dynamicMemberLookup public struct K<A: L>: Hashable, KProtocol, CustomStringConvertible {

	public let __: String
	public let ___: A
	public let ____: [L: Event.Value]

	public init(_ a: A) {
		self.init(a, [:])
	}

	internal init(_ l: A, _ d: [L: Event.Value]) {
		self.____ = d
		self.___ = l
		self.__ = bracketedDescription(id: l.__, data: d)
	}
}

private func bracketedDescription(id: String, data: [L: Event.Value]) -> String {
	var output = ""
	var index = id.startIndex
	for entry in data.sorted(by: { $0.key.__.count < $1.key.__.count }) {
		assert(id.starts(with: entry.key.__))
		let valueEnd = id.index(id.startIndex, offsetBy: entry.key.__.count)
		output += id[index..<valueEnd]
		output += "[\(entry.value.bracketedDescription)]"
		index = valueEnd
	}
	output += id[index..<id.endIndex]
	return output
}

public extension K {
	@inlinable static var localized: String { A.localized }
}

public struct EventDetail: Hashable, Sendable {
	public let id: String
	public let data: [String: Event.Value]

	public init(id: String, data: [String: Event.Value]) {
		self.id = id
		self.data = data
	}
}

public enum KBracketedDescriptionError: Error, Equatable, Sendable, CustomStringConvertible {
	case emptyIdentifier(String)
	case unexpectedClosingBracket(String)
	case missingClosingBracket(String)

	public var description: String {
		switch self {
			case .emptyIdentifier(let value):
				"Bracketed K description has no identifier: \(value)"
			case .unexpectedClosingBracket(let value):
				"Bracketed K description has an unexpected closing bracket: \(value)"
			case .missingClosingBracket(let value):
				"Bracketed K description has a missing closing bracket: \(value)"
		}
	}
}

public extension K {

	var bracketed: String { __ }
	var description: String { bracketed }

	var detail: EventDetail {
		EventDetail(
			id: ___.__,
			data: Dictionary(uniqueKeysWithValues: ____.map { key, value in
				(key.__, value)
			})
		)
	}

	init(bracketed description: String) throws {
		let detail = try EventDetail(bracketed: description)
		self.init(A(detail.id), detail.data.reduce(into: [:]) { data, entry in
			data[L(entry.key)] = entry.value
		})
	}
}

public extension EventDetail {

	init(bracketed description: String) throws {
		var id = ""
		var data: [String: Event.Value] = [:]
		var index = description.startIndex

		while index < description.endIndex {
			let segmentStart = index
			while index < description.endIndex, description[index] != "[", description[index] != "]" {
				index = description.index(after: index)
			}

			id += description[segmentStart..<index]

			guard index < description.endIndex else {
				break
			}

			guard description[index] == "[" else {
				throw KBracketedDescriptionError.unexpectedClosingBracket(description)
			}

			let valueStart = description.index(after: index)
			var valueEnd = valueStart
			var depth = 1
			var isQuoted = false
			var isEscaped = false

			while valueEnd < description.endIndex {
				let character = description[valueEnd]
				if isQuoted {
					if isEscaped {
						isEscaped = false
					} else if character == "\\" {
						isEscaped = true
					} else if character == "\"" {
						isQuoted = false
					}
				} else {
					switch character {
						case "\"":
							isQuoted = true
						case "[":
							depth += 1
						case "]":
							depth -= 1
							if depth == 0 {
								let value = description[valueStart..<valueEnd]
								data[id] = Event.Value(eventDescription: value)
								index = description.index(after: valueEnd)
								break
							}
						default:
							break
					}
				}

				if depth == 0 {
					break
				}
				valueEnd = description.index(after: valueEnd)
			}

			guard depth == 0 else {
				throw KBracketedDescriptionError.missingClosingBracket(description)
			}
		}

		guard !id.isEmpty else {
			throw KBracketedDescriptionError.emptyIdentifier(description)
		}

		self.init(id: id, data: data)
	}
}

public extension K {

	subscript<B: L>(dynamicMember keyPath: KeyPath<A, B>) -> K<B> {
		K<B>(___[keyPath: keyPath], ____)
	}

	subscript<Value>(value: Value) -> K<A> where Value: Sendable, Value: Hashable, Value: Codable {
		K(___, ____.merging([___: eventValue(value)], uniquingKeysWith: { _, last in last }))
	}
}

public extension K {

	subscript() -> Any? { self[___] }

	subscript(key: L) -> Any? { ____[key]?.base }

	subscript<Value>(
		as type: Value.Type = Value.self,
		using decoder: JSONDecoder = JSONDecoder()
	) -> Value where Value: Decodable {
		get throws { try self[___, as: Value.self, using: decoder] }
	}

	subscript<Value>(
		key: L,
		as type: Value.Type = Value.self,
		using decoder: JSONDecoder = JSONDecoder()
	) -> Value where Value: Decodable {
		get throws { try ____[key].try().value(as: type, using: decoder) }
	}
}

public protocol KProtocol: I {
	var __: String { get }
	var ____: [L: Event.Value] { get }
	subscript() -> Any? { get }
	subscript(key: L) -> Any? { get }
	subscript<A>(as type: A.Type, using decoder: JSONDecoder) -> A where A: Decodable { get throws }
	subscript<A>(key: L, as type: A.Type, using decoder: JSONDecoder) -> A where A: Decodable { get throws }
	func callAsFunction(_: KeyPath<CallAsFunctionKExtensions, CallAsFunctionKExtensions.GetL>) -> L
}

public extension K {

	@inlinable func callAsFunction(_: KeyPath<CallAsFunctionKExtensions, CallAsFunctionKExtensions.GetL>) -> L {
		___
	}
}

public enum CallAsFunctionKExtensions {}

public extension CallAsFunctionKExtensions {
	var L: GetL { .init() }
	struct GetL {}
}

private func eventValue<Value>(_ value: Value) -> Event.Value where Value: Encodable {
	do {
		return try Event.Value.encoded(value)
	} catch {
		preconditionFailure("Could not encode \(Value.self) as an event JSON value: \(error)")
	}
}

private extension Event.Value {

	var bracketedDescription: String {
		guard let string else {
			return eventDescription
		}
		guard string.isSafeUnquotedEventDescriptionString else {
			return jsonEncodedDescription
		}
		return string
	}

	var jsonEncodedDescription: String {
		(try? data(options: [.fragmentsAllowed, .sortedKeys]))
			.map { String(decoding: $0, as: UTF8.self) }
			?? eventDescription
	}

	init(eventDescription: some StringProtocol) {
		let description = String(eventDescription)
		switch description {
			case "null":
				self = .null
			case "true":
				self = .bool(true)
			case "false":
				self = .bool(false)
			default:
				if let int = Int(description) {
					self = .int(int)
				} else if let double = Double(description), description.contains(".") {
					self = .double(double)
				} else if let value = try? Event.Value(data: Data(description.utf8)) {
					self = value
				} else {
					self = .string(description)
				}
		}
	}
}

private extension String {

	var isSafeUnquotedEventDescriptionString: Bool {
		!contains(where: \.isBracketedDescriptionDelimiter) && Event.Value(eventDescription: self) == .string(self)
	}
}

private extension Character {

	var isBracketedDescriptionDelimiter: Bool {
		switch self {
			case "[", "]", "\"":
				return true
			default:
				return false
		}
	}
}
