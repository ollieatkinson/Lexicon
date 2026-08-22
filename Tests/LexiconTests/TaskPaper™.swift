//
// github.com/screensailor 2022
//

import Testing
@Suite
struct TaskPaper™ {

	@Test
	func test_root_only_taskpaper() async throws {

		let result = TaskPaper(taskpaper_example).parse()
		let graph = try result.document.graph(root: "a")

		let taskpaper = TaskPaper.encode(graph)

		#expect(result.diagnostics.filter { $0.code == .unknownLine }.count == 3)
		#expect(taskpaper == taskpaper_example_clean)
	}

	@Test
	func test_source_map_uses_taskpaper_structure_and_reference_ranges() throws {
		let text = """
		test:
			one:
			+ test.type
			= type.alias
			? @ test.default
		"""

		let sourceMap = TaskPaper(text).sourceMap()

		#expect(sourceMap.lines.map(\.nodePath) == [
			"test",
			"test.one",
			"test.one",
			"test.one",
			"test.one"
		])
		#expect(sourceMap.lines.map(\.content) == [
			.lemma(name: "test"),
			.lemma(name: "one"),
			.type(reference: "test.type"),
			.protonym(reference: "type.alias"),
			.defaultReference(reference: "test.default")
		])
		for line in sourceMap.references {
			let range = try #require(line.referenceRange)
			let reference = try #require(line.reference)
			#expect(text.substring(utf16: range) == reference)
		}
	}

	@Test
	func test_encode_sorts_type_references_lexicographically() {
		let graph = Lexicon.Graph(
			rootName: "root",
			root: .init(
				children: [
					"item": .init(
						type: ["root.z", "root.a", "root.m"]
					)
				]
			),
			date: .init(timeIntervalSinceReferenceDate: 0)
		)

		#expect(TaskPaper.encode(graph) == """
		root:
			item:
			+ root.a
			+ root.m
			+ root.z
		""")
	}

	@Test
	func lexicon_syntax_reports_lines_without_colons() throws {
		let result = TaskPaper("""
		root:
			ignored
			actual:
		""").parse()
		let graph = try result.document.graph(root: "root")

		#expect(result.diagnostics.map(\.code) == [.unknownLine])
		#expect(graph.root.children.keys == ["actual"])
	}

	@Test
	func plain_text_outline_syntax_accepts_lemmas_without_colons() throws {
		let graph = try TaskPaper("""
		root
			child
		""", options: .plainTextOutline).decodeGraph(root: "root")

		#expect(TaskPaper.encode(graph) == """
		root:
			child:
		""")
	}

	@Test
	func source_map_uses_selected_lemma_syntax() {
		#expect(TaskPaper("root").sourceMap().lines.isEmpty)
		#expect(
			TaskPaper("root", options: .plainTextOutline)
				.sourceMap()
				.lines
				.map(\.content) == [.lemma(name: "root")]
		)
	}
}

private let taskpaper_example = """
ignore me!
a:
	a1:
	+ a.a2
	+ a.a3
	+ a.a4

	a2:
		a21:
		ignore me!!
		+ a.a2
	a3:
	a4:
		a41:
			a411:
				a4111:
		a42:
		= a.a4.a41

		a43:
		= a.a4.a41.a411.a4111

b:
	ignore me too!!!
	+ b
"""

private let taskpaper_example_clean = """
a:
	a1:
	+ a.a2
	+ a.a3
	+ a.a4
	a2:
		a21:
		+ a.a2
	a3:
	a4:
		a41:
			a411:
				a4111:
		a42:
		= a.a4.a41
		a43:
		= a.a4.a41.a411.a4111
"""

private extension String {
	func substring(utf16 range: Range<Int>) -> String? {
		let lower = utf16.index(utf16.startIndex, offsetBy: range.lowerBound)
		let upper = utf16.index(utf16.startIndex, offsetBy: range.upperBound)
		guard
			let start = String.Index(lower, within: self),
			let end = String.Index(upper, within: self)
		else {
			return nil
		}
		return String(self[start..<end])
	}
}
