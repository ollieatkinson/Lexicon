//
// github.com/screensailor 2026
//

import Benchmark
import Foundation
import Lexicon
import _Collections

let benchmarks: @Sendable () -> Void = {
	Benchmark("TaskPaper document decode", configuration: benchmarkConfiguration()) { benchmark in
		let taskpaper = makeTaskpaper()

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(try TaskPaper(taskpaper).decodeDocument())
		}
		benchmark.stopMeasurement()
	}

	Benchmark("TaskPaper document encode", configuration: benchmarkConfiguration()) { benchmark in
		let document = try makeDocument()

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(TaskPaper.encode(document))
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Document JSON encode", configuration: benchmarkConfiguration()) { benchmark in
		let encoder = JSONEncoder()
		let document = try makeDocument()

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(try encoder.encode(document.json))
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Document JSON decode", configuration: benchmarkConfiguration()) { benchmark in
		let decoder = JSONDecoder()
		let documentJSON = try JSONEncoder().encode(try makeDocument().json)

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(try Lexicon.Document(decoder.decode(Lexicon.Document.JSON.self, from: documentJSON)))
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Search index build", configuration: benchmarkConfiguration()) { benchmark in
		let document = try makeDocument(roots: 2, children: 40, grandchildren: 3)
		let options = Lexicon.Search.Options(mode: .hybrid)

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(Lexicon.Search.Index(document: document, options: options))
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Hybrid search query", configuration: benchmarkConfiguration()) { benchmark in
		let document = try makeDocument(roots: 1, children: 20, grandchildren: 2)
		let index = Lexicon.Search.Index(document: document, options: .init(mode: .hybrid))
		let queries = [
			"root node child",
			"session state value",
			"local lexicon type",
			"node metadata root",
		]
		var queryIndex = 0

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(index.search(queries[queryIndex % queries.count]))
			queryIndex += 1
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Hybrid search query warmed index", configuration: benchmarkConfiguration()) { benchmark in
		let document = try makeDocument(roots: 1, children: 20, grandchildren: 2)
		let index = Lexicon.Search.Index(document: document, options: .init(mode: .hybrid))
		let queries = [
			"root node child",
			"session state value",
			"local lexicon type",
			"node metadata root",
		]
		var queryIndex = 0

		for query in queries {
			blackHole(index.search(query))
		}

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(index.search(queries[queryIndex % queries.count]))
			queryIndex += 1
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Full-scope search materialization", configuration: benchmarkConfiguration()) { benchmark in
		let document = try makeInheritedDocument(nodes: 10)
		let index = Lexicon.Search.Index(
			document: document,
			options: .init(
				mode: .hybrid,
				scope: .full,
				bounds: .init(depth: 3, candidates: 10, budget: 500)
			)
		)

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(try await index.search("shared inherited value", in: document))
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Document composition", configuration: benchmarkConfiguration()) { benchmark in
		let fixture = try makeCompositionFixture(imports: 8, children: 30)

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(try fixture.local.composed(resolving: fixture.resolver))
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Document merge", configuration: benchmarkConfiguration()) { benchmark in
		let documents = try makeMergeDocuments(count: 8, children: 40)

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(Lexicon.Document.merge(documents))
		}
		benchmark.stopMeasurement()
	}

	Benchmark("CRDT materialize operation set", configuration: benchmarkConfiguration()) { benchmark in
		let replica = try makeReplica(nodes: 320)

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(try replica.materialized())
		}
		benchmark.stopMeasurement()
	}

	Benchmark("Graph breadth-first traversal", configuration: benchmarkConfiguration()) { benchmark in
		let document = try makeDocument(roots: 1, children: 160, grandchildren: 4)
		let root = try document.roots["root0"].try()

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			blackHole(root.graphTraversal(.breadthFirst).reduce(0) { count, _ in count + 1 })
		}
		benchmark.stopMeasurement()
	}

	Benchmark("SortedDictionary descending inserts", configuration: benchmarkConfiguration()) { benchmark in
		let keys = (0..<2_000).map { String(format: "key-%04d", $0) }.reversed()

		benchmark.startMeasurement()
		for _ in benchmark.scaledIterations {
			var dictionary = SortedDictionary<String, Int>()
			for (offset, key) in keys.enumerated() {
				dictionary[key] = offset
			}
			blackHole(dictionary.count)
		}
		benchmark.stopMeasurement()
	}
}

private func benchmarkConfiguration() -> Benchmark.Configuration {
	.init(
		metrics: [
			.wallClock,
			.throughput,
			.mallocCountTotal,
			.allocatedResidentMemory,
		],
		maxDuration: .milliseconds(500),
		maxIterations: 1_000
	)
}

private func makeDocument() throws -> Lexicon.Document {
	try makeDocument(roots: 4, children: 40, grandchildren: 4)
}

private func makeDocument(roots: Int, children: Int, grandchildren: Int) throws -> Lexicon.Document {
	try TaskPaper(makeTaskpaper(roots: roots, children: children, grandchildren: grandchildren)).decodeDocument()
}

