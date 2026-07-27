//
// github.com/screensailor 2026
//

import Testing
import Foundation

@Suite

struct DocumentMetadataTests {

	@Test
	func test_taskpaper_document_metadata_round_trip() throws {

		let document = try TaskPaper("""
			# document comment
			> document note
			@ local.lexicon
			@ https://example.com/remote.lexicon
			root:
			# root comment
			> root note
			? {"count":2,"enabled":true}
				connected:
				@ local.lexicon
				@ https://example.com/remote.lexicon
				alias:
				= root.value
				value:
				? "fallback"
				+ root.type
			""").decodeDocument()

		#expect(document.comments == ["document comment"])
		#expect(document.notes == ["document note"])
		#expect(document.imports.map(\.reference) == [
			"local.lexicon",
			"https://example.com/remote.lexicon",
		])
		#expect(document.imports.map(\.location) == [.local, .remote])
		#expect(Array(document.roots.keys) == ["root"])

		let root = try document.roots["root"].try()
		#expect(root.comments == ["root comment"])
		#expect(root.notes == ["root note"])
		#expect(root.defaultValue == .literal(.object([
			"count": .number(2),
			"enabled": .bool(true),
		])))

		let connected = try root.children["connected"].try()
		#expect(connected.connections.map(\.reference) == [
			"local.lexicon",
			"https://example.com/remote.lexicon",
		])

		let alias = try root.children["alias"].try()
		#expect(alias.protonym == "root.value")

		let value = try root.children["value"].try()
		#expect(value.defaultValue == .literal(.string("fallback")))
		#expect(value.type == ["root.type"])

		let encoded = TaskPaper.encode(document)
		let roundTrip = try TaskPaper(encoded).decodeDocument()

		#expect(TaskPaper.encode(roundTrip) == encoded)
		#expect(try roundTrip.roots["root"].try().comments == ["root comment"])
		#expect(try roundTrip.roots["root"].try().children["value"].try().defaultValue == .literal(.string("fallback")))
	}

	@Test
	func test_taskpaper_document_preserves_multiple_roots() throws {

		let document = try TaskPaper("""
			zeta:
				last:
			alpha:
				first:
			""").decodeDocument()

		#expect(Array(document.roots.keys) == ["alpha", "zeta"])
		#expect(try Array(document.roots["alpha"].try().children.keys) == ["first"])
		#expect(try Array(document.roots["zeta"].try().children.keys) == ["last"])

		let graph = try TaskPaper("""
			zeta:
			alpha:
			""").decodeGraph(root: "alpha")
		#expect(graph.rootName == "alpha")

		#expect(TaskPaper.encode(document) == """
			alpha:
				first:
			zeta:
				last:
			""")
	}

	@Test
	func test_document_backing_collections_keep_keys_sorted() throws {

		var root = Lexicon.Graph.Node()
		root.children["zeta"] = .init()
		root.children["alpha"] = .init()
		root.children["middle"] = .init()
		root.children["alpha"] = .init()

		var document = Lexicon.Document()
		document.roots["zeta"] = .init()
		document.roots["alpha"] = root
		document.roots["middle"] = .init()
		document.roots["alpha"] = root

		#expect(Array(root.children.keys) == ["alpha", "middle", "zeta"])
		#expect(Array(document.roots.keys) == ["alpha", "middle", "zeta"])
	}

	@Test
	func test_lexicon_document_loads_multiple_roots() async throws {

		let document = try TaskPaper("""
			shared:
				kind:
			app:
				item:
				+ shared.kind
			zeta:
				child:
			""").decodeDocument()

		let lexicon = try await Lexicon(document: document, selectedRoot: "app")
		let rootNames = await Array(lexicon.roots.keys)
		let selectedRootName = await lexicon.root.name
		let sharedKind = try #require(await lexicon["shared.kind"])
		let item = try #require(await lexicon["app.item"])
		let zetaChild = try #require(await lexicon["zeta.child"])
		let itemIsSharedKind = await item.is(sharedKind)
		let json = await lexicon.json()

		#expect(rootNames == ["app", "shared", "zeta"])
		#expect(selectedRootName == "app")
		#expect(itemIsSharedKind == true)
		#expect(zetaChild.id == "zeta.child")
		#expect(json.name == "app")
		#expect(json.classes.map(\.id) == [
			"app",
			"app.item",
			"shared",
			"shared.kind",
		])
	}

	#if EDITOR
	@Test
	func test_multi_root_graph_reset_preserves_sibling_roots() async throws {

		let document = try TaskPaper("""
			shared:
				kind:
			app:
				item:
			""").decodeDocument()
		var graph = try document.graph(root: "app")
		graph.root.children["new"] = .init()

		let lexicon = try await Lexicon(document: document, selectedRoot: "app")
		var replacement = document
		replacement.roots["app"] = graph.root
		try await lexicon.replaceDocument(with: replacement, selectedRoot: "app")

		let rootNames = await Array(lexicon.document.roots.keys)
		let sharedKind = try #require(await lexicon["shared.kind"])
		let new = try #require(await lexicon["app.new"])

		#expect(rootNames == ["app", "shared"])
		#expect(sharedKind.id == "shared.kind")
		#expect(new.id == "app.new")
	}
	#endif

	@Test
	func test_lemma_default_values_resolve_through_types_and_synonyms() async throws {

		let document = try TaskPaper("""
			root:
				kind:
				? "kind default"
					shared:
					? "kind shared"
					unique:
					? "kind unique"
				other:
					shared:
					? "other shared"
				instance:
				+ root.kind
					shared:
					? "own shared"
				own:
				+ root.kind
				? "own default"
				alias:
				= instance
				multi:
				+ root.other
				+ root.kind
			""").decodeDocument()
		let root = try await Lexicon(
			document: document,
			selectedRoot: "root"
		).root

		let instance = try #require(await root["instance"])
		let inheritedUnique = try #require(await instance["unique"])
		let ownShared = try #require(await instance["shared"])
		let own = try #require(await root["own"])
		let alias = try await root.ownChildren["alias"].try()
		let multiShared = try #require(await root["multi", "shared"])

		let instanceDefault = await instance.defaultValue
		let inheritedUniqueDefault = await inheritedUnique.defaultValue
		let ownSharedDefault = await ownShared.defaultValue
		let ownDefault = await own.defaultValue
		let aliasDefault = await alias.defaultValue
		let multiSharedDefault = await multiShared.defaultValue

		#expect(instanceDefault == .literal(.string("kind default")))
		#expect(inheritedUniqueDefault == .literal(.string("kind unique")))
		#expect(ownSharedDefault == .literal(.string("own shared")))
		#expect(ownDefault == .literal(.string("own default")))
		#expect(aliasDefault == .literal(.string("kind default")))
		#expect(multiSharedDefault == .literal(.string("kind shared")))
	}

	@Test
	func test_json_classes_include_default_values_and_notes() async throws {

		let document = try TaskPaper("""
			root:
			> root note
			? @ root.kind
				kind:
				? "kind default"
			""").decodeDocument()
		let json = try await Lexicon(
			document: document,
			selectedRoot: "root"
		).json()

		let root = try json.classes.first { $0.id == "root" }.try()
		let kind = try json.classes.first { $0.id == "root.kind" }.try()

		#expect(root.defaultValue == DefaultValueJSON(.reference("root.kind")))
		#expect(root.notes == ["root note"])
		#expect(kind.defaultValue == DefaultValueJSON(.literal(.string("kind default"))))
	}

	@Test
	func test_json_default_values_only_include_matching_fields() async throws {

		let document = try TaskPaper("""
			root:
			? {"direct":"kept","kind":{"inherited":"kept","unknown":"drop"},"unknown":"drop"}
				direct:
				kind:
					inherited:
				instance:
				+ root.kind
				? {"inherited":"kept","unknown":"drop"}
			""").decodeDocument()
		let json = try await Lexicon(
			document: document,
			selectedRoot: "root"
		).json()

		let root = try json.classes.first { $0.id == "root" }.try()
		let instance = try json.classes.first { $0.id == "root.instance" }.try()

		#expect(root.defaultValue == DefaultValueJSON(.literal(.object([
			"direct": .string("kept"),
			"kind": .object([
				"inherited": .string("kept"),
			]),
		]))))
		#expect(instance.defaultValue == DefaultValueJSON(.literal(.object([
			"inherited": .string("kept"),
		]))))
	}

	@Test
	func test_document_json_preserves_node_metadata() throws {

		let document = Lexicon.Document(
			date: Date(timeIntervalSinceReferenceDate: 0),
			roots: [
				"root": .init(
					children: [
						"value": .init(
							type: ["root.type"],
							defaultValue: .literal(.object([
								"count": .number(2),
								"enabled": .bool(true),
							])),
							connections: [.init("https://example.com/remote.lexicon")],
							notes: ["node note"],
							comments: ["node comment"]
						),
					],
					notes: ["root note"]
				),
			],
			imports: [.init("local.lexicon")],
			notes: ["document note"],
			comments: ["document comment"]
		)

		let data = try JSONEncoder().encode(document.json)
		let decoded = try Lexicon.Document(JSONDecoder().decode(Lexicon.Document.JSON.self, from: data))
		let value = try decoded.roots["root"].try().children["value"].try()

		#expect(decoded.imports == [.init("local.lexicon")])
		#expect(decoded.notes == ["document note"])
		#expect(try decoded.roots["root"].try().notes == ["root note"])
		#expect(value.defaultValue == .literal(.object([
			"count": .number(2),
			"enabled": .bool(true),
		])))
		#expect(value.connections == [.init("https://example.com/remote.lexicon")])
		#expect(value.notes == ["node note"])
		#expect(value.comments == ["node comment"])
	}
}

private typealias DefaultValueJSON = Lexicon.Graph.Node.DefaultValue.JSON
