//
// github.com/screensailor 2026
//

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum SKOSJSONLD: CodeGenerator {

	public static let utType: UTType = .json
	public static let command = "json-ld"

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		let encoder = JSONClasses.Encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(Document(json))
	}
}

private extension SKOSJSONLD {

	struct Document: Codable {
		var context: Context = .init()
		var graph: [Concept]

		init(_ json: Lexicon.Graph.JSON) {
			let concepts = json.classes.filter { $0.mixin == nil && $0.protonym == nil }
			let narrowerIDs = Dictionary(uniqueKeysWithValues: concepts.map { concept in
				(concept.id, (concept.children ?? []).map { "\(concept.id).\($0)" })
			})
			self.graph = concepts
				.map { Concept($0, narrower: narrowerIDs[$0.id] ?? []) }
				.sorted { $0.id < $1.id }
		}

		private enum CodingKeys: String, CodingKey {
			case context = "@context"
			case graph = "@graph"
		}
	}

	struct Context: Codable {
		var lexicon = "https://github.com/ollieatkinson/Lexicon#"
		var skos = "http://www.w3.org/2004/02/skos/core#"
	}

	struct Concept: Codable {
		var id: String
		var type = "skos:Concept"
		var prefLabel: String
		var broader: Reference?
		var narrower: [Reference]?
		var altLabel: [String]?
		var alias: [Alias]?
		var lexiconType: [Reference]?
		var note: [String]?
		var defaultValue: Lexicon.Graph.Node.DefaultValue.JSON?

		init(_ concept: Lexicon.Graph.Node.Class.JSON, narrower: [String]) {
			self.id = concept.id
			self.prefLabel = concept.id
				.split(separator: ".")
				.last
				.map(String.init)?
				.replacingOccurrences(of: "_", with: " ") ?? concept.id
			self.broader = concept.id.parentID.map(Reference.init)
			self.narrower = narrower
				.sorted()
				.map(Reference.init)
				.unlessEmpty
			self.altLabel = concept.synonyms?
				.keys
				.sorted()
				.unlessEmpty
			self.alias = concept.synonyms?
				.sorted { $0.key < $1.key }
				.map { Alias(name: $0.key, protonym: $0.value) }
				.unlessEmpty
			self.lexiconType = concept.type?
				.sorted()
				.map(Reference.init)
				.unlessEmpty
			self.note = concept.notes
			self.defaultValue = concept.defaultValue
		}

		private enum CodingKeys: String, CodingKey {
			case id = "@id"
			case type = "@type"
			case prefLabel = "skos:prefLabel"
			case broader = "skos:broader"
			case narrower = "skos:narrower"
			case altLabel = "skos:altLabel"
			case alias = "lexicon:alias"
			case lexiconType = "lexicon:type"
			case note = "skos:note"
			case defaultValue = "lexicon:default"
		}
	}

	struct Reference: Codable {
		var id: String

		init(_ id: String) {
			self.id = id
		}

		private enum CodingKeys: String, CodingKey {
			case id = "@id"
		}
	}

	struct Alias: Codable {
		var name: String
		var protonym: String
	}
}

private extension String {

	var parentID: String? {
		guard let index = lastIndex(of: ".") else {
			return nil
		}
		return String(prefix(upTo: index))
	}
}
