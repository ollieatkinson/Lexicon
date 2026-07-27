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
			
		let lexicon = try await taskpaper.lexicon()
		let src = try #require(await lexicon[Lemma.ID(parsing: "o.copy.a.b")])
		let dst = try #require(await lexicon["o.paste.a"])

		_ = try await lexicon.insert(src.graph, under: dst)
		
		#expect(await lexicon.taskpaper() == """
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
			
		let lexicon = try await taskpaper.lexicon()
		let src = try #require(await lexicon[Lemma.ID(parsing: "o.a.b.x")])
		let dst = try #require(await lexicon["o.a"])

		_ = try await lexicon.insert(src.graph, under: dst)

		let actual = await lexicon.taskpaper()
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

		let lexicon = try await taskpaper.lexicon()
		let src = try #require(await lexicon[Lemma.ID(parsing: "o.source.alias")])
		let dst = try #require(await lexicon["o.destination"])

		_ = try await lexicon.insert(src.graph, under: dst)

		let actual = await lexicon.taskpaper()
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
				b:
				c:
				d:
			"""
			
		let lexicon = try await taskpaper.lexicon()
		let b = try #require(await lexicon["o.b"])
		try await lexicon.delete(b)
		
		let actual = await lexicon.taskpaper()
		#expect(actual == """
			o:
				a:
				c:
				d:
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
			
		let lexicon = try await taskpaper.lexicon()
		let a = try #require(await lexicon["o.a"])
		let o = await lexicon.root

		_ = try await lexicon.removeType(o, from: a)
		
		#expect(await lexicon.taskpaper() == """
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
			
		let lexicon = try await taskpaper.lexicon()
		let c = try #require(await lexicon["o.c"])

		_ = try await lexicon.clearProtonym(of: c)
		
		#expect(await lexicon.taskpaper() == """
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
			
		let lexicon = try await taskpaper.lexicon()
		let y = try #require(await lexicon["o.x.y"])

		_ = try await lexicon.rename(y, to: "Y")

		let actual = await lexicon.taskpaper()
		#expect(actual == """
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
			""", "actual:\n\(actual)")
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
			
		let lexicon = try await taskpaper.lexicon()
		let c = try #require(await lexicon["o.c"])
		let x = try #require(await lexicon["o.a.b.x"])

		_ = try await lexicon.setProtonym(x, of: c)

		#expect(await lexicon.taskpaper() == """
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
