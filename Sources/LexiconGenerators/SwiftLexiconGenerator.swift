//
// github.com/screensailor 2022
//

import Lexicon
import UniformTypeIdentifiers

public enum SwiftLexiconGenerator: SourceCodeGenerator {

	// TODO: prefixes?

	public static let utType = UTType.swiftSource
	public static let command = "swift"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		try json.swift()
	}
}

private extension Lexicon.Graph.JSON {

	func swift() throws -> String {
		try SourceTemplate(
			"""
		@_exported import SwiftLexicon // https://github.com/thousandyears/Lexicon
		import Foundation

		public let {{root}} = L_{{root}}("{{root}}")

		{{types}}
		"""
		).render([
			"root": name,
			"types": try classes.flatMap { try $0.swiftTypeDeclarations(prefix: ("L", "I")) }.joined(separator: "\n"),
		])
	}
}
