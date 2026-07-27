//
// github.com/screensailor 2022
//

import Testing
@Suite
struct Lemma™ {

	@Test
	func test_Lemma_isValid_name() {

		#expect(Lemma.isValid(name: "a"))
		#expect(Lemma.isValid(name: "a_"))
		#expect(Lemma.isValid(name: "a_t"))
		#expect(Lemma.isValid(name: "a_2_"))
		#expect(Lemma.isValid(name: "a_2_z"))

		#expect(!(Lemma.isValid(name: "")))
		#expect(!(Lemma.isValid(name: "1")))
		#expect(!(Lemma.isValid(name: "_")))
		#expect(!(Lemma.isValid(name: "a__")))
	}

	@Test
	func test_Lemma_isValid_character() {

		#expect(Lemma.isValid(character: "_", appendingTo: "yet_another"))

		#expect(!(Lemma.isValid(character: "_", appendingTo: "not_another_")))
		#expect(Lemma.isValid(character: "_", appendingTo: ""))
	}

	@Test
	func test_inherited_node_own_type() async throws {

		let document = try TaskPaper(inherited_node_own_type).decodeDocument()
		let root = try await Lexicon(
			document: document,
			selectedRoot: "root"
		).root

		let userId = try #require(await root["user", "id"])
		let collectionId = try #require(await root["db", "collection", "id"])

		let isCollectionId = await userId.is(collectionId)

		#expect(isCollectionId == true)
	}

	@Test
	func test_inherited_node_own_type_nested() async throws {

		let document = try TaskPaper(inherited_node_own_type).decodeDocument()
		let root = try await Lexicon(
			document: document,
			selectedRoot: "root"
		).root

		do {
			let a = try #require(await root["user", "b", "c"])
			let b = try #require(await root["a", "b", "c"])
			let matches = await a.is(b)
			#expect(matches == true)
		}

		do {
			let a = try #require(await root["a", "two", "two", "two", "three"])
			let b = try #require(await root["one", "two", "three"])
			let matches = await a.is(b)
			#expect(matches == true)
		}
	}

	@Test
	func equality_includes_lexicon_identity_and_revision() async throws {
		let document = try TaskPaper(inherited_node_own_type).decodeDocument()
		let left = try await Lexicon(document: document, selectedRoot: "root")
		let right = try await Lexicon(document: document, selectedRoot: "root")

		let leftLemma = try #require(await left["root.user.id"])
		let rightLemma = try #require(await right["root.user.id"])
		let sameGenerationLemma = try #require(await left["root.user.id"])

		#expect(leftLemma.id == rightLemma.id)
		#expect(leftLemma != rightLemma)
		#expect(leftLemma == sameGenerationLemma)
	}

	@Test
	func graph_nodes_are_distinguished_from_inherited_nodes() async throws {
		let document = try TaskPaper(inherited_node_own_type).decodeDocument()
		let lexicon = try await Lexicon(document: document, selectedRoot: "root")
		try await expectGraphNodeIdentity(in: lexicon)
	}

	@Test
	func protonym_chains_resolve_to_their_canonical_source() async throws {
		let document = try TaskPaper("""
		root:
			target:
			synonym:
			= target
			proposed:
		""").decodeDocument()
		let lexicon = try await Lexicon(document: document, selectedRoot: "root")

		let target = try #require(await lexicon["root.target"])
		let synonym = try #require(await lexicon["root.synonym"])
		let proposed = try #require(await lexicon["root.proposed"])

		#expect(await synonym.protonym == target)
		#expect(await synonym.source == target)
		#expect(await proposed.protonym == nil)

		#if EDITOR
		let updated = try await lexicon.setProtonym(synonym, of: proposed)
		let currentTarget = try #require(await lexicon["root.target"])

		#expect(await updated.node.protonym == "synonym")
		#expect(await updated.source == currentTarget)
		#endif
	}

	@Test
	func synonym_type_passes_through_to_source() async throws {
		let document = try TaskPaper("""
		root:
			type:
			target:
			+ root.type
			synonym:
			= target
		""").decodeDocument()
		let lexicon = try await Lexicon(document: document, selectedRoot: "root")

		let target = try #require(await lexicon["root.target"])
		let synonym = try #require(await lexicon["root.synonym"])
		await expectSynonymTypePassesThroughToSource(synonym, target)
	}
}

@LexiconActor
private func expectGraphNodeIdentity(in lexicon: Lexicon) throws {
	let graphNode = try #require(lexicon["root.user"])
	let inheritedNode = try #require(lexicon["root.user.id"])

	#expect(graphNode.isGraphNode)
	#expect(graphNode.graphNode != nil)
	#expect(!inheritedNode.isGraphNode)
	#expect(inheritedNode.graphNode == nil)
	#expect(inheritedNode.source.id == "root.db.collection.id")
}

@LexiconActor
private func expectSynonymTypePassesThroughToSource(_ synonym: Lemma, _ target: Lemma) {
	#expect(target.type.keys == ["root.target", "root.type"])
	#expect(synonym.type.keys == target.type.keys)
}

private let inherited_node_own_type = """
root:
	a:
	+ root.one
		b:
		+ root.one.two
			c:
			+ root.one.two.three
	one:
		two:
		+ root.a
			three:
			+ root.a.b
	db:
		collection:
			id:
	user:
	+ root.db.collection
	+ root.a
"""
