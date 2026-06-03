//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public extension UTType {
	static let typescript = UTType(filenameExtension: "ts", conformingTo: .sourceCode)!
}

public enum TypeScriptStandAloneGenerator: SourceCodeGenerator {

	public static let utType = UTType.typescript
	public static let command = "ts"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try generateSource(json, prefixes: .default)
	}

	public static func generateSource(_ json: Lexicon.Graph.JSON, prefixes: StandAloneTypePrefixes) throws -> String {
		try json.ts(prefixes: prefixes)
	}
}

private extension Lexicon.Graph.JSON {

	func ts(prefixes: StandAloneTypePrefixes) throws -> String {
		let names = StandAloneTypeNames(id: name, prefixes: prefixes)
		return try SourceTemplate(
			"""
			interface I { }

			// L
			class L implements I {
				protected id: string;
				constructor(id: string) {
					this.id = id;
				}
				get ['__']() {
					return this.id;
				}
			}

			// MARK: generated types
			{{types}}
			const {{root}} = new {{rootClassName}}("{{root}}");

			"""
		).render([
			"root": name,
			"rootClassName": names.className,
			"types": try classes.flatMap { try $0.ts(prefixes: prefixes, classes: classes) }.joined(separator: "\n"),
		])
	}
}

private extension Lexicon.Graph.Node.Class.JSON {

	func ts(prefixes: StandAloneTypePrefixes, classes: [Lexicon.Graph.Node.Class.JSON]) throws -> [String] {

		guard mixin == nil else {
			return []
		}

		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		
		if let protonym = protonym {
			return [
				try SourceTemplate("type {{className}} = {{baseClass}}").render([
					"className": names.className,
					"baseClass": names.className(for: protonym),
				])
			]
		}
		
		if hasNoProperties {
			return [
				try SourceTemplate(
					"""
					class {{className}} extends {{baseClass}} implements {{protocolName}} {{classBlock}}
					interface {{protocolName}} extends {{protocolBase}} {{protocolBlock}}
					"""
				).render([
					"className": names.className,
					"baseClass": names.baseClassName,
					"protocolName": names.protocolName,
					"classBlock": typeScriptBlock(emptyTypeScriptClassMembers(prefixes: prefixes, classes: classes)),
					"protocolBase": names.protocolBase(supertype: supertype),
					"protocolBlock": typeScriptBlock([]),
				])
			]
		}

		return [
			try SourceTemplate(
				"""
				class {{className}} extends {{baseClass}} implements {{protocolName}} {{classBlock}}
				interface {{protocolName}} extends {{protocolBase}} {{protocolBlock}}
				"""
			).render([
				"className": names.className,
				"baseClass": names.baseClassName,
				"protocolName": names.protocolName,
				"classBlock": typeScriptBlock(typeScriptClassMembers(prefixes: prefixes, classes: classes)),
				"protocolBase": names.protocolBase(supertype: supertype),
				"protocolBlock": typeScriptBlock(typeScriptProtocolMembers(prefixes: prefixes)),
			])
		]
	}

	func typeScriptBlock(_ members: [String]) -> String {
		guard !members.isEmpty else {
			return "{\n}"
		}
		return "{\n\(members.joined(separator: "\n"))\n}"
	}

	func emptyTypeScriptClassMembers(
		prefixes: StandAloneTypePrefixes,
		classes: [Lexicon.Graph.Node.Class.JSON]
	) -> [String] {
		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		return standAloneInheritedAccessors(classes: classes)
			.filter { !$0.isSynonym }
			.map { accessor in
				"  \(accessor.name)!: \(names.className(for: accessor.sourceID));"
		}
	}

	func typeScriptClassMembers(prefixes: StandAloneTypePrefixes, classes: [Lexicon.Graph.Node.Class.JSON]) -> [String] {
		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		let typeMembers = standAloneTypeAccessors(classes: classes).map { accessor in
			"  \(accessor.name)!: \(names.className(for: accessor.sourceID));"
		}

		let ownMembers = standAloneAccessors().map { accessor in
			if accessor.isSynonym {
				"  \(accessor.name) = this.\(accessor.pathSuffix);"
			} else {
				"  \(accessor.name) = new \(names.className(for: accessor.sourceID))(`${this.__}.\(accessor.name)`);"
			}
		}

		return typeMembers + ownMembers
	}

	func typeScriptProtocolMembers(prefixes: StandAloneTypePrefixes) -> [String] {
		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		return standAloneAccessors().filter { !$0.isSynonym }.map { accessor in
			"  \(accessor.name): \(names.protocolName(for: accessor.sourceID));"
		}
	}
}
