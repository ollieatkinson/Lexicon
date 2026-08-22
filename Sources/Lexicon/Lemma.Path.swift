//
// github.com/screensailor 2026
//

import Foundation

public extension Lemma {

	struct Name: Hashable, Comparable, Sendable, Codable, CustomStringConvertible,
		CustomDebugStringConvertible, ExpressibleByStringLiteral {

		public let rawValue: String

		public init(validating rawValue: String) throws {
			guard Self.isValid(rawValue) else {
				throw LexiconError("Invalid lemma name '\(rawValue)'")
			}
			self.rawValue = rawValue
		}

		public init(stringLiteral value: String) {
			guard let name = try? Self(validating: value) else {
				preconditionFailure("Invalid lemma name literal '\(value)'")
			}
			self = name
		}

		public init(from decoder: Decoder) throws {
			let container = try decoder.singleValueContainer()
			let rawValue = try container.decode(String.self)
			do {
				try self.init(validating: rawValue)
			} catch {
				throw DecodingError.dataCorruptedError(
					in: container,
					debugDescription: "Invalid lemma name '\(rawValue)'"
				)
			}
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			try container.encode(rawValue)
		}

		public var description: String { rawValue }
		public var debugDescription: String { rawValue.debugDescription }

		public static func < (lhs: Self, rhs: Self) -> Bool {
			lhs.rawValue < rhs.rawValue
		}

		public static func isValid(_ candidate: String) -> Bool {
			isValidPrefix(candidate) && candidate != "_"
		}

		public static func isValidPrefix(_ candidate: String) -> Bool {
			guard let first = candidate.first else {
				return false
			}
			guard first == "_" || first.isLexiconLetter else {
				return false
			}
			var previousWasUnderscore = false
			for character in candidate {
				guard character == "_" ||
					character.isLexiconLetter ||
					character.isLexiconDecimalDigit
				else {
					return false
				}
				if character == "_" {
					guard !previousWasUnderscore else {
						return false
					}
					previousWasUnderscore = true
				} else {
					previousWasUnderscore = false
				}
			}
			return true
		}
	}

	struct ID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible,
		CustomDebugStringConvertible, ExpressibleByStringLiteral {

		public let components: [Name]

		public init(components: [Name]) throws {
			guard components.isNotEmpty else {
				throw LexiconError("A lemma ID must contain at least one name")
			}
			self.components = components
		}

		public init(root: Name) {
			self.components = [root]
		}

		public init(parsing string: String) throws {
			let rawComponents = string.split(separator: ".", omittingEmptySubsequences: false)
			guard rawComponents.isNotEmpty else {
				throw LexiconError("A lemma ID must not be empty")
			}
			self.components = try rawComponents.map {
				try Name(validating: String($0))
			}
		}

		public init(stringLiteral value: String) {
			guard let id = try? Self(parsing: value) else {
				preconditionFailure("Invalid lemma ID literal '\(value)'")
			}
			self = id
		}

		public init(from decoder: Decoder) throws {
			let container = try decoder.singleValueContainer()
			let rawValue = try container.decode(String.self)
			do {
				try self.init(parsing: rawValue)
			} catch {
				throw DecodingError.dataCorruptedError(
					in: container,
					debugDescription: "Invalid lemma ID '\(rawValue)'"
				)
			}
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			try container.encode(description)
		}

		public var root: Name { components[0] }
		public var name: Name { components[components.endIndex - 1] }
		public var parent: Self? {
			guard components.count > 1 else {
				return nil
			}
			return try? Self(components: Array(components.dropLast()))
		}

		public func appending(_ name: Name) -> Self {
			try! Self(components: components + [name])
		}

		public func appending(_ relativeID: RelativeID) -> Self {
			try! Self(components: components + relativeID.components)
		}

		public func relative(to ancestor: Self) throws -> RelativeID {
			guard components.starts(with: ancestor.components), components.count > ancestor.components.count else {
				throw LexiconError("Lemma '\(self)' is not a descendant of '\(ancestor)'")
			}
			return try RelativeID(components: Array(components.dropFirst(ancestor.components.count)))
		}

		public func isAncestor(of other: Self) -> Bool {
			components.count < other.components.count && other.components.starts(with: components)
		}

		public func isDescendant(of other: Self) -> Bool {
			other.isAncestor(of: self)
		}

		public func isInLineage(of other: Self) -> Bool {
			self == other || isDescendant(of: other)
		}

		public var description: String {
			components.map(\.rawValue).joined(separator: ".")
		}

		public var debugDescription: String { description.debugDescription }

		public static func < (lhs: Self, rhs: Self) -> Bool {
			lhs.components.lexicographicallyPrecedes(rhs.components)
		}
	}

	struct RelativeID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible,
		CustomDebugStringConvertible, ExpressibleByStringLiteral {

		public let components: [Name]

		public init(components: [Name]) throws {
			guard components.isNotEmpty else {
				throw LexiconError("A relative lemma ID must contain at least one name")
			}
			self.components = components
		}

		public init(parsing string: String) throws {
			let rawComponents = string.split(separator: ".", omittingEmptySubsequences: false)
			guard rawComponents.isNotEmpty else {
				throw LexiconError("A relative lemma ID must not be empty")
			}
			self.components = try rawComponents.map {
				try Name(validating: String($0))
			}
		}

		public init(stringLiteral value: String) {
			guard let id = try? Self(parsing: value) else {
				preconditionFailure("Invalid relative lemma ID literal '\(value)'")
			}
			self = id
		}

		public init(from decoder: Decoder) throws {
			let container = try decoder.singleValueContainer()
			let rawValue = try container.decode(String.self)
			do {
				try self.init(parsing: rawValue)
			} catch {
				throw DecodingError.dataCorruptedError(
					in: container,
					debugDescription: "Invalid relative lemma ID '\(rawValue)'"
				)
			}
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			try container.encode(description)
		}

		public var name: Name { components[components.endIndex - 1] }

		public var description: String {
			components.map(\.rawValue).joined(separator: ".")
		}

		public var debugDescription: String { description.debugDescription }

		public static func < (lhs: Self, rhs: Self) -> Bool {
			lhs.components.lexicographicallyPrecedes(rhs.components)
		}
	}

	typealias Protonym = RelativeID
}

private extension Character {

	var isLexiconLetter: Bool {
		guard let first = unicodeScalars.first else {
			return false
		}
		switch first.properties.generalCategory {
			case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
				.modifierLetter, .otherLetter:
				break
			default:
				return false
		}
		return unicodeScalars.dropFirst().allSatisfy {
			switch $0.properties.generalCategory {
				case .nonspacingMark, .spacingMark, .enclosingMark:
					return true
				default:
					return false
			}
		}
	}

	var isLexiconDecimalDigit: Bool {
		unicodeScalars.isNotEmpty && unicodeScalars.allSatisfy {
			$0.properties.generalCategory == .decimalNumber
		}
	}
}
