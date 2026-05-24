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

	func test_stand_alone_all_accessors_include_inherited_accessors() throws {
		let classes = try JSONDecoder().decode(
			[Lexicon.Graph.Node.Class.JSON].self,
			from: Data("""
			[
				{
					"id": "root.type",
					"children": ["base", "shadowed"],
					"synonyms": { "alias": "base" }
				},
				{
					"id": "root.instance",
					"supertype": "root.type",
					"children": ["shadowed", "own"]
				}
			]
			""".utf8)
		)

		let instance = try classes.first { $0.id == "root.instance" }.try()
		let accessors = instance.standAloneAllAccessors(classes: classes)

		hope(accessors.map(\.name)) == ["alias", "base", "own", "shadowed"]
		hope(accessors.map(\.sourceID)) == [
			"root.type.alias",
			"root.type.base",
			"root.instance.own",
			"root.instance.shadowed",
		]
		hope(accessors.map(\.targetID)) == [
			"root.type.base",
			"root.type.base",
			"root.instance.own",
			"root.instance.shadowed",
		]
	}

	func test_stand_alone_type_accessors_follow_declared_type_order() throws {
		let classes = try JSONDecoder().decode(
			[Lexicon.Graph.Node.Class.JSON].self,
			from: Data("""
			[
				{
					"id": "root.first",
					"children": ["first"],
					"synonyms": { "firstAlias": "first" }
				},
				{
					"id": "root.second",
					"children": ["second"]
				},
				{
					"id": "root.instance",
					"type": ["root.second", "root.first"]
				}
			]
			""".utf8)
		)

		let instance = try classes.first { $0.id == "root.instance" }.try()
		let accessors = instance.standAloneTypeAccessors(classes: classes)

		hope(accessors.map(\.name)) == ["second", "first", "firstAlias"]
		hope(accessors.map(\.sourceID)) == [
			"root.second.second",
			"root.first.first",
			"root.first.firstAlias",
		]
		hope(accessors.map(\.targetID)) == [
			"root.second.second",
			"root.first.first",
			"root.first.first",
		]
	}

	func test_stand_alone_inherited_accessors_include_mixin_children() throws {
		let classes = try JSONDecoder().decode(
			[Lexicon.Graph.Node.Class.JSON].self,
			from: Data("""
			[
				{
					"id": "root.shared",
					"children": ["base"]
				},
				{
					"id": "root.mixin",
					"supertype": "root.shared",
					"mixin": {
						"type": "root.shared",
						"children": {
							"mixinChild": "root.mixin.child"
						}
					}
				},
				{
					"id": "root.instance",
					"supertype": "root.mixin"
				}
			]
			""".utf8)
		)

		let instance = try classes.first { $0.id == "root.instance" }.try()
		let accessors = instance.standAloneInheritedAccessors(classes: classes)

		hope(accessors.map(\.name)) == ["base", "mixinChild"]
		hope(accessors.map(\.sourceID)) == ["root.shared.base", "root.mixin.child"]
		hope(accessors.map(\.targetID)) == ["root.shared.base", "root.mixin.child"]
		hope(accessors.map(\.pathSuffix)) == ["base", "mixinChild"]
	}
}
