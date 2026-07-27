//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum SwiftStandAloneGenerator: SourceCodeGenerator {

	public static let utType = UTType.swiftSource
	public static let command = "swift-standalone"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try generateSource(json, prefixes: .default)
	}

	public static func generateSource(_ json: Lexicon.Graph.JSON, prefixes: StandAloneTypePrefixes) throws -> String {
		try json.swift(prefixes: prefixes)
	}
}

private extension Lexicon.Graph.JSON {

	func swift(prefixes: StandAloneTypePrefixes) throws -> String {
		try validateStandAloneRoot(
			language: "Swift",
			reserved: [
				"CallAsFunctionExtensions",
				"LexiconActor",
				"SourceCodeIdentifiable",
				"TypeLocalized",
			]
		)
		try validateStandAloneSymbols(prefixes: prefixes)
		try validateStandAloneMembers(
			language: "Swift",
			reserved: ["__", "debugDescription"]
		)
		let rootID = Lemma.ID(root: name)
		let root = rootID.description
		let names = StandAloneTypeNames(id: rootID, prefixes: prefixes)
		return try SourceTemplate(
			"""
		import Foundation

		@globalActor
		public actor LexiconActor {
			public static let shared = LexiconActor()
		}
		
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
		
		@LexiconActor open class L: Hashable, I {
			nonisolated open class var localized: String { "" }
			public let __: String
			nonisolated public required init(_ id: String) { __ = id }
		}
		
		public extension L {
			nonisolated static func == (lhs: L, rhs: L) -> Bool { lhs.__ == rhs.__ }
			nonisolated func hash(into hasher: inout Hasher) { hasher.combine(__) }
		}
		
		// MARK: generated types
		
		public let %%rootIdentifier%% = %%rootClassName%%("%%root%%")
		
		%%types%%
		""",
			delimiters: .percentSigns
		).render([
			"root": root,
			"rootIdentifier": root.swiftDeclarationIdentifier,
			"rootClassName": names.className,
			"types": try classes.flatMap {
				try $0.swiftTypeDeclarations(prefixes: prefixes, classes: classes)
			}.joined(separator: "\n"),
		])
	}
}
