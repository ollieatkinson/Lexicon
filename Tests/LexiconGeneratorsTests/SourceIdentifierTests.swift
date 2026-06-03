//
// github.com/screensailor 2026
//

import Testing
import Foundation
@testable import LexiconGenerators

@Suite

struct SourceIdentifierTests {

	@Test
	func test_stand_alone_type_suffix_preserves_existing_identifier_rules() {
		#expect("test.one.more".standAloneTypeSuffix == "test_one_more")
		#expect("test.type_even.no_good".standAloneTypeSuffix == "test_type__even_no__good")
		#expect("test._&_.type".standAloneTypeSuffix == "test_____type")
	}

	@Test
	func test_stand_alone_type_names_share_prefix_rules() {
		let names = StandAloneTypeNames(id: "root.some_type", prefixes: .default)

		#expect(names.className == "L_root_some__type")
		#expect(names.protocolName == "I_root_some__type")
		#expect(names.className(for: "root.some_type.child") == "L_root_some__type_child")
		#expect(names.protocolBase(supertype: nil) == "I")
		#expect(names.protocolBase(supertype: "root.a_&_root.bad") == "I_root_a, I_root_bad")
	}

	@Test
	func test_stand_alone_type_names_keep_base_symbols_separate_from_generated_prefixes() {
		let prefixes = StandAloneTypePrefixes(class: "Node", protocol: "Kind")
		let names = StandAloneTypeNames(id: "root.some_type", prefixes: prefixes)

		#expect(names.baseClassName == "L")
		#expect(names.baseProtocolName == "I")
		#expect(names.className == "Node_root_some__type")
		#expect(names.protocolName == "Kind_root_some__type")
		#expect(names.className(for: "root.some_type.child") == "Node_root_some__type_child")
		#expect(names.protocolBase(supertype: nil) == "I")
		#expect(names.protocolBase(supertype: "root.a_&_root.bad") == "Kind_root_a, Kind_root_bad")
	}

	@Test
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

		#expect(accessors.map(\.name) == ["child", "alias"])
		#expect(accessors.map(\.sourceID) == ["root.child", "root.alias"])
		#expect(accessors.map(\.targetID) == ["root.child", "root.child"])
		#expect(accessors.map(\.pathSuffix) == ["child", "child"])
		#expect(accessors.map(\.isSynonym) == [false, true])
	}

	@Test
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
		let inheritedAccessors = instance.standAloneInheritedAccessors(classes: classes)
		let accessors = instance.standAloneAllAccessors(classes: classes)

		#expect(inheritedAccessors.map(\.name) == ["alias", "base", "shadowed"])
		#expect(inheritedAccessors.map(\.sourceID) == [
			"root.type.alias",
			"root.type.base",
			"root.type.shadowed",
		])
		#expect(inheritedAccessors.map(\.targetID) == [
			"root.type.base",
			"root.type.base",
			"root.type.shadowed",
		])
		#expect(accessors.map(\.name) == ["alias", "base", "own", "shadowed"])
		#expect(accessors.map(\.sourceID) == [
			"root.type.alias",
			"root.type.base",
			"root.instance.own",
			"root.instance.shadowed",
		])
		#expect(accessors.map(\.targetID) == [
			"root.type.base",
			"root.type.base",
			"root.instance.own",
			"root.instance.shadowed",
		])
	}

	@Test
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

		#expect(accessors.map(\.name) == ["second", "first", "firstAlias"])
		#expect(accessors.map(\.sourceID) == [
			"root.second.second",
			"root.first.first",
			"root.first.firstAlias",
		])
		#expect(accessors.map(\.targetID) == [
			"root.second.second",
			"root.first.first",
			"root.first.first",
		])
	}

	@Test
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

		#expect(accessors.map(\.name) == ["base", "mixinChild"])
		#expect(accessors.map(\.sourceID) == ["root.shared.base", "root.mixin.child"])
		#expect(accessors.map(\.targetID) == ["root.shared.base", "root.mixin.child"])
		#expect(accessors.map(\.pathSuffix) == ["base", "mixinChild"])
	}
}
