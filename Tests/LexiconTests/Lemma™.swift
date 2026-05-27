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
		#expect(Lemma.isValid(name: "a_2_")) // TODO: consider disallowing this!
		#expect(Lemma.isValid(name: "a_2_z"))

		#expect(!(Lemma.isValid(name: "")))
		#expect(!(Lemma.isValid(name: "1")))
		#expect(!(Lemma.isValid(name: "_"))) // TODO: consider allowing this!
		#expect(!(Lemma.isValid(name: "a__")))
	}
	
	@Test
	func test_Lemma_isValid_character() {
		
		#expect(Lemma.isValid(character: "_", appendingTo: "yet_another"))
		
		#expect(!(Lemma.isValid(character: "_", appendingTo: "not_another_")))
		#expect(!(Lemma.isValid(character: "_", appendingTo: ""))) // TODO: consider allowing this!
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

