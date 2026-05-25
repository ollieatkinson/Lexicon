//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum SwiftLexiconGenerator: SourceCodeGenerator {

	// TODO: prefixes?

	public static let utType = UTType.swiftSource
	public static let command = "swift"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try json.swift()
	}
}

private extension Lexicon.Graph.JSON {

	func swift() throws -> String {
		try SourceTemplate(
			"""
		@_exported import SwiftLexicon // https://github.com/thousandyears/Lexicon
		import Foundation

		public let {{root}} = L_{{root}}("{{root}}")

		{{types}}
		"""
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
				try SourceTemplate("public typealias {{className}} = {{baseClass}}").render([
					"className": names.className,
					"baseClass": names.className(for: protonym),
				])
			]
		}

		var lines = [
			try SourceTemplate(
				"""
				public final class {{className}}: {{baseClass}}, @unchecked Sendable, {{protocolName}} {
				\tpublic override class var localized: String { NSLocalizedString("{{localized}}", comment: "") }
				}
				"""
			).render([
				"className": names.className,
				"baseClass": names.classPrefix,
				"protocolName": names.protocolName,
				"localized": id,
			]),
			try SourceTemplate("public protocol {{protocolName}}: {{protocolBase}} {}").render([
				"protocolName": names.protocolName,
				"protocolBase": names.protocolBase(supertype: supertype),
			])
		]

		let properties = try swiftProperties(prefix: prefix)
		if !properties.isEmpty {
			lines.append(
				try SourceTemplate(
					"""
					public extension {{protocolName}} {
					{{properties}}
					}
					"""
				).render([
					"protocolName": names.protocolName,
					"properties": properties.joined(separator: "\n"),
				])
			)
		}

		return lines
	}

}
