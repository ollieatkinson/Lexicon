//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum SwiftStandAloneGenerator: SourceCodeGenerator {
	
	// TODO: prefixes?
	
	public static let utType = UTType.swiftSource
	public static let command = "swift-standalone"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try json.swift()
	}
}

private extension Lexicon.Graph.JSON {
	
	func swift() throws -> String {
		try SourceTemplate(
			"""
		import Foundation
		
		// MARK: I
		
		public protocol I: Sendable, TypeLocalized, SourceCodeIdentifiable {}

		public protocol TypeLocalized {
			static var localized: String { get }
		}

		public protocol SourceCodeIdentifiable: CustomDebugStringConvertible {
			var __: String { get }
		}

		public extension SourceCodeIdentifiable {
			@inlinable var debugDescription: String { __ }
		}

		public enum CallAsFunctionExtensions<X> {
			case from
		}

		public extension I {
			func callAsFunction<Property>(_ keyPath: KeyPath<CallAsFunctionExtensions<I>, (I) -> Property>) -> Property {
				CallAsFunctionExtensions.from[keyPath: keyPath](self)
			}
		}

		public extension CallAsFunctionExtensions where X == I {
			var id: (I) -> String {{ $0.__ }}
			var localizedType: (I) -> String {{ type(of: $0).localized }}
		}
		
		// MARK: L
		
		open class L: @unchecked Sendable, Hashable, I {
			open class var localized: String { "" }
			public let __: String
			public required init(_ id: String) { __ = id }
		}
		
		public extension L {
			static func == (lhs: L, rhs: L) -> Bool { lhs.__ == rhs.__ }
			func hash(into hasher: inout Hasher) { hasher.combine(__) }
		}
		
		// MARK: generated types
		
		public let %%root%% = L_%%root%%("%%root%%")
		
		%%types%%
		""",
			delimiters: .percentSigns
		).render([
			"root": name,
			"types": try classes.flatMap { try $0.swiftTypeDeclarations(prefix: ("L", "I")) }.joined(separator: "\n"),
		])
	}
}
