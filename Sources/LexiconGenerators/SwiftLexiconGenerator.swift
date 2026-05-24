//
// github.com/screensailor 2022
//

import Foundation
import Lexicon
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum SwiftLexiconGenerator: SourceCodeGenerator {

	// TODO: prefixes?

	public static let utType = UTType.swiftSource
	public static let command = "swift"

	public static func generateSource(_ json: Lexicon.Graph.JSON) throws -> String {
		json.swift()
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
		let names = StandAloneTypeNames(id: id, prefix: prefix)

		if let protonym = protonym {
			lines += "public typealias \(names.className) = \(names.className(for: protonym))"
			return lines
		}

		lines += """
		public final class \(names.className): \(names.classPrefix), @unchecked Sendable, \(names.protocolName) {
		\tpublic override class var localized: String { NSLocalizedString("\(id)", comment: "") }
		}
		"""

		lines += "public protocol \(names.protocolName): \(names.protocolBase(supertype: supertype)) {}"

		guard hasProperties else {
			return lines
		}

		let line = "public extension \(names.protocolName)"

		lines += line + " {"

		for accessor in standAloneAccessors() {
			let body = accessor.isSynonym ? accessor.pathSuffix : ".init(\"\\(__).\(accessor.name)\")"
			lines += "\tvar `\(accessor.name)`: \(names.className(for: accessor.sourceID)) { \(body) }"
		}

		lines += "}"

		return lines
	}

}
