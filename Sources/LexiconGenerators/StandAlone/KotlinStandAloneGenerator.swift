//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum KotlinStandAloneGenerator: SourceCodeGenerator {

	public static let utType = UTType(filenameExtension: "kt", conformingTo: .sourceCode)!
	public static let command = "kotlin"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try generateSource(json, prefixes: .default)
	}

	public static func generateSource(_ json: Lexicon.Graph.JSON, prefixes: StandAloneTypePrefixes) throws -> String {
		try json.kotlin(prefixes: prefixes)
	}
}

private extension Lexicon.Graph.JSON {

	func kotlin(prefixes: StandAloneTypePrefixes) throws -> String {
		try validateStandAloneSymbols(prefixes: prefixes)
		try validateStandAloneMembers(
			language: "Kotlin",
			reserved: ["debugDescription", "identifier", "localized"]
		)
		let rootID = Lemma.ID(root: name)
		let root = rootID.description
		let names = StandAloneTypeNames(id: rootID, prefixes: prefixes)
		return try SourceTemplate(
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

			val {{rootIdentifier}} = {{rootClassName}}("{{root}}")

			{{types}}

			"""
		).render([
			"root": root,
			"rootIdentifier": root.kotlinDeclarationIdentifier,
			"rootClassName": names.className,
			"types": try classes.flatMap {
				try $0.kotlin(prefixes: prefixes, classes: classes)
			}.joined(separator: "\n"),
		])
	}
}

private extension Lexicon.Graph.Node.Class.JSON {

	func kotlin(
		prefixes: StandAloneTypePrefixes,
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [String] {

		guard mixin == nil else {
			return []
		}

		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		
		if let protonym = protonym {
			let canonicalID = try classes.standAloneCanonicalID(
				for: protonym,
				referencedBy: id
			)
			return [
				try SourceTemplate("typealias {{className}} = {{baseClass}}").render([
					"className": names.className,
					"baseClass": names.className(for: canonicalID),
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
				"baseClass": names.baseClassName,
				"protocolName": names.protocolName,
				"protocolBase": try names.protocolBase(supertype: supertype, classes: classes),
			])
		]

		for accessor in try standAloneAccessors(classes: classes) {
			let template = accessor.isSynonym
				? "val {{protocolName}}.`{{name}}`: {{className}} get() = {{protonym}}"
				: "val {{protocolName}}.`{{name}}`: {{className}} get() = {{className}}(\"${identifier}.{{name}}\")"
			lines.append(
				try SourceTemplate(template)
					.render([
						"protocolName": names.protocolName,
						"name": accessor.name.rawValue,
						"className": names.className(for: accessor.sourceID),
						"protonym": accessor.pathSuffix.kotlinMemberPath,
					])
			)
		}
		
		return lines
	}
	
}
