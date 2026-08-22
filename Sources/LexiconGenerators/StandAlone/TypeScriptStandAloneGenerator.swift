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
		try validateStandAloneSymbols(prefixes: prefixes)
		try validateStandAloneMembers(
			language: "TypeScript",
			reserved: ["__", "constructor", "id"]
		)
		let rootID = Lemma.ID(root: name)
		let root = rootID.description
		let names = StandAloneTypeNames(id: rootID, prefixes: prefixes)
		let rootDeclaration = root.isTypeScriptBindingKeyword
			? """
			const __lexicon_root = new \(names.className)("\(root)");
			export { __lexicon_root as \(root) };
			"""
			: "export const \(root) = new \(names.className)(\"\(root)\");"
		return try SourceTemplate(
			"""
			export interface I { }

			// L
			export class L implements I {
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
			{{rootDeclaration}}

			"""
		).render([
			"rootDeclaration": rootDeclaration,
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
			let canonicalID = try classes.standAloneCanonicalID(
				for: protonym,
				referencedBy: id
			)
			return [
				try SourceTemplate("export type {{className}} = {{baseClass}}").render([
					"className": names.className,
					"baseClass": names.className(for: canonicalID),
				])
			]
		}
		
		if hasNoProperties {
			return [
				try SourceTemplate(
					"""
					export class {{className}} extends {{baseClass}} implements {{protocolName}} {{classBlock}}
					export interface {{protocolName}} extends {{protocolBase}} {{protocolBlock}}
					"""
				).render([
					"className": names.className,
					"baseClass": names.baseClassName,
					"protocolName": names.protocolName,
					"classBlock": typeScriptBlock(
						try emptyTypeScriptClassMembers(prefixes: prefixes, classes: classes)
					),
					"protocolBase": try names.protocolBase(supertype: supertype, classes: classes),
					"protocolBlock": typeScriptBlock([]),
				])
			]
		}

		return [
			try SourceTemplate(
				"""
				export class {{className}} extends {{baseClass}} implements {{protocolName}} {{classBlock}}
				export interface {{protocolName}} extends {{protocolBase}} {{protocolBlock}}
				"""
			).render([
				"className": names.className,
				"baseClass": names.baseClassName,
				"protocolName": names.protocolName,
				"classBlock": typeScriptBlock(
					try typeScriptClassMembers(prefixes: prefixes, classes: classes)
				),
				"protocolBase": try names.protocolBase(supertype: supertype, classes: classes),
				"protocolBlock": typeScriptBlock(
					try typeScriptProtocolMembers(prefixes: prefixes, classes: classes)
				),
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
	) throws -> [String] {
		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		return try typeScriptRuntimeAccessors(classes: classes).map { member in
			member.declaration(names: names)
		}
	}

	func typeScriptClassMembers(
		prefixes: StandAloneTypePrefixes,
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [String] {
		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		return try typeScriptRuntimeAccessors(classes: classes).map { member in
			member.declaration(names: names)
		}
	}

	func typeScriptRuntimeAccessors(
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [TypeScriptRuntimeMember] {
		var members: [TypeScriptRuntimeMember] = []
		func append(_ accessor: StandAloneAccessor, isOwn: Bool = false) {
			let member = TypeScriptRuntimeMember(accessor: accessor, isOwn: isOwn)
			if let index = members.firstIndex(where: { $0.accessor.name == accessor.name }) {
				members[index] = member
			} else {
				members.append(member)
			}
		}
		for accessor in try standAloneTypeAccessors(classes: classes) {
			append(accessor)
		}
		for accessor in try standAloneInheritedAccessors(classes: classes) {
			append(accessor)
		}
		for accessor in try standAloneAccessors(classes: classes) {
			append(accessor, isOwn: true)
		}
		return members
	}

	func typeScriptProtocolMembers(
		prefixes: StandAloneTypePrefixes,
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [String] {
		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		return try standAloneAccessors(classes: classes)
			.filter { !$0.isSynonym }
			.map { accessor in
			"  \(accessor.name.rawValue): \(names.protocolName(for: accessor.sourceID));"
		}
	}
}

private struct TypeScriptRuntimeMember {
	var accessor: StandAloneAccessor
	var isOwn: Bool

	func declaration(names: StandAloneTypeNames) -> String {
		let factory = accessor.typeScriptFactory(names: names)
		if isOwn {
			return "  \(accessor.name.rawValue) = \(factory);"
		}
		return "  get \(accessor.name.rawValue)() { return \(factory); }"
	}
}

private extension StandAloneAccessor {

	func typeScriptFactory(names: StandAloneTypeNames) -> String {
		"new \(names.className(for: targetID))(`${this.__}.\(pathSuffix)`)"
	}
}
