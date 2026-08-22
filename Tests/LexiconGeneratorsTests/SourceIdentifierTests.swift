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
	}

	@Test
	func test_stand_alone_type_names_share_prefix_rules() {
		let names = StandAloneTypeNames(id: "root.some_type", prefixes: .default)

		#expect(names.className == "L_root_some__type")
		#expect(names.protocolName == "I_root_some__type")
		#expect(names.className(for: "root.some_type.child") == "L_root_some__type_child")
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
	}

	@Test
	func test_synonym_member_paths_escape_every_component() {
		let path: Lemma.RelativeID = "class.default"

		#expect(path.swiftMemberPath == "`class`.`default`")
		#expect(path.kotlinMemberPath == "`class`.default")
	}

	@Test
	func test_protocol_bases_expand_typed_mixin_graphs() throws {
		let classes = try JSONDecoder().decode(
			[Lexicon.Graph.Node.Class.JSON].self,
			from: Data("""
			[
				{ "id": "root.first" },
				{ "id": "root.second" },
				{
					"id": "mixin_root_first_and_root_second",
					"supertype": "root.first",
					"mixin": { "type": "root.second" }
				},
				{
					"id": "root.instance",
					"supertype": "mixin_root_first_and_root_second"
				}
			]
			""".utf8)
		)
		let names = StandAloneTypeNames(
			id: "root.instance",
			prefixes: .init(class: "Node", protocol: "Kind")
		)

		#expect(try names.protocolBase(supertype: nil, classes: classes) == "I")
		#expect(
			try names.protocolBase(
				supertype: "mixin_root_first_and_root_second",
				classes: classes
			) == "Kind_root_first, Kind_root_second"
		)
	}

	@Test
	func test_stand_alone_symbol_preflight_rejects_invalid_prefixes_and_collisions() throws {
		let ordinary = try graphJSON(classIDs: ["root"])
		#expect(throws: StandAloneGenerationError.invalidTypePrefix(kind: "class", value: "bad-prefix")) {
			try ordinary.validateStandAloneSymbols(
				prefixes: .init(class: "bad-prefix", protocol: "Kind")
			)
		}

		do {
			try ordinary.validateStandAloneSymbols(prefixes: .init(class: "Symbol", protocol: "Symbol"))
			Issue.record("Expected a class/protocol symbol collision.")
		} catch let error as StandAloneGenerationError {
			#expect(error.description.contains("Generated symbol 'Symbol_root' collides"))
		}

		let pathCollision = try graphJSON(classIDs: ["root", "root.a_.b", "root.a._b"])
		do {
			try pathCollision.validateStandAloneSymbols(prefixes: .default)
			Issue.record("Expected encoded path symbols to collide.")
		} catch let error as StandAloneGenerationError {
			#expect(error.description.contains("Generated symbol 'L_root_a___b' collides"))
		}

		let rootCollision = try graphJSON(name: "L", classIDs: ["L"])
		#expect(throws: StandAloneGenerationError.symbolCollision(
			symbol: "L",
			first: "base class",
			second: "root binding 'L'"
		)) {
			try rootCollision.validateStandAloneSymbols(prefixes: .default)
		}
	}

	@Test
	func test_stand_alone_preflight_rejects_malformed_class_relationships() throws {
		let invalidAccessor = try graphJSON(
			classJSON: #"{"id":"root","synonyms":{"bad-name":"child"}}"#
		)
		#expect(throws: StandAloneGenerationError.invalidAccessorName(
			owner: "root",
			value: "bad-name"
		)) {
			try invalidAccessor.validateStandAloneSymbols(prefixes: .default)
		}

		let missingSupertype = try graphJSON(
			classJSON: #"{"id":"root","supertype":"root.missing"}"#
		)
		#expect(throws: StandAloneGenerationError.missingClass(
			id: "root.missing",
			referencedBy: "root"
		)) {
			try missingSupertype.validateStandAloneSymbols(prefixes: .default)
		}

		let inheritanceCycle = try graphJSON(
			classesJSON: """
			[
				{"id":"root","supertype":"root.other"},
				{"id":"root.other","supertype":"root"}
			]
			"""
		)
		#expect(throws: StandAloneGenerationError.inheritanceCycle("root")) {
			try inheritanceCycle.validateStandAloneSymbols(prefixes: .default)
		}

		let duplicate = try graphJSON(
			classesJSON: #"[{"id":"root"},{"id":"root"}]"#
		)
		#expect(throws: StandAloneGenerationError.duplicateClass("root")) {
			try duplicate.validateStandAloneSymbols(prefixes: .default)
		}
	}

	@Test
	func test_stand_alone_accessors_preserve_child_then_synonym_order() throws {
		let classes = try JSONDecoder().decode(
			[Lexicon.Graph.Node.Class.JSON].self,
			from: Data("""
			[
				{
					"id": "root",
					"children": ["child"],
					"synonyms": { "alias": "child" }
				},
				{ "id": "root.child" },
				{ "id": "root.alias", "protonym": "root.child" }
			]
			""".utf8)
		)
		let json = try classes.first.try()

		let accessors = try json.standAloneAccessors(classes: classes)

		#expect(accessors.map(\.name) == ["child", "alias"])
		#expect(accessors.map(\.sourceID) == ["root.child", "root.alias"])
		#expect(accessors.map(\.targetID) == ["root.child", "root.child"])
		#expect(accessors.map(\.pathSuffix) == ["child", "child"])
		#expect(accessors.map(\.isSynonym) == [false, true])
	}

	@Test
	func test_stand_alone_accessors_resolve_protonym_chains_to_canonical_targets() throws {
		let classes = try JSONDecoder().decode(
			[Lexicon.Graph.Node.Class.JSON].self,
			from: Data("""
			[
				{
					"id": "root",
					"children": ["target"],
					"synonyms": {
						"alias1": "target",
						"alias2": "alias1"
					}
				},
				{ "id": "root.target" },
				{ "id": "root.alias1", "protonym": "root.target" },
				{ "id": "root.alias2", "protonym": "root.alias1" }
			]
			""".utf8)
		)
		let root = try classes.first.try()

		let accessors = try root.standAloneAccessors(classes: classes)

		#expect(accessors.map(\.name) == ["target", "alias1", "alias2"])
		#expect(accessors.map(\.targetID) == [
			"root.target",
			"root.target",
			"root.target",
		])
		#expect(accessors.map(\.pathSuffix) == ["target", "target", "target"])
	}

	@Test
	func test_stand_alone_preflight_rejects_protonym_cycles() throws {
		let json = try graphJSON(
			classesJSON: """
			[
				{
					"id": "root",
					"synonyms": {
						"first": "second",
						"second": "first"
					}
				},
				{ "id": "root.first", "protonym": "root.second" },
				{ "id": "root.second", "protonym": "root.first" }
			]
			"""
		)

		#expect(throws: StandAloneGenerationError.protonymCycle("root.first")) {
			try json.validateStandAloneSymbols(prefixes: .default)
		}
	}

	@Test
	func test_inherited_accessors_and_protocols_resolve_protonym_supertypes() throws {
		let classes = try JSONDecoder().decode(
			[Lexicon.Graph.Node.Class.JSON].self,
			from: Data("""
			[
				{ "id": "root.type", "children": ["child"] },
				{ "id": "root.type.child" },
				{ "id": "root.alias", "protonym": "root.type" },
				{ "id": "root.instance", "supertype": "root.alias" }
			]
			""".utf8)
		)
		let instance = try classes.first { $0.id == "root.instance" }.try()
		let names = StandAloneTypeNames(id: instance.id, prefixes: .default)

		#expect(
			try instance.standAloneInheritedAccessors(classes: classes)
				.map(\.targetID) == ["root.type.child"]
		)
		#expect(
			try names.protocolBase(
				supertype: instance.supertype,
				classes: classes
			) == "I_root_type"
		)
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
		let inheritedAccessors = try instance.standAloneInheritedAccessors(classes: classes)
		let accessors = try instance.standAloneAllAccessors(classes: classes)

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
		let accessors = try instance.standAloneTypeAccessors(classes: classes)

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
		let accessors = try instance.standAloneInheritedAccessors(classes: classes)

		#expect(accessors.map(\.name) == ["base", "mixinChild"])
		#expect(accessors.map(\.sourceID) == ["root.shared.base", "root.mixin.child"])
		#expect(accessors.map(\.targetID) == ["root.shared.base", "root.mixin.child"])
		#expect(accessors.map(\.pathSuffix) == ["base", "mixinChild"])
	}

	private func graphJSON(
		name: String = "root",
		classIDs: [String]
	) throws -> Lexicon.Graph.JSON {
		let classes = classIDs
			.map { #"{"id":"\#($0)"}"# }
			.joined(separator: ",")
		return try JSONDecoder().decode(
			Lexicon.Graph.JSON.self,
			from: Data(#"{"date":0,"name":"\#(name)","classes":[\#(classes)]}"#.utf8)
		)
	}

	private func graphJSON(
		name: String = "root",
		classJSON: String
	) throws -> Lexicon.Graph.JSON {
		try graphJSON(name: name, classesJSON: "[\(classJSON)]")
	}

	private func graphJSON(
		name: String = "root",
		classesJSON: String
	) throws -> Lexicon.Graph.JSON {
		try JSONDecoder().decode(
			Lexicon.Graph.JSON.self,
			from: Data(
				#"{"date":0,"name":"\#(name)","classes":\#(classesJSON)}"#.utf8
			)
		)
	}
}
