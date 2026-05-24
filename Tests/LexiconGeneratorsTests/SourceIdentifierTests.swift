//
// github.com/screensailor 2026
//

import Foundation
@_exported import Hope
@testable import LexiconGenerators

final class SourceIdentifierTests: Hopes {

	func test_stand_alone_type_suffix_preserves_existing_identifier_rules() {
		hope("test.one.more".standAloneTypeSuffix) == "test_one_more"
		hope("test.type_even.no_good".standAloneTypeSuffix) == "test_type__even_no__good"
		hope("test._&_.type".standAloneTypeSuffix) == "test_____type"
	}

	func test_stand_alone_type_names_share_prefix_rules() {
		let names = StandAloneTypeNames(id: "root.some_type", prefix: ("L", "I"))

		hope(names.className) == "L_root_some__type"
		hope(names.protocolName) == "I_root_some__type"
		hope(names.className(for: "root.some_type.child")) == "L_root_some__type_child"
		hope(names.protocolBase(supertype: nil)) == "I"
		hope(names.protocolBase(supertype: "root.a_&_root.bad")) == "I_root_a, I_root_bad"
	}

	func test_stand_alone_accessors_preserve_child_then_synonym_order() throws {
		let json = try JSONDecoder().decode(
			Lexicon.Graph.Node.Class.JSON.self,
			from: Data("""
			{
				"id": "root",
				"children": ["child"],
				"synonyms": { "alias": "child" }
			}
			""".utf8)
		)

		let accessors = json.standAloneAccessors()

		hope(accessors.map(\.name)) == ["child", "alias"]
		hope(accessors.map(\.sourceID)) == ["root.child", "root.alias"]
		hope(accessors.map(\.targetID)) == ["root.child", "root.child"]
		hope(accessors.map(\.pathSuffix)) == ["child", "child"]
		hope(accessors.map(\.isSynonym)) == [false, true]
	}
}
