//
// github.com/screensailor 2022
//

import Testing
@Suite
struct Lemma_Find™ {
	
	let sentences = """
		one two three
		a b c d
		"""
	
	@Test
	func test_() async throws {
		let lemma = try await sentenceRoot(sentences)
		let o = await lemma.find("").map(\.id)
		#expect(o == [])
	}
	
	@Test
	func test_c() async throws {
		let lemma = try await sentenceRoot(sentences)
		let o = await lemma.find("c").map(\.id)
		#expect(o == ["a.sentence.a.b.c"])
	}
	
	@Test
	func test_C() async throws {
		let lemma = try await sentenceRoot(sentences)
		let o = await lemma.find("c").map(\.id)
		#expect(o == ["a.sentence.a.b.c"])
	}
	
	@Test
	func test_n() async throws {
		let lemma = try await sentenceRoot(sentences)
		let o = await lemma.find("n").map(\.id).sorted()
		#expect(o == [
			"a.word.noun",
			"a.word.number",
		])
	}
	
	@Test
	func test_w_n() async throws {
		let lemma = try await sentenceRoot(sentences)
		let o = await lemma.find("w", "n").map(\.id).sorted()
		#expect(o == [
			"a.word.noun",
			"a.word.number",
		])
	}
	
	@Test
	func test_w__n() async throws {
		let lemma = try await sentenceRoot(sentences)
		let o = await lemma.find("w", "", "n").map(\.id).sorted()
		#expect(o == [
			"a.word.noun",
			"a.word.number",
		])
	}
	
	@Test
	func test_a_b() async throws {
		let lemma = try await sentenceRoot(sentences)
		let o = await lemma.find("a", "b").map(\.id)
		#expect(o == [
			"a.sentence.a.b",
		])
	}
	
	@Test
	func test_b_d() async throws {
		
		let sentences = """
		one two three
		a b c d
		b c d
		"""
		
		let lemma = try await sentenceRoot(sentences)
		let o = await lemma.find("b", "d").map(\.id).sorted()
		#expect(o == [
			"a.sentence.a.b.c.d",
			"a.sentence.b.c.d",
		])
	}
	
	@Test
	func test_a_d() async throws {
		
		let sentences = """
		one two three
		a b c d
		b c d a b c d
		"""
		let lemma = try await sentenceRoot(sentences)
		do {
			let o = await lemma.find("a", "d").map(\.id).sorted()
			#expect(o == [
				"a.sentence.a.b.c.d",
				"a.sentence.b.c.d.a.b.c.d",
			])
		}
		do {
			let o = await lemma.find("b", "d").map(\.id).sorted()
			#expect(o == [
				"a.sentence.a.b.c.d",
				"a.sentence.b.c.d",
				"a.sentence.b.c.d.a.b.c.d",
			])
		}
	}
}

@LexiconActor
private func sentenceRoot(_ sentences: String) throws -> Lemma {
	try Lexicon(graph: .from(sentences: sentences)).root
}
