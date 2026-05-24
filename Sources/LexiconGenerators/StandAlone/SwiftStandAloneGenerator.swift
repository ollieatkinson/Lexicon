//
// github.com/screensailor 2022
//

import Lexicon
import UniformTypeIdentifiers

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
			"types": try classes.flatMap { try $0.swift(prefix: ("L", "I")) }.joined(separator: "\n"),
		])
	}
}

private extension Lexicon.Graph.Node.Class.JSON {
	
	func swift(prefix: (class: String, protocol: String)) throws -> [String] {
		
		guard mixin == nil else {
			return []
		}
		
		let names = StandAloneTypeNames(id: id, prefix: prefix)
		
		if let protonym = protonym {
			return [
				try SourceTemplate(
					"public typealias %%className%% = %%baseClass%%",
					delimiters: .percentSigns
				).render([
					"className": names.className,
					"baseClass": names.className(for: protonym),
				])
			]
		}
		
		var lines = [
			try SourceTemplate(
				"""
				public final class %%className%%: %%baseClass%%, @unchecked Sendable, %%protocolName%% {
					public override class var localized: String { NSLocalizedString("%%localized%%", comment: "") }
				}
				""",
				delimiters: .percentSigns
			).render([
				"className": names.className,
				"baseClass": names.classPrefix,
				"protocolName": names.protocolName,
				"localized": id,
			]),
			try SourceTemplate(
				"public protocol %%protocolName%%: %%protocolBase%% {}",
				delimiters: .percentSigns
			).render([
				"protocolName": names.protocolName,
				"protocolBase": names.protocolBase(supertype: supertype),
			])
		]

		let properties = try swiftProperties(prefix: prefix)
		if !properties.isEmpty {
			lines.append(
				try SourceTemplate(
					"""
					public extension %%protocolName%% {
					%%properties%%
					}
					""",
					delimiters: .percentSigns
				).render([
					"protocolName": names.protocolName,
					"properties": properties.joined(separator: "\n"),
				])
			)
		}
		
		return lines
	}

	func swiftProperties(prefix: (class: String, protocol: String)) throws -> [String] {
		let names = StandAloneTypeNames(id: id, prefix: prefix)
		var properties: [String] = []

		for accessor in standAloneAccessors() {
			let template = accessor.isSynonym
				? "\tvar `%%name%%`: %%className%% { %%protonym%% }"
				: "\tvar `%%name%%`: %%className%% { .init(\"\\(__).%%name%%\") }"
			properties.append(
				try SourceTemplate(
					template,
					delimiters: .percentSigns
				).render([
					"name": accessor.name,
					"className": names.className(for: accessor.sourceID),
					"protonym": accessor.pathSuffix,
				])
			)
		}

		return properties
	}
}
