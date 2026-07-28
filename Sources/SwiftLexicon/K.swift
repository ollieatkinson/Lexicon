//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
import _JSON

public extension I where Self: L {

	/// Attaches a directly representable event value to this lemma.
	subscript<Value>(value: Value) -> K<Self> where Value: EventValueConvertible {
		K(self, [self: value.eventValue])
	}

	/// Validates and attaches an arbitrary JSON event value to this lemma.
	subscript(value: Event.Value) -> K<Self> {
		get throws {
			try K(self, [self: Event.Value.encoded(value)])
		}
	}

	/// Encodes a custom value as JSON and attaches it to this lemma.
	func encoding<Value>(_ value: Value) throws -> K<Self>
	where Value: Sendable, Value: Hashable, Value: Encodable {
		try K(self, [self: Event.Value.encoded(value)])
	}
}

/// A value that can be attached to an event without a fallible encoding step.
public protocol EventValueConvertible: Sendable, Hashable {
	var eventValue: Event.Value { get }
}

extension String: EventValueConvertible {
	public var eventValue: Event.Value { .string(self) }
}

extension Bool: EventValueConvertible {
	public var eventValue: Event.Value { .bool(self) }
}

extension Int: EventValueConvertible {
	public var eventValue: Event.Value { .int(self) }
}

extension Int8: EventValueConvertible {
	public var eventValue: Event.Value { .int(Int(self)) }
}

extension Int16: EventValueConvertible {
	public var eventValue: Event.Value { .int(Int(self)) }
}

extension Int32: EventValueConvertible {
	public var eventValue: Event.Value { .int(Int(self)) }
}

extension UInt8: EventValueConvertible {
	public var eventValue: Event.Value { .int(Int(self)) }
}

extension UInt16: EventValueConvertible {
	public var eventValue: Event.Value { .int(Int(self)) }
}

extension UInt32: EventValueConvertible {
	public var eventValue: Event.Value { .int(Int(self)) }
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

	/// Attaches a directly representable event value to the current lemma in the path.
	subscript<Value>(value: Value) -> K<A> where Value: EventValueConvertible {
		K(___, ____.merging([___: value.eventValue], uniquingKeysWith: { _, last in last }))
	}

	/// Validates and attaches an arbitrary JSON event value to the current lemma in the path.
	subscript(value: Event.Value) -> K<A> {
		get throws {
			try K(
				___,
				____.merging(
					[___: Event.Value.encoded(value)],
					uniquingKeysWith: { _, last in last }
				)
			)
		}
	}

	/// Encodes a custom value as JSON and attaches it to the current lemma in the path.
	func encoding<Value>(_ value: Value) throws -> K<A>
	where Value: Sendable, Value: Hashable, Value: Encodable {
		try K(
			___,
			____.merging([___: Event.Value.encoded(value)], uniquingKeysWith: { _, last in last })
		)
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
