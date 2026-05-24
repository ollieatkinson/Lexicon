//
// github.com/screensailor 2022
//

import Lexicon
import UniformTypeIdentifiers

public extension UTType {
	static var typescript = UTType(filenameExtension: "ts", conformingTo: .sourceCode)!
}

public enum TypeScriptStandAloneGenerator: SourceCodeGenerator {
	
	// TODO: prefixes?
	
	public static let utType = UTType.typescript
	public static let command = "ts"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try json.ts()
	}
}

private extension Lexicon.Graph.JSON {
	
	func ts() throws -> String {
		try SourceTemplate(
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
			const {{root}} = new L_{{root}}("{{root}}");

			"""
		).render([
			"root": name,
			"types": try classes.flatMap { try $0.ts(prefix: ("L", "I"), classes: classes) }.joined(separator: "\n"),
		])
	}
}

private extension Lexicon.Graph.Node.Class.JSON {
	
	func ts(prefix: (class: String, protocol: String), classes: [Lexicon.Graph.Node.Class.JSON]) throws -> [String] {
		
		guard mixin == nil else {
			return []
		}
		
		let names = StandAloneTypeNames(id: id, prefix: prefix)
		
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
					type {{protocolName}} = {{protocolAlias}};
					"""
				).render([
					"className": names.className,
					"baseClass": names.classPrefix,
					"protocolName": names.protocolName,
					"classBlock": typeScriptBlock(emptyTypeScriptClassMembers(prefix: prefix, classes: classes)),
					"protocolAlias": names.protocolBase(supertype: supertype),
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
				"baseClass": names.classPrefix,
				"protocolName": names.protocolName,
				"classBlock": typeScriptBlock(typeScriptClassMembers(prefix: prefix, classes: classes)),
				"protocolBase": names.protocolBase(supertype: supertype),
				"protocolBlock": typeScriptBlock(typeScriptProtocolMembers(prefix: prefix)),
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
		prefix: (class: String, protocol: String),
		classes: [Lexicon.Graph.Node.Class.JSON]
	) -> [String] {
		standAloneInheritedAccessors(classes: classes)
			.filter { !$0.isSynonym }
			.map { accessor in
				"  \(accessor.name)!: \(prefix.class)_\(accessor.sourceID.standAloneTypeSuffix);"
			}
	}

	func typeScriptClassMembers(prefix: (class: String, protocol: String), classes: [Lexicon.Graph.Node.Class.JSON]) -> [String] {
		var members: [String] = []
		for t in type ?? [] {
			let subClass = classes.first { $0.id == t }
			for accessor in subClass?.standAloneAccessors() ?? [] {
				let id = "\(prefix.class).\(accessor.sourceID)"
				members.append("  \(accessor.name)!: \(id.standAloneTypeSuffix);")
			}
		}

		for accessor in standAloneAccessors() {
			if accessor.isSynonym {
				members.append("  \(accessor.name) = this.\(accessor.pathSuffix);")
			} else {
				members.append("  \(accessor.name) = new \(prefix.class)_\(accessor.sourceID.standAloneTypeSuffix)(`${this.__}.\(accessor.name)`);")
			}
		}
		return members
	}

	func typeScriptProtocolMembers(prefix: (class: String, protocol: String)) -> [String] {
		standAloneAccessors().filter { !$0.isSynonym }.map { accessor in
			"  \(accessor.name): \(prefix.protocol)_\(accessor.sourceID.standAloneTypeSuffix);"
		}
	}
}
