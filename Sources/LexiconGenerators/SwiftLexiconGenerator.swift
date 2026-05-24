//
// github.com/screensailor 2022
//

import Lexicon
import UniformTypeIdentifiers

public enum SwiftLexiconGenerator: CodeGenerator {

	// TODO: prefixes?

	public static let utType = UTType.swiftSource
	public static let command = "swift"

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		Data(json.swift().utf8)
	}
}

private extension Lexicon.Graph.JSON {

	func swift() -> String {

		return """
		@_exported import SwiftLexicon // https://github.com/thousandyears/Lexicon
		import Foundation

		public let \(name) = L_\(name)("\(name)")

		\(classes.flatMap{ $0.swift(prefix: ("L", "I")) }.joined(separator: "\n"))
		"""
	}
}

private extension Lexicon.Graph.Node.Class.JSON {

	// TODO: make this more readable

	func swift(prefix: (class: String, protocol: String)) -> [String] {

		guard mixin == nil else {
			return []
		}

		var lines: [String] = []
		let T = id.standAloneTypeSuffix
		let (L, I) = prefix

		if let protonym = protonym {
			lines += "public typealias \(L)_\(T) = \(L)_\(protonym.standAloneTypeSuffix)"
			return lines
		}

		lines += """
		public final class \(L)_\(T): L, @unchecked Sendable, \(I)_\(T) {
		\tpublic override class var localized: String { NSLocalizedString("\(id)", comment: "") }
		}
		"""

		let supertype = supertype?
			.replacingOccurrences(of: "_", with: "__")
			.replacingOccurrences(of: ".", with: "_")
			.replacingOccurrences(of: "__&__", with: ", I_")

		lines += "public protocol \(I)_\(T): \(I)\(supertype.map{ "_\($0)" } ?? "") {}"

		guard hasProperties else {
			return lines
		}

		let line = "public extension \(I)_\(T)"

		lines += line + " {"

		for child in children ?? [] {
			let id = "\(id).\(child)"
			lines += "\tvar `\(child)`: \(L)_\(id.standAloneTypeSuffix) { .init(\"\\(__).\(child)\") }"
		}

		for (synonym, protonym) in (synonyms?.sortedByLocalizedStandard(by: \.key) ?? []) {
			let id = "\(id).\(synonym)"
			lines += "\tvar `\(synonym)`: \(L)_\(id.standAloneTypeSuffix) { \(protonym) }"
		}

		lines += "}"

		return lines
	}

}