private func makeTaskpaper(
	roots: Int = 4,
	children: Int = 40,
	grandchildren: Int = 4
) -> String {
	var lines: [String] = []

	for root in stride(from: roots - 1, through: 0, by: -1) {
		let rootName = "root\(root)"
		lines.append("\(rootName):")
		lines.append("\t# root \(root) comment")
		lines.append("\t> root \(root) note")
		lines.append("\t@ local\(root).lexicon")
		lines.append("\ttype:")

		for child in stride(from: children - 1, through: 0, by: -1) {
			let childName = "node\(child)"
			lines.append("\t\(childName):")
			lines.append("\t? {\"index\":\(child),\"root\":\(root)}")
			lines.append("\t+ \(rootName).type")

			if root > 0 {
				lines.append("\t+ root0.type")
			}

			for grandchild in stride(from: grandchildren - 1, through: 0, by: -1) {
				lines.append("\t\tchild\(grandchild):")
				lines.append("\t\t? \"\(rootName)-\(childName)-\(grandchild)\"")
			}
		}
	}

	return lines.joined(separator: "\n")
}

private func makeInheritedDocument(nodes: Int) throws -> Lexicon.Document {
	var lines = [
		"root:",
		"\ttype:",
		"\t\tbase:",
		"\t\t\tshared:",
		"\t\t\t\tvalue:",
		"\t\t\tbranch:",
		"\t\t\t\tleaf:",
	]

	for index in 0..<nodes {
		lines.append("\tnode\(index):")
		lines.append("\t+ root.type.base")
		lines.append("\t? \"shared inherited value \(index)\"")
		lines.append("\t\tlocal\(index):")
		lines.append("\t\t+ root.type.base.branch")
	}

	return try TaskPaper(lines.joined(separator: "\n")).decodeDocument()
}

private func makeCompositionFixture(
	imports: Int,
	children: Int
) throws -> (local: Lexicon.Document, resolver: DictionaryLexiconImportResolver) {
	var localLines: [String] = []
	var importedDocuments: [String: Lexicon.Document] = [:]

	for index in 0..<imports {
		let reference = "imported\(index).lexicon"
		localLines.append("@ \(reference)")
		importedDocuments[reference] = try makeImportedDocument(name: "external\(index)", children: children)
	}

	localLines.append("root:")
	for index in 0..<imports {
		let reference = "imported\(index).lexicon"
		localLines.append("\tconnection\(index):")
		localLines.append("\t@ \(reference)")
		localLines.append("\t\tlocal:")
		localLines.append("\t\t? \"local \(index)\"")
	}

	return (
		try TaskPaper(localLines.joined(separator: "\n")).decodeDocument(),
		DictionaryLexiconImportResolver(importedDocuments)
	)
}

private func makeImportedDocument(name: String, children: Int) throws -> Lexicon.Document {
	var lines = [
		"\(name):",
		"\ttype:",
		"\t\tvalue:",
	]

	for child in 0..<children {
		lines.append("\timported\(child):")
		lines.append("\t+ \(name).type.value")
		lines.append("\t? \"imported \(child)\"")
	}

	return try TaskPaper(lines.joined(separator: "\n")).decodeDocument()
}

private func makeMergeDocuments(count: Int, children: Int) throws -> [Lexicon.Document] {
	try (0..<count).map { document in
		var lines = [
			"root:",
			"\ttype:",
			"\t\tvalue:",
		]

		for child in 0..<children {
			lines.append("\tnode\(child):")
			lines.append("\t+ root.type.value")
			lines.append("\t? \"document \(document) child \(child)\"")
			lines.append("\t\tchild\(document):")
		}

		return try TaskPaper(lines.joined(separator: "\n")).decodeDocument()
	}
}

private func makeReplica(nodes: Int) throws -> Lexicon.CRDT.Replica {
	var replica = Lexicon.CRDT.Replica()
	var counter: UInt64 = 0

	func apply(_ kind: Lexicon.CRDT.Kind) throws {
		counter += 1
		try replica.apply(.init(
			kind,
			id: .init(timestamp: counter, actor: "benchmark")
		))
	}

	try apply(.setDocumentDate(Date(timeIntervalSince1970: 0)))
	try apply(.createNode(path: "root", parentPath: nil, name: "root"))
	try apply(.createNode(path: "root.type", parentPath: "root", name: "type"))
	try apply(.createNode(path: "root.type.value", parentPath: "root.type", name: "value"))

	for index in 0..<nodes {
		let path = try Lemma.ID(parsing: "root.node\(index)")
		let name = try Lemma.Name(validating: "node\(index)")
		try apply(.createNode(path: path, parentPath: "root", name: name))
		try apply(.addTypeReference(path: path, type: "root.type.value"))
		try apply(.setDefaultValue(path: path, value: .literal(.string("value \(index)"))))
		try apply(.insertNote(path: path, after: nil, text: "note \(index)"))
	}

	return replica
}
