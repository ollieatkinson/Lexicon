//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum SwiftLexiconGenerator: SourceCodeGenerator {

	public static let utType = UTType.swiftSource
	public static let command = "swift"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try generateSource(json, prefixes: .default)
	}

	public static func generateSource(_ json: Lexicon.Graph.JSON, prefixes: StandAloneTypePrefixes) throws -> String {
		try json.swift(prefixes: prefixes)
	}
}

private extension Lexicon.Graph.JSON {

	func swift(prefixes: StandAloneTypePrefixes) throws -> String {
		try validateStandAloneRoot(
			language: "Swift",
			reserved: [
				"CallAsFunctionExtensions",
				"LexiconActor",
				"SourceCodeIdentifiable",
				"TypeLocalized",
			]
		)
		try validateStandAloneSymbols(prefixes: prefixes)
		try validateStandAloneMembers(
			language: "Swift",
			reserved: ["__", "debugDescription"]
		)
		let rootID = Lemma.ID(root: name)
		let root = rootID.description
		let names = StandAloneTypeNames(id: rootID, prefixes: prefixes)
		return try SourceTemplate(
			"""
		@_exported import SwiftLexicon // https://github.com/thousandyears/Lexicon
		import Foundation

		public let {{rootIdentifier}} = {{rootClassName}}("{{root}}")

		{{types}}
		"""
		).render([
			"root": root,
			"rootIdentifier": root.swiftDeclarationIdentifier,
			"rootClassName": names.className,
			"types": try classes.flatMap {
				try $0.swiftTypeDeclarations(prefixes: prefixes, classes: classes)
			}.joined(separator: "\n"),
		])
	}
}
