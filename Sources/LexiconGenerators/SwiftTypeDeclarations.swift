//
// github.com/screensailor 2026
//

import Lexicon

extension Lexicon.Graph.Node.Class.JSON {

	func swiftTypeDeclarations(
		prefixes: StandAloneTypePrefixes,
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [String] {
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
				try SourceTemplate(
					"public typealias %%className%% = %%baseClass%%",
					delimiters: .percentSigns
				).render([
					"className": names.className,
					"baseClass": names.className(for: canonicalID),
				])
			]
		}

		var lines = [
				try SourceTemplate(
					"""
				public final class %%className%%: %%baseClass%%, %%protocolName%% {
					public nonisolated override class var localized: String { NSLocalizedString("%%localized%%", comment: "") }
				}
				""",
				delimiters: .percentSigns
			).render([
				"className": names.className,
				"baseClass": names.baseClassName,
				"protocolName": names.protocolName,
				"localized": id.description,
			]),
			try SourceTemplate(
				"public protocol %%protocolName%%: %%protocolBase%% {}",
				delimiters: .percentSigns
			).render([
				"protocolName": names.protocolName,
				"protocolBase": try names.protocolBase(supertype: supertype, classes: classes),
			])
		]

		let properties = try swiftProperties(prefixes: prefixes, classes: classes)
		if !properties.isEmpty {
			lines.append(
				try SourceTemplate(
					"""
					public extension %%protocolName%% {
					%%properties%%
					}
					""",
					delimiters: .percentSigns
				).render([
					"protocolName": names.protocolName,
					"properties": properties.joined(separator: "\n"),
				])
			)
		}

		return lines
	}
}
