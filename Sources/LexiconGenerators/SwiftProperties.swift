//
// github.com/screensailor 2026
//

import Lexicon

extension Lexicon.Graph.Node.Class.JSON {

	func swiftProperties(prefix: (class: String, protocol: String)) throws -> [String] {
		let names = StandAloneTypeNames(id: id, prefix: prefix)
		var properties: [String] = []

		for accessor in standAloneAccessors() {
			let template = accessor.isSynonym
				? "\tvar `%%name%%`: %%className%% { %%protonym%% }"
				: "\tvar `%%name%%`: %%className%% { .init(\"\\(__).%%name%%\") }"
			properties.append(
				try SourceTemplate(
					template,
					delimiters: .percentSigns
				).render([
					"name": accessor.name,
					"className": names.className(for: accessor.sourceID),
					"protonym": accessor.pathSuffix,
				])
			)
		}

		return properties
	}
}
