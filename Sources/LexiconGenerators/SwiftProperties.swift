//
// github.com/screensailor 2026
//

import Lexicon

extension Lexicon.Graph.Node.Class.JSON {

	func swiftProperties(
		prefixes: StandAloneTypePrefixes,
		classes: [Lexicon.Graph.Node.Class.JSON]
	) throws -> [String] {
		let names = StandAloneTypeNames(id: id, prefixes: prefixes)
		var properties: [String] = []

		for accessor in try standAloneAccessors(classes: classes) {
			let template = accessor.isSynonym
				? "\tvar `%%name%%`: %%className%% { %%protonym%% }"
				: "\tvar `%%name%%`: %%className%% { .init(\"\\(__).%%name%%\") }"
			properties.append(
				try SourceTemplate(
					template,
					delimiters: .percentSigns
				).render([
					"name": accessor.name.rawValue,
					"className": names.className(for: accessor.sourceID),
					"protonym": accessor.pathSuffix.swiftMemberPath,
				])
			)
		}

		return properties
	}
}
