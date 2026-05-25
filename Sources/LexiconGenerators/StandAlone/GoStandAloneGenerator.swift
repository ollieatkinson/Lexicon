//
// github.com/screensailor 2026
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum GoStandAloneGenerator: SourceCodeGenerator {

	public static let utType = UTType(filenameExtension: "go", conformingTo: .sourceCode)!
	public static let command = "go"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try json.go()
	}
}

private extension Lexicon.Graph.JSON {

	func go() throws -> String {
		try SourceTemplate(
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

		var {{rootVariable}} = new_L_{{rootType}}("{{rootID}}")

		{{types}}
		"""
		).render([
			"rootVariable": name.goIdentifier,
			"rootType": name.goTypeSuffix,
			"rootID": name,
			"types": try classes.flatMap { try $0.go(classes: classes) }.joined(separator: "\n\n"),
		]) + "\n"
	}
}

private extension Lexicon.Graph.Node.Class.JSON {

	func go(classes: [Lexicon.Graph.Node.Class.JSON]) throws -> [String] {
		guard mixin == nil else {
			return []
		}

		let type = "L_\(id.goTypeSuffix)"

		if let protonym = protonym {
			return [
				try SourceTemplate("type {{type}} = L_{{protonym}}").render([
					"type": type,
					"protonym": protonym.goTypeSuffix,
				])
			]
		}

		let ownAccessors = standAloneAccessors()
		return [
			try SourceTemplate(
				"""
				type {{type}} struct {
					L{{fields}}
				}

				func new_{{type}}(id string) {{type}} {
					l := {{type}}{L: L{id}}{{initializers}}
					return l
				}

				func (l {{type}}) Localized() string {
					return "{{localized}}"
				}{{inherited}}
				"""
			).render([
				"type": type,
				"localized": id,
				"fields": ownAccessors
					.map { "\n\t\($0.name.goIdentifier) L_\($0.sourceID.goTypeSuffix)" }
					.joined(),
				"initializers": ownAccessors
					.map { "\n\tl.\($0.name.goIdentifier) = \($0.factory(receiver: "id"))" }
					.joined(),
				"inherited": try standAloneInheritedAccessors(classes: classes)
					.filter { inherited in !ownAccessors.contains(where: { $0.name == inherited.name }) }
					.map { try $0.method(receiverType: type) }
					.joined(),
			])
		]
	}
}

private extension StandAloneAccessor {

	func factory(receiver: String) -> String {
		"new_L_\(targetID.goTypeSuffix)(\(receiver) + \".\(pathSuffix)\")"
	}

	func method(receiverType: String) throws -> String {
		"\n\n" + (try SourceTemplate(
			"""
			func (l {{receiverType}}) {{name}}() L_{{sourceType}} {
				return {{factory}}
			}
			"""
		).render([
			"receiverType": receiverType,
			"name": name.goIdentifier,
			"sourceType": sourceID.goTypeSuffix,
			"factory": factory(receiver: "l.id"),
		]))
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
