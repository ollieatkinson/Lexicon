//
// github.com/screensailor 2022
//

import Testing
import Lexicon

#if EDITOR

extension Lexicon™ {
	
	// MARK: additive mutations
	
	@Test
	func test_make_child_graph() async throws {
				
		let taskpaper = """
			o:
				copy:
					a:
					+ o
						b:
							c:
								d:
								+ o.paste.a
									e:
									+ o
							d:
							= c.d
							e:
							= c.d.e.copy
						c:
						= copy
				paste:
					a:
			"""
			
		let src = try await taskpaper.lemma("o.copy.a.b")
		let dst = try #require(await src.lexicon["o.paste.a"])

		let b = try #require(await dst.make(child: src.graph))
		
		#expect(await b.lexicon.taskpaper() == """
			o:
				copy:
					a:
					+ o
						b:
							c:
								d:
								+ o.paste.a
									e:
									+ o
							d:
							= c.d
							e:
							= c.d.e.copy
						c:
						= copy
				paste:
					a:
						b:
							c:
								d:
								+ o.paste.a
									e:
									+ o
							d:
							= c.d
							e:
							= c.d.e.copy
			""")
	}
	
	@Test
	func test_make_child_graph_where_root_is_a_synonym() async throws {
				
		let taskpaper = """
			o:
				a:
					b:
						c:
							d:
						x:
						= c
			"""
			
		let src = try await taskpaper.lemma("o.a.b.x")
		let dst = try #require(await src.lexicon["o.a"])

		let b = try #require(await dst.make(child: src.graph))

		let actual = await b.lexicon.taskpaper()
		#expect(actual == """
			o:
				a:
					b:
						c:
							d:
						x:
						= c
					x:
			""", "actual:\n\(actual)")
	}

	@Test
	func test_make_child_graph_preserves_valid_root_synonym() async throws {

		let taskpaper = """
			o:
				source:
					target:
					alias:
					= target
				destination:
					target:
			"""

		let src = try await taskpaper.lemma("o.source.alias")
		let dst = try #require(await src.lexicon["o.destination"])

		let alias = try #require(await dst.make(child: src.graph))

		let actual = await alias.lexicon.taskpaper()
		#expect(actual == """
			o:
				destination:
					alias:
					= target
					target:
				source:
					alias:
					= target
					target:
			""", "actual:\n\(actual)")
	}
	
	// MARK: non-additive mutations
	
	@Test
	func test_delete() async throws {
		
		let taskpaper = """
			o:
				a:
				+ o
				+ o.b
				b:
					x:
				c:
				= a.x
				d:
				= a
			"""
			
		let b = try await taskpaper.lemma("o.b")
		
		let o = try #require(await b.delete())
		
		let actual = await o.lexicon.taskpaper()
		#expect(actual == """
			o:
				a:
				+ o
				d:
				= a
			""", "actual:\n\(actual)")
	}
	
	@Test
	func test_remove_type() async throws {
		
		let taskpaper = """
			o:
				a:
				+ o
				b:
					x:
				c:
				= a.b.x
				d:
				= a
			"""
			
		let a = try await taskpaper.lemma("o.a")
		let o = try #require(await a.lexicon["o"])

		let a₂ = try #require(await a.remove(type: o))
		
		#expect(await a₂.lexicon.taskpaper() == """
			o:
				a:
				b:
					x:
				d:
				= a
			""")
	}
	
	@Test
	func test_remove_protonym() async throws {
		
		let taskpaper = """
			o:
				a:
				+ o
				b:
					x:
				c:
				= a.b.x
				d:
				= a
			"""
			
		let c = try await taskpaper.lemma("o.c")

		let c₂ = try #require(await c.removeProtonym())
		
		#expect(await c₂.lexicon.taskpaper() == """
			o:
				a:
				+ o
				b:
					x:
				c:
				d:
				= a
			""")
	}
		
	@Test
	func test_rename() async throws {
		
		let taskpaper = """
			o:
				a:
				+ o.ax
				+ o.x.y.z
					b:
					+ o.ax.xa
					+ o.x.y
						c:
						+ o.ax.xa.axa
						+ o.x
				ax:
					xa:
						axa:
						+ o.z.y
				s1:
				= x.y.z
				s2:
				= a.b.z
				s3:
				= a.b.c.y.z
				x:
					y:
						z:
				z:
					y:
			"""
			
		let y = try await taskpaper.lemma("o.x.y")

		let y₂ = try #require(await y.rename(to: "Y"))
		
		#expect(await y₂.lexicon.taskpaper() == """
			o:
				a:
				+ o.ax
				+ o.x.Y.z
					b:
					+ o.ax.xa
					+ o.x.Y
						c:
						+ o.ax.xa.axa
						+ o.x
				ax:
					xa:
						axa:
						+ o.z.y
				s1:
				= x.Y.z
				s2:
				= a.b.z
				s3:
				= a.b.c.Y.z
				x:
					Y:
						z:
				z:
					y:
			""")
	}

	@Test
	func test_set_protonym() async throws {
		
		let taskpaper = """
			o:
				a:
				+ o
				b:
					x:
				c:
				d:
				= a
			"""
			
		let c = try await taskpaper.lemma("o.c")
		let x = try #require(await c.lexicon["o.a.b.x"])

		let c₂ = try #require(await c.set(protonym: x))

		#expect(await c₂.lexicon.taskpaper() == """
			o:
				a:
				+ o
				b:
					x:
				c:
				= a.b.x
				d:
				= a
			""")
	}
}

#endif
