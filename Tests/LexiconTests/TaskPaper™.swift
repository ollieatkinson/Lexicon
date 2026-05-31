//
// github.com/screensailor 2022
//

import Testing
@Suite
struct TaskPaper™ {
	
	@Test
	func test_root_only_taskpaper() async throws {
		
		let graph = try TaskPaper(taskpaper_example).decode()
		
		let taskpaper = TaskPaper.encode(graph)
		
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

		let sourceMap = try TaskPaper(text).sourceMap()

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
