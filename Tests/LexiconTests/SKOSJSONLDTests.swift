//
// github.com/screensailor 2026
//

import Foundation

final class SKOSJSONLDTests: Hopes {

	func test_skos_json_ld_export_maps_lexicon_concepts() async throws {

		let lexicon = try await Lexicon.from(TaskPaper("""
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
			""").decodeDocument())
		let json = await lexicon.json()
		let output = try SKOSJSONLD.generate(json).string()

		hope(output) == """
			{
			  "@context" : {
			    "lexicon" : "https:\\/\\/github.com\\/ollieatkinson\\/Lexicon#",
			    "skos" : "http:\\/\\/www.w3.org\\/2004\\/02\\/skos\\/core#"
			  },
			  "@graph" : [
			    {
			      "@id" : "root",
			      "@type" : "skos:Concept",
			      "lexicon:alias" : [
			        {
			          "name" : "kitty",
			          "protonym" : "cat"
			        }
			      ],
			      "skos:altLabel" : [
			        "kitty"
			      ],
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
			"""
	}
}
