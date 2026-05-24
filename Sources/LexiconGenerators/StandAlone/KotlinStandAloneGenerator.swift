//
// github.com/screensailor 2022
//

import Lexicon
import UniformTypeIdentifiers

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
		
		let T = id.standAloneTypeSuffix
		let (L, I) = prefix
		let className = "\(L)_\(T)"
		let protocolName = "\(I)_\(T)"
		
		if let protonym = protonym {
			return [
				try SourceTemplate("typealias {{className}} = {{baseClass}}").render([
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
				data class {{className}}(override val identifier: String): {{baseClass}}(identifier = identifier), {{protocolName}}
				interface {{protocolName}}: {{protocolBase}}
				"""
			).render([
				"className": className,
				"baseClass": L,
				"protocolName": protocolName,
				"protocolBase": "\(I)\(supertype.map{ "_\($0)" } ?? "")",
			])
		]

		for child in children ?? [] {
			let id = "\(id).\(child)"
			lines.append(
				try SourceTemplate("val {{protocolName}}.`{{name}}`: {{className}} get() = {{className}}(\"${identifier}.{{name}}\")")
					.render([
						"protocolName": protocolName,
						"name": child,
						"className": "\(L)_\(id.standAloneTypeSuffix)",
					])
			)
		}
		
		for (synonym, protonym) in (synonyms?.sorted(by: { $0.key < $1.key }) ?? []) {
			let id = "\(id).\(synonym)"
			lines.append(
				try SourceTemplate("val {{protocolName}}.`{{name}}`: {{className}} get() = {{protonym}}")
					.render([
						"protocolName": protocolName,
						"name": synonym,
						"className": "\(L)_\(id.standAloneTypeSuffix)",
						"protonym": protonym,
					])
			)
		}
		
		return lines
	}
	
}
