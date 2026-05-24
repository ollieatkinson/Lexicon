//
// github.com/screensailor 2026
//

import Lexicon

extension Lexicon.Graph.Node.Class.JSON {

	func swiftTypeDeclarations(prefix: (class: String, protocol: String)) throws -> [String] {
		guard mixin == nil else {
			return []
		}

		let names = StandAloneTypeNames(id: id, prefix: prefix)

		if let protonym = protonym {
			return [
				try SourceTemplate(
					"public typealias %%className%% = %%baseClass%%",
					delimiters: .percentSigns
				).render([
					"className": names.className,
					"baseClass": names.className(for: protonym),
				])
			]
		}

		var lines = [
			try SourceTemplate(
				"""
				public final class %%className%%: %%baseClass%%, @unchecked Sendable, %%protocolName%% {
					public override class var localized: String { NSLocalizedString("%%localized%%", comment: "") }
				}
				""",
				delimiters: .percentSigns
			).render([
				"className": names.className,
				"baseClass": names.classPrefix,
				"protocolName": names.protocolName,
				"localized": id,
			]),
			try SourceTemplate(
				"public protocol %%protocolName%%: %%protocolBase%% {}",
				delimiters: .percentSigns
			).render([
				"protocolName": names.protocolName,
				"protocolBase": names.protocolBase(supertype: supertype),
			])
		]

		let properties = try swiftProperties(prefix: prefix)
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
