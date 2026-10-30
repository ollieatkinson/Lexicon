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
			// An inherited getter may return its source declaration's nominal
			// class, while this alias names a projected class. Preserve the
			// resolved identifier through the alias's declared generated type.
			let template = accessor.isSynonym
				? "\tvar `%%name%%`: %%className%% { .init(%%protonym%%(\\.id)) }"
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
