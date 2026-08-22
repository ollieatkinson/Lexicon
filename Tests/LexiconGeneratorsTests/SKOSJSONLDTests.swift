//
// github.com/screensailor 2026
//

import Testing
import Foundation

@Suite

struct SKOSJSONLDTests {

	@Test
	func test_skos_json_ld_export_maps_lexicon_concepts() async throws {

		let lexicon = try await TaskPaper("""
			root:
			> root note
				animal:
					name:
				cat:
				+ root.animal
				> cat note
				? {"ignored":true,"name":"Mog"}
					name:
				kitty:
				= cat
			""").lexicon()
		let json = await lexicon.json()
		let output = try SKOSJSONLD.generate(json).string()

		#expect(SKOSJSONLD.utType.preferredFilenameExtension == "jsonld")
		#expect(output == """
			{
			  "@context" : {
			    "lexicon" : "https:\\/\\/github.com\\/ollieatkinson\\/Lexicon#",
			    "skos" : "http:\\/\\/www.w3.org\\/2004\\/02\\/skos\\/core#"
			  },
			  "@graph" : [
			    {
			      "@id" : "root",
			      "@type" : "skos:Concept",
			      "skos:narrower" : [
			        {
			          "@id" : "root.animal"
			        },
			        {
			          "@id" : "root.cat"
			        }
			      ],
			      "skos:note" : [
			        "root note"
			      ],
			      "skos:prefLabel" : "root"
			    },
			    {
			      "@id" : "root.animal",
			      "@type" : "skos:Concept",
			      "skos:broader" : {
			        "@id" : "root"
			      },
			      "skos:narrower" : [
			        {
			          "@id" : "root.animal.name"
			        }
			      ],
			      "skos:prefLabel" : "animal"
			    },
			    {
			      "@id" : "root.animal.name",
			      "@type" : "skos:Concept",
			      "skos:broader" : {
			        "@id" : "root.animal"
			      },
			      "skos:prefLabel" : "name"
			    },
			    {
			      "@id" : "root.cat",
			      "@type" : "skos:Concept",
			      "lexicon:alias" : [
			        {
			          "name" : "kitty",
			          "protonym" : "root.cat"
			        }
			      ],
			      "lexicon:default" : {
			        "literal" : {
			          "object" : {
			            "name" : {
			              "string" : "Mog"
			            }
			          }
			        }
			      },
			      "lexicon:type" : [
			        {
			          "@id" : "root.animal"
			        }
			      ],
			      "skos:altLabel" : [
			        "kitty"
			      ],
			      "skos:broader" : {
			        "@id" : "root"
			      },
			      "skos:narrower" : [
			        {
			          "@id" : "root.cat.name"
			        }
			      ],
			      "skos:note" : [
			        "cat note"
			      ],
			      "skos:prefLabel" : "cat"
			    },
			    {
			      "@id" : "root.cat.name",
			      "@type" : "skos:Concept",
			      "skos:broader" : {
			        "@id" : "root.cat"
			      },
			      "skos:prefLabel" : "name"
			    }
			  ]
			}
			""")
	}

	@Test
	func test_skos_json_ld_maps_protonym_chains_to_the_canonical_concept() async throws {
		let json = try await TaskPaper("""
			root:
				target:
				alias1:
				= target
				alias2:
				= alias1
			""").lexicon().json()
		let alias2 = try json.classes.first { $0.id == "root.alias2" }.try()
		#expect(alias2.protonym == "root.alias1")

		let output = try SKOSJSONLD.generate(json).string()

		#expect(output.contains(#""name" : "alias1""#))
		#expect(output.contains(#""name" : "alias2""#))
		#expect(
			output.components(separatedBy: #""protonym" : "root.target""#).count - 1 == 2
		)
		#expect(!output.contains(#""@id" : "root.alias1""#))
		#expect(!output.contains(#""@id" : "root.alias2""#))
	}
}
