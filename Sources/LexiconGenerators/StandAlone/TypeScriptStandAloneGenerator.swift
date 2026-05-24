//
// github.com/screensailor 2022
//

import Lexicon
import UniformTypeIdentifiers

public extension UTType {
	static var typescript = UTType(filenameExtension: "ts", conformingTo: .sourceCode)!
}

public enum TypeScriptStandAloneGenerator: CodeGenerator {
	
	// TODO: prefixes?
	
	public static let utType = UTType.typescript
	public static let command = "ts"

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		Data(try json.ts().utf8)
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
		
		let T = id.idToClassSuffix
		let (L, I) = prefix
		let className = "\(L)_\(T)"
		let protocolName = "\(I)_\(T)"
		
		if let protonym = protonym {
			return [
				try SourceTemplate("type {{className}} = {{baseClass}}").render([
					"className": className,
					"baseClass": "\(L)_\(protonym.idToClassSuffix)",
				])
			]
		}
		
		let supertype = supertype?
			.replacingOccurrences(of: "_", with: "__")
			.replacingOccurrences(of: ".", with: "_")
			.replacingOccurrences(of: "__&__", with: ", I_")
		
		if hasNoProperties {
			return [
				try SourceTemplate(
					"""
					class {{className}} extends {{baseClass}} implements {{protocolName}} {{classBlock}}
					type {{protocolName}} = {{protocolAlias}};
					"""
				).render([
					"className": className,
					"baseClass": L,
					"protocolName": protocolName,
					"classBlock": typeScriptBlock(emptyTypeScriptClassMembers(prefix: prefix, classes: classes, supertype: supertype)),
					"protocolAlias": supertype.map { "\(I)_\($0)" } ?? I,
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
				"className": className,
				"baseClass": L,
				"protocolName": protocolName,
				"classBlock": typeScriptBlock(typeScriptClassMembers(prefix: prefix, classes: classes)),
				"protocolBase": "\(I)\(supertype.map{ "_\($0)" } ?? "")",
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
		classes: [Lexicon.Graph.Node.Class.JSON],
		supertype: Lemma.ID?
	) -> [String] {
		guard let supertype else {
			return []
		}
		let superChildren = classes.first { $0.id == supertype }?.children ?? []
		return superChildren.map { child in
			"  \(child)!: \(prefix.class)_\(supertype)_\(child);"
		}
	}

	func typeScriptClassMembers(prefix: (class: String, protocol: String), classes: [Lexicon.Graph.Node.Class.JSON]) -> [String] {
		var members: [String] = []
		for t in type ?? [] {
			let subClass = classes.first { $0.id == t }
			for child in subClass?.children ?? [] {
				let id = "L.\(t).\(child)"
				members.append("  \(child)!: \(id.idToClassSuffix);")
			}
			for synonym in subClass?.synonyms?.keys.sorted() ?? [] {
				let id = "L.\(t).\(synonym)"
				members.append("  \(synonym)!: \(id.idToClassSuffix);")
			}
		}

		for child in children ?? [] {
			let id = "\(id).\(child)"
			members.append("  \(child) = new \(prefix.class)_\(id.idToClassSuffix)(`${this.__}.\(child)`);")
		}

		for (synonym, protonym) in (synonyms?.sorted(by: { $0.key < $1.key }) ?? []) {
			members.append("  \(synonym) = this.\(protonym);")
		}
		return members
	}

	func typeScriptProtocolMembers(prefix: (class: String, protocol: String)) -> [String] {
		(children ?? []).map { child in
			let id = "\(id).\(child)"
			return "  \(child): \(prefix.protocol)_\(id.idToClassSuffix);"
		}
	}
}

private extension String {
	var idToClassSuffix: String {
		replacingOccurrences(of: "_", with: "__")
			.replacingOccurrences(of: ".", with: "_")
			.replacingOccurrences(of: "_&_", with: "_")
	}
}
