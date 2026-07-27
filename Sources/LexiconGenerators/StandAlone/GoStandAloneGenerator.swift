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
		try generateSource(json, packageName: "lexicon")
	}

	public static func generateSource(_ json: Lexicon.Graph.JSON, packageName: String) throws -> String {
		try json.go(packageName: packageName)
	}
}

private extension Lexicon.Graph.JSON {

	func go(packageName: String) throws -> String {
		try validateStandAloneSymbols(prefixes: .default)
		let rootSelector = name.goSelector
		guard !["I", "L", "Lemma"].contains(rootSelector) else {
			throw GoGenerationError.reservedSelector(owner: nil, selector: rootSelector)
		}
		for type in classes where type.mixin == nil {
			for accessor in try type.standAloneGeneratedAccessors(classes: classes)
			where ["ID", "L", "Localized"].contains(accessor.name.goSelector) {
				throw GoGenerationError.reservedSelector(
					owner: type.id,
					selector: accessor.name.goSelector
				)
			}
		}
		return try SourceTemplate(
			"""
		package {{packageName}}

		type I interface {
			ID() string
			Localized() string
		}

		type Lemma string

		func l(path string) Lemma {
			return Lemma(path)
		}

		func (l Lemma) ID() string {
			return string(l)
		}

		func (l Lemma) Localized() string {
			return string(l)
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
			"packageName": try packageName.goPackageName,
			"rootVariable": name.goSelector,
			"rootType": name.goTypeSuffix,
			"rootID": name.rawValue,
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
			let canonicalID = try classes.standAloneCanonicalID(
				for: protonym,
				referencedBy: id
			)
			return [
				try SourceTemplate("type {{type}} = L_{{protonym}}").render([
					"type": type,
					"protonym": canonicalID.goTypeSuffix,
				])
			]
		}

		let ownAccessors = try standAloneAccessors(classes: classes)
		let inheritedAccessors = try standAloneInheritedAccessors(classes: classes)
			.filter { inherited in !ownAccessors.contains(where: { $0.name == inherited.name }) }
		try (ownAccessors + inheritedAccessors).validateUniqueGoSelectors(owner: id)

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
				"localized": id.description,
				"fields": ownAccessors
					.map { "\n\t\($0.name.goSelector) L_\($0.sourceID.goTypeSuffix)" }
					.joined(),
				"initializers": ownAccessors
					.map { "\n\tl.\($0.name.goSelector) = \($0.factory(receiver: "id"))" }
					.joined(),
				"inherited": try inheritedAccessors
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
			"name": name.goSelector,
			"sourceType": sourceID.goTypeSuffix,
			"factory": factory(receiver: "l.id"),
		]))
	}
}

private extension Array where Element == StandAloneAccessor {

	func validateUniqueGoSelectors(owner: Lemma.ID) throws {
		var selectors: [String: Lemma.Name] = [:]
		for accessor in self {
			let selector = accessor.name.goSelector
			if let existing = selectors[selector], existing != accessor.name {
				throw GoGenerationError.selectorCollision(
					owner: owner,
					selector: selector,
					first: existing.rawValue,
					second: accessor.name.rawValue
				)
			}
			selectors[selector] = accessor.name
		}
	}
}

private extension String {

	var goTypeSuffix: String {
		split(separator: ".")
			.map(String.init)
			.map(\.goTypeSegment)
			.joined(separator: "_")
	}

	var goTypeSegment: String {
		goIdentifier.replacingOccurrences(of: "_", with: "__")
	}

	var goIdentifier: String {
		let normalized = precomposedStringWithCanonicalMapping
		let sanitized = normalized.unicodeScalars.map { scalar -> String in
			scalar == "_" || scalar.isGoIdentifierLetter || scalar.isGoIdentifierDigit
				? String(scalar)
				: "_"
		}
		return sanitized.joined().unlessEmpty ?? "lexicon"
	}

	var goSelector: String {
		var identifier = goIdentifier
		if identifier.first?.isNumber == true {
			identifier = "_\(identifier)"
		}
		guard let first = identifier.first else {
			return identifier
		}
		return first.uppercased() + String(identifier.dropFirst())
	}

	var goPackageName: String {
		get throws {
			let identifier = goIdentifier
			guard
				self == identifier,
				identifier != "_",
				identifier.first?.isNumber != true,
				!identifier.isGoKeyword
			else {
				throw GoGenerationError.invalidPackageName(self)
			}
			return identifier
		}
	}

	var isGoKeyword: Bool {
		switch self {
		case "break", "default", "func", "interface", "select",
			"case", "defer", "go", "map", "struct",
			"chan", "else", "goto", "package", "switch",
			"const", "fallthrough", "if", "range", "type",
			"continue", "for", "import", "return", "var":
			return true
		default:
			return false
		}
	}
}

private extension Unicode.Scalar {

	var isGoIdentifierLetter: Bool {
		switch properties.generalCategory {
			case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
				.modifierLetter, .otherLetter:
				return true
			default:
				return false
		}
	}

	var isGoIdentifierDigit: Bool {
		properties.generalCategory == .decimalNumber
	}
}

private extension Lemma.Name {

	var goTypeSuffix: String { rawValue.goTypeSuffix }
	var goSelector: String { rawValue.goSelector }
}

private extension Lemma.ID {

	var goTypeSuffix: String { description.goTypeSuffix }
}

private enum GoGenerationError: Error, CustomStringConvertible {
	case invalidPackageName(String)
	case reservedSelector(owner: Lemma.ID?, selector: String)
	case selectorCollision(owner: Lemma.ID, selector: String, first: String, second: String)

	var description: String {
		switch self {
		case .invalidPackageName(let packageName):
			"'\(packageName)' is not a valid Go package name."
		case .reservedSelector(let owner, let selector):
			if let owner {
				"Go reserves selector '\(selector)' in generated class '\(owner)'."
			} else {
				"Go root selector '\(selector)' conflicts with a generated base type."
			}
		case .selectorCollision(let owner, let selector, let first, let second):
			"""
			Go selector collision in '\(owner)': '\(first)' and '\(second)' both generate '\(selector)'.
			"""
		}
	}
}
