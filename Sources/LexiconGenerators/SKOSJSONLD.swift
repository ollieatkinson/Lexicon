//
// github.com/screensailor 2026
//

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import Lexicon

public enum SKOSJSONLD: CodeGenerator {

	public static let utType = UTType(filenameExtension: "jsonld", conformingTo: .json) ?? .json
	public static let command = "json-ld"

	public static func generate(_ json: Lexicon.Graph.JSON) throws -> Data {
		let encoder = JSONClasses.Encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(try Document(json))
	}
}

private extension SKOSJSONLD {

	struct Document: Codable {
		var context: Context = .init()
		var graph: [Concept]

		init(_ json: Lexicon.Graph.JSON) throws {
			let concepts = json.classes.filter { $0.mixin == nil && $0.protonym == nil }
			var aliases: [Lemma.ID: [Alias]] = [:]
			for concept in concepts {
				for (name, protonym) in concept.synonyms ?? [:] {
					let aliasName = try Lemma.Name(validating: name)
					let immediateID = concept.id.appending(protonym)
					let canonicalID = try json.classes.standAloneCanonicalID(
						for: immediateID,
						referencedBy: concept.id.appending(aliasName)
					)
					aliases[canonicalID, default: []].append(
						Alias(name: aliasName.rawValue, protonym: canonicalID.description)
					)
				}
			}
			let narrowerIDs = Dictionary(uniqueKeysWithValues: concepts.map { concept in
				(concept.id, (concept.children ?? []).map { concept.id.appending($0) })
			})
			self.graph = concepts
				.map { Concept($0, narrower: narrowerIDs[$0.id] ?? [], aliases: aliases[$0.id] ?? []) }
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

		init(_ concept: Lexicon.Graph.Node.Class.JSON, narrower: [Lemma.ID], aliases: [Alias]) {
			self.id = concept.id.description
			self.prefLabel = concept.id.name.rawValue
				.replacingOccurrences(of: "_", with: " ")
			self.broader = concept.id.parent.map(Reference.init)
			self.narrower = narrower
				.sorted()
				.map(Reference.init)
				.unlessEmpty
			self.altLabel = aliases
				.map(\.name)
				.sorted()
				.unlessEmpty
			self.alias = aliases
				.sorted { $0.name < $1.name }
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

		init(_ id: Lemma.ID) {
			self.id = id.description
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
