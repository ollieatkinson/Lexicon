//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum SwiftStandAloneGenerator: CodeGenerator {
	
	// TODO: prefixes?
	
	public static let utType = UTType.swiftSource
	public static let command = "swift-standalone"

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		Data(try json.swift().utf8)
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
		
		let T = id.standAloneTypeSuffix
		let (L, I) = prefix
		let className = "\(L)_\(T)"
		let protocolName = "\(I)_\(T)"
		
		if let protonym = protonym {
			return [
				try SourceTemplate(
					"public typealias %%className%% = %%baseClass%%",
					delimiters: .percentSigns
				).render([
					"className": className,
					"baseClass": "\(L)_\(protonym.standAloneTypeSuffix)",
				])
			]
		}
		
		let supertype = supertype?
			.replacingOccurrences(of: "_", with: "__")
			.replacingOccurrences(of: ".", with: "_")
			.replacingOccurrences(of: "__&__", with: ", I_")
		
		var lines = [
			try SourceTemplate(
				"""
				public final class %%className%%: %%baseClass%%, @unchecked Sendable, %%protocolName%% {
					public override class var localized: String { NSLocalizedString("%%localized%%", comment: "") }
				}
				""",
				delimiters: .percentSigns
			).render([
				"className": className,
				"baseClass": L,
				"protocolName": protocolName,
				"localized": id,
			]),
			try SourceTemplate(
				"public protocol %%protocolName%%: %%protocolBase%% {}",
				delimiters: .percentSigns
			).render([
				"protocolName": protocolName,
				"protocolBase": "\(I)\(supertype.map{ "_\($0)" } ?? "")",
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
					"protocolName": protocolName,
					"properties": properties.joined(separator: "\n"),
				])
			)
		}
		
		return lines
	}

	func swiftProperties(prefix: (class: String, protocol: String)) throws -> [String] {
		let L = prefix.class
		var properties: [String] = []

		for child in children ?? [] {
			let id = "\(id).\(child)"
			properties.append(
				try SourceTemplate(
					"\tvar `%%name%%`: %%className%% { .init(\"\\(__).%%name%%\") }",
					delimiters: .percentSigns
				).render([
					"name": child,
					"className": "\(L)_\(id.standAloneTypeSuffix)",
				])
			)
		}

		for (synonym, protonym) in (synonyms?.sorted(by: { $0.key < $1.key }) ?? []) {
			let id = "\(id).\(synonym)"
			properties.append(
				try SourceTemplate(
					"\tvar `%%name%%`: %%className%% { %%protonym%% }",
					delimiters: .percentSigns
				).render([
					"name": synonym,
					"className": "\(L)_\(id.standAloneTypeSuffix)",
					"protonym": protonym,
				])
			)
		}
		return properties
	}
}
