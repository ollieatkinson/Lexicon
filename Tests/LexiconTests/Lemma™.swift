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
		#expect(!(Lemma.isValid(character: "_", appendingTo: "")))
	}

	@Test
	func test_inherited_node_own_type() async throws {

		let root = try await Lexicon.from(
			TaskPaper(inherited_node_own_type).decode()
		).root

		let userId = try #require(await root["user", "id"])
		let collectionId = try #require(await root["db", "collection", "id"])

		let isCollectionId = await userId.is(collectionId)

		#expect(isCollectionId == true)
	}

	@Test
	func test_inherited_node_own_type_nested() async throws {

		let root = try await Lexicon.from(
			TaskPaper(inherited_node_own_type).decode()
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
	func equality_uses_stable_id() async throws {
		let left = try await Lexicon.from(TaskPaper(inherited_node_own_type).decode())
		let right = try await Lexicon.from(TaskPaper(inherited_node_own_type).decode())

		let leftLemma = try #require(await left["root.user.id"])
		let rightLemma = try #require(await right["root.user.id"])

		#expect(leftLemma == rightLemma)
		#expect(leftLemma !== rightLemma)
	}

	@Test
	func graph_path_is_cached_for_graph_nodes() async throws {
		let lexicon = try await Lexicon.from(TaskPaper(inherited_node_own_type).decode())
		try await expectGraphPathIsCached(in: lexicon)
	}

	@Test
	func protonym_validation_accepts_synonym_candidates() async throws {
		let lexicon = try await Lexicon.from(TaskPaper("""
		root:
			target:
			synonym:
			= target
			proposed:
		""").decode())

		let target = try #require(await lexicon["root.target"])
		let synonym = try #require(await lexicon["root.synonym"])
		let proposed = try #require(await lexicon["root.proposed"])

		#expect(await target.isValidProtonym(for: proposed))
		#expect(await proposed.isValid(protonym: target))
		#expect(await synonym.isValidProtonym(for: proposed))
		#expect(!(await synonym.isValidProtonym(for: target)))

		#if EDITOR
		let updated = try #require(await proposed.set(protonym: synonym))

		#expect(await updated.node.protonym == "synonym")
		#expect(await updated.source == target)
		#endif
	}

	@Test
	func synonym_type_passes_through_to_source() async throws {
		let lexicon = try await Lexicon.from(TaskPaper("""
		root:
			type:
			target:
			+ root.type
			synonym:
			= target
		""").decode())

		let target = try #require(await lexicon["root.target"])
		let synonym = try #require(await lexicon["root.synonym"])
		await expectSynonymTypePassesThroughToSource(synonym, target)
	}
}

@LexiconActor
private func expectGraphPathIsCached(in lexicon: Lexicon) throws {
	let graphNode = try #require(lexicon["root.user"])
	let inheritedNode = try #require(lexicon["root.user.id"])
	let path = try #require(graphNode.graphPath)

	#expect(lexicon.graph[path].name == "user")
	#expect(inheritedNode.graphPath == nil)
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
		+ root.two
			c:
			+ root.three
	one:
		two:
		+ root.a
			three:
			+ root.b
	db:
		collection:
			id:
	user:
	+ root.db.collection
	+ root.a
"""
