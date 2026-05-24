//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum KotlinStandAloneGenerator: SourceCodeGenerator {
	
	// TODO: prefixes?
	
	public static let utType = UTType(filenameExtension: "kt", conformingTo: .sourceCode)!
	public static let command = "kotlin"
	
	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try json.kotlin()
	}
}

private extension Lexicon.Graph.JSON {
	
	func kotlin() throws -> String {
		try SourceTemplate(
			"""
			interface I: TypeLocalized, SourceCodeIdentifiable

			interface TypeLocalized {
				val localized: String
			}

			interface SourceCodeIdentifiable {
				val identifier: String
			}

			val SourceCodeIdentifiable.debugDescription get() = identifier

			open class L(override val localized: String = "", override val identifier: String,) : I

			// MARK: generated types

			val {{root}} = L_{{root}}("{{root}}")

			{{types}}

			"""
		).render([
			"root": name,
			"types": try classes.flatMap { try $0.kotlin(prefix: ("L", "I")) }.joined(separator: "\n"),
		])
	}
}

private extension Lexicon.Graph.Node.Class.JSON {
	
	func kotlin(prefix: (class: String, protocol: String)) throws -> [String] {
		
		guard mixin == nil else {
			return []
		}
		
		let names = StandAloneTypeNames(id: id, prefix: prefix)
		
		if let protonym = protonym {
			return [
				try SourceTemplate("typealias {{className}} = {{baseClass}}").render([
					"className": names.className,
					"baseClass": names.className(for: protonym),
				])
			]
		}
		
		var lines = [
			try SourceTemplate(
				"""
				data class {{className}}(override val identifier: String): {{baseClass}}(identifier = identifier), {{protocolName}}
				interface {{protocolName}}: {{protocolBase}}
				"""
			).render([
				"className": names.className,
				"baseClass": names.classPrefix,
				"protocolName": names.protocolName,
				"protocolBase": names.protocolBase(supertype: supertype),
			])
		]

		for accessor in standAloneAccessors() {
			let template = accessor.isSynonym
				? "val {{protocolName}}.`{{name}}`: {{className}} get() = {{protonym}}"
				: "val {{protocolName}}.`{{name}}`: {{className}} get() = {{className}}(\"${identifier}.{{name}}\")"
			lines.append(
				try SourceTemplate(template)
					.render([
						"protocolName": names.protocolName,
						"name": accessor.name,
						"className": names.className(for: accessor.sourceID),
						"protonym": accessor.pathSuffix,
					])
			)
		}
		
		return lines
	}
	
}
