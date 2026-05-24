//
// github.com/screensailor 2026
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum GoStandAloneGenerator: CodeGenerator {

	public static let utType = UTType(filenameExtension: "go", conformingTo: .sourceCode)!
	public static let command = "go"

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		Data(json.go().utf8)
	}
}

private extension Lexicon.Graph.JSON {

	func go() -> String {
		"""
		package lexicon

		type I interface {
			ID() string
			Localized() string
		}

		type L struct {
			id string
		}

		func (l L) ID() string {
			return l.id
		}

		func (l L) Localized() string {
			return l.id
		}

		var \(name.goIdentifier) = new_L_\(name.goTypeSuffix)("\(name)")

		\(classes.flatMap { $0.go(classes: classes) }.joined(separator: "\n\n"))
		"""
		+ "\n"
	}
}

private extension Lexicon.Graph.Node.Class.JSON {

	func go(classes: [Lexicon.Graph.Node.Class.JSON]) -> [String] {
		guard mixin == nil else {
			return []
		}

		let type = "L_\(id.goTypeSuffix)"

		if let protonym = protonym {
			return ["type \(type) = L_\(protonym.goTypeSuffix)"]
		}

		var lines: [String] = [
			"type \(type) struct {",
			"\tL",
		]

		let ownAccessors = ownAccessors()
		for accessor in ownAccessors {
			lines += "\t\(accessor.name.goIdentifier) L_\(accessor.sourceID.goTypeSuffix)"
		}

		lines += [
			"}",
			"",
			"func new_\(type)(id string) \(type) {",
			"\tl := \(type){L: L{id}}",
		]

		for accessor in ownAccessors {
			lines += "\tl.\(accessor.name.goIdentifier) = \(accessor.factory(receiver: "id"))"
		}

		lines += [
			"\treturn l",
			"}",
			"",
			"func (l \(type)) Localized() string {",
			"\treturn \"\(id)\"",
			"}",
		]

		for accessor in inheritedAccessors(classes: classes) where !ownAccessors.contains(where: { $0.name == accessor.name }) {
			lines += [
				"",
				"func (l \(type)) \(accessor.name.goIdentifier)() L_\(accessor.sourceID.goTypeSuffix) {",
				"\treturn \(accessor.factory(receiver: "l.id"))",
				"}",
			]
		}

		return [lines.joined(separator: "\n")]
	}
}

private extension Lexicon.Graph.Node.Class.JSON {

	struct Accessor {
		var name: String
		var sourceID: String
		var targetID: String
		var pathSuffix: String
		var isSynonym: Bool

		func factory(receiver: String) -> String {
			"new_L_\(targetID.goTypeSuffix)(\(receiver) + \".\(pathSuffix)\")"
		}
	}

	func ownAccessors() -> [Accessor] {
		var accessors: [String: Accessor] = [:]
		for child in children ?? [] {
			let childID = "\(id).\(child)"
			accessors[child] = .init(
				name: child,
				sourceID: childID,
				targetID: childID,
				pathSuffix: child,
				isSynonym: false
			)
		}

		for (synonym, protonym) in (synonyms?.sortedByLocalizedStandard(by: \.key) ?? []) {
			let synonymID = "\(id).\(synonym)"
			let targetID = "\(id).\(protonym)"
			accessors[synonym] = .init(
				name: synonym,
				sourceID: synonymID,
				targetID: targetID,
				pathSuffix: protonym,
				isSynonym: true
			)
		}

		return accessors.values.sorted { lhs, rhs in
			if lhs.isSynonym != rhs.isSynonym {
				return !lhs.isSynonym
			}
			return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
		}
	}

	func allAccessors(classes: [Lexicon.Graph.Node.Class.JSON]) -> [Accessor] {
		var accessors = Dictionary(uniqueKeysWithValues: inheritedAccessors(classes: classes).map { ($0.name, $0) })
		for accessor in ownAccessors() {
			accessors[accessor.name] = accessor
		}
		return accessors.values.sortedByLocalizedStandard(by: \.name)
	}

	func inheritedAccessors(classes: [Lexicon.Graph.Node.Class.JSON]) -> [Accessor] {
		guard let supertype = supertype else {
			return []
		}
		guard let klass = classes.first(where: { $0.id == supertype }) else {
			return []
		}
		if let mixin = klass.mixin {
			var accessors = Dictionary(uniqueKeysWithValues: klass.inheritedAccessors(classes: classes).map { ($0.name, $0) })
			for (name, id) in mixin.children?.sortedByLocalizedStandard(by: \.key) ?? [] {
				accessors[name] = .init(
					name: name,
					sourceID: id,
					targetID: id,
					pathSuffix: name,
					isSynonym: false
				)
			}
			return accessors.values.sortedByLocalizedStandard(by: \.name)
		} else {
			return klass.allAccessors(classes: classes)
		}
	}
}

private extension String {

	var goTypeSuffix: String {
		split(separator: ".")
			.map(String.init)
			.map(\.goIdentifier)
			.joined(separator: "_")
	}

	var goIdentifier: String {
		let sanitized = map { character -> Character in
			character.isLetter || character.isNumber ? character : "_"
		}
		var identifier = String(sanitized).unlessEmpty ?? "lexicon"
		if identifier.first?.isNumber == true {
			identifier = "_\(identifier)"
		}
		if Self.goKeywords.contains(identifier) {
			identifier += "_"
		}
		return identifier
	}

	static let goKeywords: Set<String> = [
		"break",
		"default",
		"func",
		"interface",
		"select",
		"case",
		"defer",
		"go",
		"map",
		"struct",
		"chan",
		"else",
		"goto",
		"package",
		"switch",
		"const",
		"fallthrough",
		"if",
		"range",
		"type",
		"continue",
		"for",
		"import",
		"return",
		"var",
	]
}
