//
// github.com/screensailor 2022
//

import Testing
import Foundation

@Suite

struct JSONClasses™ {
	
	@Test
	func test() async throws {

		var json = try await JSONClasses™.taskpaper.lexicon().json()
		json.date = Date(timeIntervalSinceReferenceDate: 0)

		let data = try JSONClasses.generate(json)
		let output = try data.string()
		let decoded = try JSONClasses.Decoder().decode(Lexicon.Graph.JSON.self, from: data)
		let root = try #require(decoded.classes.first { $0.id == "root" })
		let alias = try #require(decoded.classes.first { $0.id == "root.x_y_z" })
		let combined = try #require(decoded.classes.first { $0.id == "root.one.two.three.four" })

		#expect(decoded.date == Date(timeIntervalSinceReferenceDate: 0))
		#expect(decoded.name == "root")
		#expect(root.synonyms?.values["x_y_z"] == "a.b.b.b.b.b")
		#expect(root.references.map(Array.init) == [
			"root.a",
			"root.bad",
			"root.first",
			"root.good",
			"root.one",
			"root.a.b.b.b.b.b",
		])
		#expect(alias.protonym == "root.a.b.b.b.b.b")
		#expect(alias.references.map(Array.init) == ["root.a.b.b.b.b.b"])
		#expect(combined.references.map(Array.init) == [
			"root.a",
			"root.bad",
			"root.first",
			"root.good",
			"root.a_&_root.bad_&_root.first_&_root.good",
		])
		#expect(decoded.references?.contains("root.a_&_root.bad_&_root.first_&_root.good") == true)
		#expect(output.contains(
			#"""
			      "synonyms" : {
			        "x_y_z" : "a.b.b.b.b.b"
			      }
			"""#
		))
	}

	@Test
	func test_json_mixins_include_inherited_children() async throws {
		let json = try await """
		root:
			first:
				firstChild:
			shared:
				sharedChild:
			second:
			+ root.shared
				secondChild:
			instance:
			+ root.first
			+ root.second
		""".lexicon().json()

		let mixin = try #require(json.classes.first { $0.id == "root.first_&_root.second" }?.mixin)
		let children = try #require(mixin.children)

		#expect(mixin.type == "root.second")
		#expect(Array(children.values.keys) == ["secondChild", "sharedChild"])
		#expect(Array(children.values.values) == ["root.second.secondChild", "root.second.sharedChild"])
	}
}

extension JSONClasses™ {

	static let taskpaper = """
	root:
		a:
		+ root.a.b.c
			b:
			+ root.a
				c:
				+ root
		x_y_z:
		= a.b.b.b.b.b
		one:
		+ root.a
			two:
			+ root.a
			+ root.first
				three:
				+ root.a
				+ root.first
				+ root.bad
					four:
					+ root.a
					+ root.first
					+ root.bad
					+ root.good
		first:
			second:
				third:
		bad:
			worse:
				worst:
		good:
			better:
				best:
	"""
}
